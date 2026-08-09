## Example 06 — ActivityPub HTTP server
##
## Start a full ActivityPub server powered by powpow, register actors,
## register inbox handlers, and verify the endpoints respond.
##
##   nim c -r examples/ex_06_server.nim

import std/[httpclient, net, os, times]
import ../src/activitypub

let store = newActivityStore()

# Register some local actors
discard store.registerActor("alice", "localhost", "Alice")
discard store.registerActor("bob", "localhost", "Bob")

# Store an activity in alice's outbox
store.storeActivity("alice", %*{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Create",
  "actor": "https://localhost/users/alice",
  "object": %*{
    "type": "Note",
    "content": "Hello from the outbox!"
  }
})

var server: ActivityPubServer
server = newActivityPubServer("localhost", store)

const port = Port(9000)

# powpow's start() blocks on the event loop, so run it on a thread.
proc runServer(arg: pointer) {.thread.} =
  let srv = cast[ptr ActivityPubServer](arg)
  {.cast(gcsafe).}:
    srv[].start(port)

var thread: Thread[pointer]
createThread(thread, runServer, cast[pointer](addr server))
sleep(500)  # give the server a moment to bind

let client = newHttpClient()
let base = "http://localhost:" & $port.int

echo "== GET /users/alice =="
let actor = client.get(base & "/users/alice")
echo actor.status, " ", actor.body
echo ""

echo "== GET /.well-known/webfinger?resource=acct:alice@localhost =="
let jrd = client.get(base & "/.well-known/webfinger?resource=acct:alice@localhost")
echo jrd.status, " ", jrd.body
echo ""

echo "== GET /users/alice/outbox =="
let outbox = client.get(base & "/users/alice/outbox")
echo outbox.status, " ", outbox.body
echo ""

echo "== GET /users/alice/followers =="
let followers = client.get(base & "/users/alice/followers")
echo followers.status, " ", followers.body

client.close()
server.stop()
