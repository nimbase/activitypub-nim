## Example 07 — C2S Client
##
## Build a Client from an actor document and private key, then send a
## signed Follow activity to an inbox — here, a local ActivityPub server
## that verifies the HTTP Signature and dispatches it to a handler.
##
##   nim c -r examples/ex_07_client.nim

import std/[httpclient, net, os, times]
import ../src/activitypub

# --- Create our local actor (the C2S client's identity) ---
let store = newActivityStore()
discard store.registerActor("alice", "example.com", "Alice")
let aliceData = store.findActorByUsername("alice")

# Build a Client from the actor JSON + secret key hex
let client = newClient(aliceData.json, aliceData.privateKeyHex)

echo "== Client =="
echo "id: ", client.id
echo "inbox: ", client.inbox
echo "outbox: ", client.outbox
echo "keyId: ", client.keyId
echo ""

# --- Spin up a local server that owns alice's inbox ---
var server: ActivityPubServer
var receivedFollow: bool
server = newActivityPubServer("example.com", store)

register[Follow](server.dispatcher, "Follow", proc (f: Follow, verifiedBy: string): InboxResult =
  echo "Server handler: Follow from ", f.actor.get(), " -> ", f.object.get()
  echo "Server handler: verified by ", verifiedBy
  receivedFollow = true
  InboxResult(success: true, status: 202)
)

const port = Port(9001)
proc runServer(arg: pointer) {.thread.} =
  let srv = cast[ptr ActivityPubServer](arg)
  {.cast(gcsafe).}:
    srv[].start(port)

var thread: Thread[pointer]
createThread(thread, runServer, cast[pointer](addr server))
sleep(500)

# --- Build a Follow and send it to the local server's inbox (signed) ---
let follow = buildFollow(client.id, "https://remote.social/users/bob")
echo "== Sending Follow to local inbox =="
let result = client.sendTo(follow.toJsonNode(), "http://localhost:" & $port.int & "/users/alice/inbox")
echo "delivery success: ", result.success
if not result.success:
  echo "error: ", result.error
echo ""

# --- Verify the server side received and verified it ---
sleep(200)
echo "server received & verified Follow: ", receivedFollow

server.stop()
