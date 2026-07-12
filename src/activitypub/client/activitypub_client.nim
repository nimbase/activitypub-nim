## C2S (Client-to-Server) client for ActivityPub.
##
## A `Client` holds an actor's identity (ID, keys, inbox/outbox URLs)
## and provides methods to send activities — either to the actor's own
## outbox (C2S) or directly to remote inboxes (S2S-style direct delivery).
##
## Usage:
##   let client = newClient(actorJson, myPrivateKeyHex)
##   discard client.follow("@user@remote.social")
##   discard client.like("@user@remote.social", "https://remote.social/posts/1")
##   discard client.postNote("Hello World", to = @["@friend@other.social"])

import std/[httpclient, strutils]
import openparser/json
import ../datatypes/[metatypes, coretypes, activitytypes]
import ../server/[httpsig, federation]
import ../builders/activity_builders
import ../discovery/webfinger

export metatypes, coretypes, activitytypes

type
  Client* = object
    id*: string
    inbox*: string
    outbox*: string
    keyId*: string
    privateKeyHex*: string

proc newClient*(actorJson: JsonNode; privateKeyHex: string): Client =
  ## Creates a `Client` from a parsed actor JSON document and an Ed25519
  ## secret key in hex (128 hex chars).
  ##
  ## Extracts the actor's ID, inbox, outbox, and constructs the keyId as
  ## `{actorId}#main-key`.
  let actorId = actorJson{"id"}.getStr
  Client(
    id: actorId,
    inbox: actorJson{"inbox"}.getStr,
    outbox: actorJson{"outbox"}.getStr,
    keyId: actorId & "#main-key",
    privateKeyHex: privateKeyHex
  )

proc newClient*(actorId, privateKeyHex: string): Client =
  ## Creates a `Client` by fetching the actor's JSON document from their
  ## actor URL first, then constructing from the fetched document.
  ##
  ## Raises `IOError` if the actor is unreachable.
  result = newClient(fetchObject(actorId), privateKeyHex)

proc sendTo*(client: Client; activity: JsonNode; inboxUrl: string): FederationResult[string] =
  ## Sends a signed activity to a specific inbox URL.
  ##
  ## Signs the request with the client's Ed25519 key (HTTP Signatures draft-cavage-12)
  ## and POSTs the JSON body. Returns `FederationResult` — check `.success` to determine
  ## whether delivery succeeded.
  try:
    let body = $activity
    let parsedUrl = parseUri(inboxUrl)
    let path = if parsedUrl.path.len > 0: parsedUrl.path else: "/"
    let host = parsedUrl.hostname
    let sigResult = signRequest("POST", path, host, body, client.keyId, client.privateKeyHex)
    let httpClient = newHttpClient()
    try:
      httpClient.headers = newHttpHeaders({
        "Content-Type": "application/activity+json; charset=utf-8",
        "Host": host,
        "Date": sigResult.date,
        "Digest": sigResult.digest,
        "Signature": sigResult.signature,
        "User-Agent": "activitypub-nim-c2s/0.1.0"
      })
      try:
        let resp = httpClient.post(inboxUrl, body)
        let code = resp.code
        if code == Http202 or code == Http200 or code == Http201:
          result = FederationResult[string](success: true, data: $code)
        else:
          result = FederationResult[string](
            success: false,
            error: "send failed (" & $code & "): " & resp.body
          )
      except CatchableError:
        result = FederationResult[string](
          success: false,
          error: "send failed: " & getCurrentExceptionMsg()
        )
    finally:
      httpClient.close()
  except CatchableError:
    result = FederationResult[string](
      success: false,
      error: "send failed: " & getCurrentExceptionMsg()
    )

proc resolveActorUrl*(target: string): string =
  ## Resolves an actor handle (`@user@domain` or `user@domain`) to an actor URL.
  ##
  ## If `target` is already an HTTP(S) URL, it's returned as-is.
  if target.startsWith("https://") or target.startsWith("http://"):
    target
  else:
    let (url, _) = resolveActor(target)
    url

proc resolveInbox*(target: string): string =
  ## Resolves an actor handle or URL to the actor's inbox URL.
  ##
  ## - `@user@domain` → WebFinger → actor fetch → inbox URL
  ## - `https://domain/user` → actor fetch → inbox URL
  ##
  ## Raises `ValueError` if the actor has no inbox.
  let actorUrl = resolveActorUrl(target)
  let actorJson = fetchObject(actorUrl)
  result = actorJson{"inbox"}.getStr
  if result.len == 0:
    raise newException(ValueError, "actor has no inbox: " & actorUrl)

proc trySend(client: Client; activity: JsonNode; inbox: string): FederationResult[string] =
  try:
    result = sendTo(client, activity, inbox)
  except CatchableError:
    result = FederationResult[string](
      success: false,
      error: "send failed: " & getCurrentExceptionMsg()
    )

proc tryResolveInbox(target: string): FederationResult[string] =
  try:
    result = FederationResult[string](success: true, data: resolveInbox(target))
  except CatchableError:
    result = FederationResult[string](
      success: false,
      error: "failed to resolve inbox: " & getCurrentExceptionMsg()
    )

proc follow*(client: Client; targetHandleOrUrl: string): FederationResult[string] =
  ## Sends a `Follow` activity to a remote actor's inbox.
  ##
  ## Resolves the target's inbox, builds the Follow activity, and delivers it.
  let inbox = tryResolveInbox(targetHandleOrUrl)
  if not inbox.success: return inbox
  let activity = buildFollow(client.id, targetHandleOrUrl)
  trySend(client, toJsonNode(activity), inbox.data)

proc unfollow*(client: Client; targetHandleOrUrl: string): FederationResult[string] =
  ## Sends an `Undo(Follow)` activity to a remote actor's inbox.
  ##
  ## Builds a Follow for the target, wraps it in an Undo, and delivers to the target's inbox.
  let inbox = tryResolveInbox(targetHandleOrUrl)
  if not inbox.success: return inbox
  let follow = buildFollow(client.id, targetHandleOrUrl)
  let activity = buildUndo(client.id, follow)
  trySend(client, toJsonNode(activity), inbox.data)

proc like*(client: Client; actorHandleOrUrl, objectUrl: string): FederationResult[string] =
  ## Sends a `Like` activity to an actor's inbox.
  ##
  ## - `actorHandleOrUrl`: the author of the object being liked (their inbox receives the Like)
  ## - `objectUrl`: the URL of the object being liked
  let inbox = tryResolveInbox(actorHandleOrUrl)
  if not inbox.success: return inbox
  let activity = buildLike(client.id, objectUrl)
  trySend(client, toJsonNode(activity), inbox.data)

proc unlike*(client: Client; actorHandleOrUrl, objectUrl: string): FederationResult[string] =
  ## Sends an `Undo(Like)` activity to an actor's inbox.
  ##
  ## - `actorHandleOrUrl`: the author of the object being unliked
  ## - `objectUrl`: the URL of the object being unliked
  let inbox = tryResolveInbox(actorHandleOrUrl)
  if not inbox.success: return inbox
  let like = buildLike(client.id, objectUrl)
  let activity = buildUndo(client.id, like)
  trySend(client, toJsonNode(activity), inbox.data)

proc postNote*(client: Client; content: string; to: seq[string] = @[];
               cc: seq[string] = @[]; summary: string = ""): FederationResult[string] =
  ## Posts a new `Note` wrapped in a `Create` activity to the client's own outbox.
  ##
  ## Builds the Note and Create, then POSTs to the actor's outbox endpoint.
  ## The server receiving the outbox POST handles further federation.
  let note = buildNote(content, client.id, summary, to, cc)
  let create = buildCreate(client.id, note)
  trySend(client, toJsonNode(create), client.outbox)
