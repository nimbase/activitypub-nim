## Inbox request dispatcher — validates HTTP Signatures, parses incoming
## activities, and routes them to user-registered handlers by activity type.
##
## Usage:
##   var inbox = newDispatcher(fetchActor)
##   inbox.register[Follow]("Follow", proc (f: Follow, by: string): InboxResult =
##     InboxResult(success: true, status: 202)
##   )
##   let result = inbox.handle(body, headers, "/inbox")

import std/tables
import openparser/json
import ../datatypes/[metatypes, activitytypes]
import ./federation

export metatypes, activitytypes

type
  InboxResult* = object
    success*: bool
    status*: int
    error*: string

  FetchActorCallback* = proc(keyId: string): JsonNode
  HandlerFunc = proc(activity: JsonNode, verifiedBy: string): InboxResult

  InboxDispatcher* = object
    fetchActor*: FetchActorCallback
    handlers: Table[string, HandlerFunc]
    defaultHandler: HandlerFunc

proc register*[T](d: var InboxDispatcher; activityType: string;
                  handler: proc(activity: T, verifiedBy: string): InboxResult) =
  ## Registers a typed handler for a specific activity type (e.g., `"Follow"`, `"Create"`).
  ##
  ## The handler receives the fully-typed Nim object (e.g. `Follow`, `Create`) parsed
  ## automatically from the incoming JSON body, plus the `verifiedBy` keyId of the sender.
  d.handlers[activityType] = proc(activity: JsonNode, verifiedBy: string): InboxResult =
    try:
      let typed = fromJson($activity, T)
      handler(typed, verifiedBy)
    except CatchableError:
      InboxResult(success: false, status: 400,
                  error: "failed to parse activity: " & getCurrentExceptionMsg())

proc registerDefault*(d: var InboxDispatcher; handler: HandlerFunc) =
  ## Registers a fallback handler for any unregistered activity type.
  ##
  ## The handler receives the raw `JsonNode` and the sender's `verifiedBy` keyId.
  ## If no default is set, unregistered types silently return HTTP 202.
  d.defaultHandler = handler

proc newDispatcher*(fetchActor: FetchActorCallback): InboxDispatcher =
  ## Creates an `InboxDispatcher` with the given `fetchActor` callback for
  ## HTTP Signature key resolution.
  ##
  ## `fetchActor` takes a keyId (e.g. `"https://example.com/user/alice#main-key"`)
  ## and returns the actor's JSON document containing their public key.
  InboxDispatcher(fetchActor: fetchActor)

proc handle*(d: InboxDispatcher; body: string;
             headers: seq[(string, string)];
             path: string): InboxResult =
  ## Validates, parses, and dispatches an incoming inbox request.
  ##
  ## 1. Verifies the HTTP Signature via `verifyInboxRequest`
  ## 2. Parses the JSON body and extracts the `type` field
  ## 3. Routes to the registered typed handler or default handler
  ## 4. Returns an `InboxResult` with HTTP status code and optional error
  try:
    let verification = verifyInboxRequest(body, headers, path, d.fetchActor)
    if not verification.success:
      return InboxResult(success: false, status: 401, error: verification.error)
    let verifiedBy = verification.data
    let activity = fromJson(body)
    let typeStr = activity{"type"}.getStr("")
    if typeStr.len == 0:
      return InboxResult(success: false, status: 400, error: "activity has no type field")
    var handler: HandlerFunc = nil
    if d.handlers.hasKey(typeStr):
      handler = d.handlers[typeStr]
    elif not d.defaultHandler.isNil:
      handler = d.defaultHandler
    if handler.isNil:
      return InboxResult(success: true, status: 202)
    try:
      result = handler(activity, verifiedBy)
    except CatchableError:
      result = InboxResult(success: false, status: 500,
                          error: "handler raised: " & getCurrentExceptionMsg())
  except CatchableError:
    result = InboxResult(success: false, status: 500,
                        error: "dispatch failed: " & getCurrentExceptionMsg())
