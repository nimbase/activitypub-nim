## ActivityPub HTTP server built on powpow.
##
## Serves actor profiles, WebFinger, inbox, outbox, followers, and following
## endpoints. Uses `InboxDispatcher` for receiving activities and `ActivityStore`
## for data persistence.
##
## Usage:
##   let store = newActivityStore()
##   discard store.registerActor("alice", "example.com", "Alice")
##   var server = newActivityPubServer("example.com", store)
##   server.register[Follow]("Follow", proc (f: Follow, by: string): InboxResult =
##     InboxResult(success: true, status: 202)
##   )
##   server.start(Port(9000))

import std/[httpcore, strutils]
import pkg/powpow/proto
import pkg/openparser/json # don't panic, exports std/json too

import ../datatypes/[metatypes, collectiontypes]
import ../discovery/webfinger
import ./[federation, inbox, storage]

export metatypes, collectiontypes, webfinger, federation, inbox, storage

type
  ActivityPubServer* = object
    domain*: string
    store*: ActivityStore
    httpServer: HttpServer
    dispatcher*: InboxDispatcher

proc newActivityPubServer*(domain: string; store: ActivityStore): ActivityPubServer =
  ## Creates a new ActivityPub HTTP server.
  ##
  ## - `domain`: the server domain (e.g. `"example.com"`)
  ## - `store`: an `ActivityStore` with registered actors
  let httpServer = newHttpServer()
  let dispatcher = newDispatcher(proc (keyId: string): JsonNode =
    try:
      result = store.findActorByKeyId(keyId).json
    except:
      result = nil
  )
  ActivityPubServer(
    domain: domain,
    store: store,
    httpServer: httpServer,
    dispatcher: dispatcher
  )

proc register*[T](server: var ActivityPubServer; activityType: string;
                  handler: proc(activity: T, verifiedBy: string): InboxResult) =
  ## Delegates to `InboxDispatcher.register` — registers a typed handler
  ## for a specific activity type (e.g. `"Follow"`, `"Create"`).
  server.dispatcher.register[T](activityType, handler)

proc handleWebfinger(server: ActivityPubServer; res: HttpResponse; query: string) =
  let resource = if query.startsWith("resource="): query[9..^1] else: ""
  if resource.len == 0:
    res.sendError(Http400, "Missing resource parameter")
    return
  try:
    let actorData = server.store.findActorByAcctUri(resource)
    let jrd = buildJrd(resource, actorData.json["id"].getStr)
    res.status(Http200)
      .header("Content-Type", "application/jrd+json")
      .send($jrd)
  except KeyError, ValueError:
    res.sendError(Http404, "Actor not found")

proc handleActor(server: ActivityPubServer; res: HttpResponse; username: string) =
  try:
    let actorData = server.store.findActorByUsername(username)
    res.status(Http200)
      .header("Content-Type", "application/activity+json")
      .header("Access-Control-Allow-Origin", "*")
      .send($actorData.json)
  except KeyError:
    res.sendError(Http404, "Actor not found")

proc handleInbox(server: ActivityPubServer; req: HttpRequest; res: HttpResponse; username: string) =
  try:
    discard server.store.findActorByUsername(username)
  except KeyError:
    res.sendError(Http404, "Actor not found")
    return
  let body = req.getBodyString()
  var headerList: seq[(string, string)]
  for k, v in req.getHeaders().pairs:
    headerList.add((k, v))
  let inboxPath = "/users/" & username & "/inbox"
  let inboxResult = server.dispatcher.handle(body, headerList, inboxPath)
  if inboxResult.success:
    res.status(Http202).send()
  else:
    let code = case inboxResult.status
      of 400: Http400
      of 401: Http401
      of 500: Http500
      else: Http500
    res.sendError(code, inboxResult.error)

proc serveCollection(server: ActivityPubServer; res: HttpResponse;
                     items: seq[JsonNode]; collectionId: string) =
  let totalItems = items.len
  var json = %*{
    "@context": "https://www.w3.org/ns/activitystreams",
    "id": collectionId,
    "type": "OrderedCollection",
    "totalItems": totalItems,
    "first": collectionId & "?page=1"
  }
  if totalItems > 0:
    json["orderedItems"] = %*items
  res.status(Http200)
    .header("Content-Type", "application/activity+json")
    .header("Access-Control-Allow-Origin", "*")
    .send($json)

proc handleOutbox(server: ActivityPubServer; res: HttpResponse; username: string) =
  try:
    let actorData = server.store.findActorByUsername(username)
    let items = server.store.getOutboxItems(username)
    let collectionId = actorData.json["id"].getStr & "/outbox"
    serveCollection(server, res, items, collectionId)
  except KeyError:
    res.sendError(Http404, "Actor not found")

proc handleFollowers(server: ActivityPubServer; res: HttpResponse; username: string) =
  try:
    let actorData = server.store.findActorByUsername(username)
    let urls = server.store.getFollowerUrls(username)
    var items: seq[JsonNode]
    for u in urls:
      items.add(%* u)
    let collectionId = actorData.json["id"].getStr & "/followers"
    serveCollection(server, res, items, collectionId)
  except KeyError:
    res.sendError(Http404, "Actor not found")

proc handleFollowing(server: ActivityPubServer; res: HttpResponse; username: string) =
  try:
    let actorData = server.store.findActorByUsername(username)
    let urls = server.store.getFollowingUrls(username)
    var items: seq[JsonNode]
    for u in urls:
      items.add(%* u)
    let collectionId = actorData.json["id"].getStr & "/following"
    serveCollection(server, res, items, collectionId)
  except KeyError:
    res.sendError(Http404, "Actor not found")

proc route(server: ActivityPubServer; req: HttpRequest; res: HttpResponse) =
  let meth = req.getMethod()
  let path = req.getPath()
  let parts = path.split('/')
  if parts.len >= 3 and parts[1] == ".well-known" and parts[2] == "webfinger":
    if meth == HttpGet:
      server.handleWebfinger(res, req.getQuery())
    else:
      res.sendError(Http405, "Method Not Allowed")
  elif parts.len >= 3 and parts[1] == "users":
    let username = parts[2]
    if parts.len == 3:
      if meth == HttpGet:
        server.handleActor(res, username)
      else:
        res.sendError(Http405, "Method Not Allowed")
    elif parts.len == 4:
      case parts[3]:
      of "inbox":
        if meth == HttpPost:
          server.handleInbox(req, res, username)
        else:
          res.sendError(Http405, "Method Not Allowed")
      of "outbox":
        if meth == HttpGet:
          server.handleOutbox(res, username)
        else:
          res.sendError(Http405, "Method Not Allowed")
      of "followers":
        if meth == HttpGet:
          server.handleFollowers(res, username)
        else:
          res.sendError(Http405, "Method Not Allowed")
      of "following":
        if meth == HttpGet:
          server.handleFollowing(res, username)
        else:
          res.sendError(Http405, "Method Not Allowed")
      else:
        res.sendError(Http404, "Not Found")
    else:
      res.sendError(Http404, "Not Found")
  else:
    res.sendError(Http404, "Not Found")

proc start*(server: ActivityPubServer; port: Port) =
  ## Starts the HTTP server on the given `port`.
  ##
  ## Blocks the current thread. Uses powpow's event loop.
  server.httpServer.start(
    proc (req: HttpRequest, res: HttpResponse) {.gcsafe.} =
      {.cast(gcsafe).}:
        server.route(req, res),
    port
  )

proc stop*(server: ActivityPubServer) =
  ## Stops the HTTP server and closes all connections.
  server.httpServer.stop()
