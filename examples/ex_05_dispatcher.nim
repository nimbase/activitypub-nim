## Example 05 — Inbox dispatcher
##
## Set up an InboxDispatcher, register typed handlers for activities,
## and process signed inbox requests end-to-end.
##
##   nim c -r examples/ex_05_dispatcher.nim

import ../src/activitypub

# --- Setup: our local actor ---
let (localPub, localSecret) = generateEd25519KeypairPem()

# --- Setup: a remote sender actor ---
let (remotePub, remoteSecret) = generateEd25519KeypairPem()

# A fetchActor callback: looks up an actor's JSON by keyId.
# In production this fetches over the network or from a store.
proc fetchActor(keyId: string): JsonNode =
  if keyId == "https://remote.social/users/bob#main-key":
    result = %*{
      "id": "https://remote.social/users/bob",
      "publicKey": {
        "id": "https://remote.social/users/bob#main-key",
        "owner": "https://remote.social/users/bob",
        "publicKeyPem": remotePub
      }
    }

var dispatcher = newDispatcher(fetchActor)

# Register a typed handler for Follow activities
register[Follow](dispatcher, "Follow", proc (f: Follow, verifiedBy: string): InboxResult =
  echo "Received Follow from ", f.actor.get(), " (verified by ", verifiedBy, ")"
  InboxResult(success: true, status: 202)
)

# Register a typed handler for Create activities
register[Create](dispatcher, "Create", proc (c: Create, verifiedBy: string): InboxResult =
  echo "Received Create from ", c.actor.get()
  InboxResult(success: true, status: 202)
)

# Register a default handler for anything else
dispatcher.registerDefault(proc (activity: JsonNode, verifiedBy: string): InboxResult =
  echo "Unhandled activity type: ", activity{"type"}.getStr("")
  InboxResult(success: true, status: 202)
)
# --- Send a Follow to our inbox, signed by bob ---
let followBody = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Follow","actor":"https://remote.social/users/bob","object":"https://example.com/users/alice"}"""
let signed = signRequest(
  "POST", "/users/alice/inbox", "example.com", followBody,
  "https://remote.social/users/bob#main-key", remoteSecret
)
let headers = @[
  ("host", "example.com"),
  ("date", signed.date),
  ("digest", signed.digest),
  ("signature", signed.signature)
]

echo "== Dispatching Follow =="
let followResult = dispatcher.handle(followBody, headers, "/users/alice/inbox")
echo "success: ", followResult.success, ", status: ", followResult.status
echo ""

# --- Send a Create (Note) to our inbox ---
let createBody = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Create","actor":"https://remote.social/users/bob","object":{"type":"Note","content":"hello from bob"}}"""
let createSigned = signRequest(
  "POST", "/users/alice/inbox", "example.com", createBody,
  "https://remote.social/users/bob#main-key", remoteSecret
)
let createHeaders = @[
  ("host", "example.com"),
  ("date", createSigned.date),
  ("digest", createSigned.digest),
  ("signature", createSigned.signature)
]

echo "== Dispatching Create =="
let createResult = dispatcher.handle(createBody, createHeaders, "/users/alice/inbox")
echo "success: ", createResult.success, ", status: ", createResult.status
echo ""

# --- Try dispatching a request with a bad signature ---
let badBody = """{"type":"Like","actor":"https://remote.social/users/bob","object":"https://example.com/posts/1"}"""
let badResult = dispatcher.handle(badBody, @[("signature", "keyId=\"https://remote.social/users/bob#main-key\",algorithm=\"ed25519\",headers=\"(request-target) host date digest\",signature=\"AAAA\""), ("host", "example.com"), ("date", signed.date)], "/users/alice/inbox")
echo "== Dispatching with bad signature =="
echo "success: ", badResult.success, ", status: ", badResult.status
echo "error: ", badResult.error
