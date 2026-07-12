## Federation engine — sending, receiving, and resolving ActivityPub objects.
##
## Ties together WebFinger, HTTP Signatures, and crypto to:
## - Resolve remote actors (WebFinger → actor fetch → public key)
## - Deliver activities to remote inboxes (signed POST)
## - Verify incoming inbox requests
## - Fetch remote objects

import std/[json, uri, httpclient, strutils, tables]
import ../discovery/webfinger
import ./httpsig
import ../datatypes/metatypes

export webfinger, httpsig

type
  RemoteActor* = object
    id*: string
    inbox*: string
    sharedInbox*: string
    publicKey*: metatypes.PublicKey
    rawJson*: JsonNode

  FederationResult*[T] = object
    success*: bool
    data*: T
    error*: string

proc resolveRemoteActor*(handle: string): RemoteActor =
  ## Resolves a remote actor by handle (e.g. `@user@domain`) into a `RemoteActor`.
  ##
  ## Performs WebFinger discovery, fetches the actor JSON, extracts the inbox,
  ## sharedInbox, and public key. Raises `ValueError` if the actor has no inbox
  ## or no public key.
  let (actorUrl, actorJson) = resolveActor(handle)
  let inbox = actorJson{"inbox"}.getStr
  if inbox.len == 0:
    raise newException(ValueError, "actor has no inbox: " & actorUrl)
  let sharedInbox =
    if actorJson{"endpoints"}{"sharedInbox"}.kind != JNull:
      actorJson{"endpoints"}{"sharedInbox"}.getStr
    else: ""
  let pkNode = actorJson{"publicKey"}
  var pubKey: metatypes.PublicKey
  if pkNode.kind == JArray and pkNode.len > 0:
    let first = pkNode[0]
    pubKey = metatypes.PublicKey(
      id: some(first{"id"}.getStr),
      owner: some(first{"owner"}.getStr),
      publicKeyPem: some(first{"publicKeyPem"}.getStr)
    )
  elif pkNode.kind == JObject:
    pubKey = metatypes.PublicKey(
      id: some(pkNode{"id"}.getStr),
      owner: some(pkNode{"owner"}.getStr),
      publicKeyPem: some(pkNode{"publicKeyPem"}.getStr)
    )
  else:
    raise newException(ValueError, "actor has no publicKey: " & actorUrl)
  RemoteActor(
    id: actorUrl,
    inbox: inbox,
    sharedInbox: sharedInbox,
    publicKey: pubKey,
    rawJson: actorJson
  )

proc deliverActivity*(remote: RemoteActor, secretKeyHex: string,
                       activityJson: JsonNode,
                       keyId: string = ""): FederationResult[string] =
  ## Delivers an activity to a remote actor's inbox via a signed HTTP POST request.
  ##
  ## Signs the request with Ed25519 HTTP Signatures (Date, Digest, Signature headers).
  ## Returns a `FederationResult` indicating success (HTTP 200/201/202 accepted) or failure.
  let activityBody = $activityJson
  let parsedUri = parseUri(remote.inbox)
  let path = if parsedUri.path.len > 0: parsedUri.path else: "/"
  let host = parsedUri.hostname
  let effectiveKeyId = if keyId.len > 0: keyId else: remote.id & "#main-key"
  let sigResult = signRequest("POST", path, host, activityBody,
                                effectiveKeyId, secretKeyHex)
  let client = newHttpClient()
  try:
    client.headers = newHttpHeaders({
      "Content-Type": "application/activity+json; charset=utf-8",
      "Host": host,
      "Date": sigResult.date,
      "Digest": sigResult.digest,
      "Signature": sigResult.signature,
      "User-Agent": "activitypub-nim/0.1.0"
    })
    try:
      let resp = client.post(remote.inbox, activityBody)
      let code = resp.code
      if code == Http202 or code == Http200 or code == Http201:
        result = FederationResult[string](success: true, data: $code)
      else:
        result = FederationResult[string](
          success: false,
          error: "delivery failed (" & $code & "): " & resp.body
        )
    except CatchableError:
      result = FederationResult[string](
        success: false,
        error: "delivery failed: " & getCurrentExceptionMsg()
      )
  finally:
    client.close()

proc verifyInboxRequest*(body: string,
                          headers: seq[(string, string)],
                          path: string,
                          fetchActor: proc(keyId: string): JsonNode
                         ): FederationResult[string] =
  ## Verifies an incoming inbox request by checking its HTTP Signature.
  ##
  ## `fetchActor` is a callback that returns an actor JSON document for a given
  ## keyId (used to look up the sender's public key). Returns the verified keyId
  ## on success, or an error message on failure.
  var hmap = {"host": ""}.toTable()
  for (k, v) in headers:
    hmap[k.toLowerAscii()] = v
  if not hmap.hasKey("signature"):
    return FederationResult[string](success: false, error: "missing Signature header")
  let sigParams = parseSignatureHeader(hmap["signature"])
  if sigParams.keyId.len == 0:
    return FederationResult[string](success: false,
                                     error: "missing keyId in Signature header")
  let actorJson = fetchActor(sigParams.keyId)
  if actorJson.isNil or actorJson.kind == JNull:
    return FederationResult[string](success: false,
                                     error: "could not fetch actor: " & sigParams.keyId)
  if verifyRequest("POST", path, body, headers, actorJson):
    result = FederationResult[string](success: true, data: sigParams.keyId)
  else:
    result = FederationResult[string](success: false,
                                       error: "signature verification failed")

proc fetchObject*(url: string): JsonNode =
  ## Fetches an ActivityPub object (actor, note, activity, etc.) by URL.
  ##
  ## Sends an `Accept: application/activity+json` GET request.
  ## Raises `IOError` on HTTP failure or network error.
  let client = newHttpClient()
  try:
    client.headers = newHttpHeaders({
      "Accept": "application/activity+json",
      "User-Agent": "activitypub-nim/0.1.0"
    })
    try:
      let resp = client.get(url)
      if resp.code != Http200:
        raise newException(IOError, "failed to fetch object (" & $resp.code & "): " & url)
      result = parseJson(resp.body)
    except CatchableError:
      raise newException(IOError, "failed to fetch object: " & getCurrentExceptionMsg())
  finally:
    client.close()
