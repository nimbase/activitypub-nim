import unittest, std/[strutils, times]
import openparser/json as opj
import activitypub

suite "ActivityPub Core Types - Deserialization":
  test "Parse a simple Note":
    let data = """{"@context":"https://www.w3.org/ns/activitystreams","id":"https://example.com/note/1","type":"Note","name":"Hello World","content":"<p>Hello World</p>","published":"2024-01-15T10:00:00Z","to":"https://example.com/~alice/followers/"}"""
    let note = opj.fromJson(data, Note)
    check(note.`type` == otNote)
    check(note.id.get == "https://example.com/note/1")
    check(note.name.get == "Hello World")
    check(note.content.get == "<p>Hello World</p>")
    check(note.published.get == "2024-01-15T10:00:00Z")

  test "Parse a Note with Addresses (single-value to normalized to array)":
    let data = """{"type":"Note","to":"https://example.com/~alice/followers/","cc":["https://example.com/~bob/","https://www.w3.org/ns/activitystreams#Public"]}"""
    let note = opj.fromJson(data, Note)
    check(note.`type` == otNote)
    check(note.to.isSome)
    check(note.to.get.items.len == 1)
    check(note.to.get.items[0].getStr == "https://example.com/~alice/followers/")
    check(note.cc.get.items.len == 2)
    check(note.cc.get.items[1].getStr == "https://www.w3.org/ns/activitystreams#Public")

suite "ActivityPub Crypto":
  test "Generate Ed25519 keypair and PEM roundtrip":
    let (pem, secretHex) = generateEd25519KeypairPem()
    check(pem.startsWith("-----BEGIN PUBLIC KEY-----"))
    check(secretHex.len == 128)
    let pubKey = pemToPublicKeyEd25519(pem)
    let pem2 = publicKeyToPemEd25519(pubKey)
    check(pem == pem2)

  test "Ed25519 sign and verify roundtrip":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let data = "test message"
    let sig = signEd25519(data, secretHex)
    check(sig.len > 0)
    check(verifyEd25519(data, sig, pem))
    check(not verifyEd25519(data & "tampered", sig, pem))

  test "SHA-256 digest":
    let d = sha256Digest("hello")
    check(d.startsWith("SHA-256="))
    check(d.len > 40)

  test "httpDate / parseHttpDate roundtrip":
    let now = getTime()
    let dateStr = httpDate(now)
    check(dateStr.contains(" GMT"))
    let parsed = parseHttpDate(dateStr)
    check((now - parsed).inSeconds() < 2)

suite "HTTP Signatures":
  test "Parse Signature header":
    let header = "keyId=\"https://example.com/actor#main-key\",algorithm=\"ed25519\",headers=\"(request-target) host date digest\",signature=\"abc123==\""
    let p = parseSignatureHeader(header)
    check(p.keyId == "https://example.com/actor#main-key")
    check(p.algorithm == "ed25519")
    check(p.headers == @["(request-target)", "host", "date", "digest"])
    check(p.signature == "abc123==")

  test "Sign and verify request (Ed25519)":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    let body = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Create"}"""
    let result = signRequest("POST", "/actor/inbox", "example.com", body,
                              "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", result.date),
      ("digest", result.digest),
      ("signature", result.signature)
    ]
    check(verifyRequest("POST", "/actor/inbox", body, headers, actorJson))

  test "Verify rejects tampered body":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    let body = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Create"}"""
    let result = signRequest("POST", "/actor/inbox", "example.com", body,
                              "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", result.date),
      ("digest", result.digest),
      ("signature", result.signature)
    ]
    let tamperedBody = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Delete"}"""
    check(not verifyRequest("POST", "/actor/inbox", tamperedBody, headers, actorJson))

suite "WebFinger":
  test "Parse actor handle":
    let (user, domain) = parseHandle("@alice@example.com")
    check(user == "alice")
    check(domain == "example.com")

  test "Parse acct: URI":
    let (user, domain) = parseHandle("acct:bob@social.example")
    check(user == "bob")
    check(domain == "social.example")

  test "Parse handle without leading @":
    let (user, domain) = parseHandle("charlie@test.org")
    check(user == "charlie")
    check(domain == "test.org")

  test "Build JRD response":
    let jrd = buildJrd("acct:alice@example.com", "https://example.com/users/alice")
    check(jrd["subject"].getStr == "acct:alice@example.com")
    check(jrd["links"][0]["rel"].getStr == "self")
    check(jrd["links"][0]["type"].getStr == "application/activity+json")
    check(jrd["links"][0]["href"].getStr == "https://example.com/users/alice")

suite "Federation":
  test "verifyInboxRequest with valid signature":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "inbox": "https://example.com/actor/inbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    let body = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Create","object":{"type":"Note"}}"""
    let sig = signRequest("POST", "/actor/inbox", "example.com", body,
                           "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let res = verifyInboxRequest(body, headers, "/actor/inbox",
      proc (keyId: string): JsonNode =
        check(keyId == "https://example.com/actor#main-key")
        actorJson
    )
    check(res.success)
    check(res.data == "https://example.com/actor#main-key")

  test "verifyInboxRequest rejects tampered body":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    let body = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Create"}"""
    let sig = signRequest("POST", "/actor/inbox", "example.com", body,
                           "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com/actor/inbox"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let tampered = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Delete"}"""
    let res = verifyInboxRequest(tampered, headers, "/actor/inbox",
      proc (keyId: string): JsonNode = actorJson)
    check(not res.success)

  test "verifyInboxRequest rejects missing Signature header":
    let res = verifyInboxRequest("{}", @[], "/inbox",
      proc (keyId: string): JsonNode = nil)
    check(not res.success)
    check(res.error.contains("missing Signature"))

  test "verifyInboxRequest rejects unknown actor":
    let res = verifyInboxRequest("{}", @[("signature", "keyId=\"https://evil#key\",algorithm=\"ed25519\",headers=\"(request-target) host date\",signature=\"abc\"")], "/inbox",
      proc (keyId: string): JsonNode = nil)
    check(not res.success)
    check(res.error.contains("could not fetch actor"))

  test "deliverActivity fails on unreachable inbox":
    let actorJson = %* {
      "id": "https://example.com/actor",
      "inbox": "http://127.0.0.1:1/actor/inbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": ""
      }
    }
    let remote = RemoteActor(
      id: "https://example.com/actor",
      inbox: "http://127.0.0.1:1/actor/inbox",
      sharedInbox: "",
      publicKey: metatypes.PublicKey(
        id: some("https://example.com/actor#main-key"),
        owner: some("https://example.com/actor"),
        publicKeyPem: some("")
      ),
      rawJson: actorJson
    )
    let activity = %* {"@context":"https://www.w3.org/ns/activitystreams","type":"Create"}
    let (pem, secretHex) = generateEd25519KeypairPem()
    let res = deliverActivity(remote, secretHex, activity)
    check(not res.success)

  test "fetchObject fails on unreachable URL":
    expect(IOError, OSError):
      discard fetchObject("http://127.0.0.1:1/nonexistent")

  test "resolveRemoteActor rejects invalid handle":
    expect(ValueError):
      discard resolveRemoteActor("not-a-handle")

  test "resolveRemoteActor key extraction logic":
    let (pem, _) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "type": "Person",
      "inbox": "https://example.com/actor/inbox",
      "outbox": "https://example.com/actor/outbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    let pkNode = actorJson{"publicKey"}
    var pk: metatypes.PublicKey
    pk = metatypes.PublicKey(
      id: some(pkNode{"id"}.getStr),
      owner: some(pkNode{"owner"}.getStr),
      publicKeyPem: some(pkNode{"publicKeyPem"}.getStr)
    )
    check(pk.id.get == "https://example.com/actor#main-key")
    check(pk.publicKeyPem.get == pem)
    check(actorJson{"id"}.getStr == "https://example.com/actor")
    check(actorJson{"inbox"}.getStr == "https://example.com/actor/inbox")

suite "Activity Builders":
  test "buildNote creates a Note with content and attribution":
    let note = buildNote("Hello World", "https://example.com/~alice")
    check(note.`type` == otNote)
    check(note.content.get == "Hello World")
    check(note.attributedTo.get.getStr == "https://example.com/~alice")
    check(note.id.isSome)
    check(note.published.isSome)

  test "buildNote with addressing":
    let note = buildNote("Hello", "https://example.com/~alice",
                         to = @["https://example.com/~bob"],
                         cc = @["https://www.w3.org/ns/activitystreams#Public"])
    check(note.to.isSome)
    check(note.to.get.items.len == 1)
    check(note.to.get.items[0].getStr == "https://example.com/~bob")
    check(note.cc.get.items.len == 1)
    check(note.cc.get.items[0].getStr == "https://www.w3.org/ns/activitystreams#Public")

  test "buildNote with summary":
    let note = buildNote("Hello", "https://example.com/~alice", summary = "cw")
    check(note.summary.get == "cw")

  test "buildFollow creates a Follow activity":
    let f = buildFollow("https://example.com/~alice", "https://remote.social/~bob")
    check(f.`type` == FollowType)
    check(f.actor.get.getStr == "https://example.com/~alice")
    check(f.`object`.get.getStr == "https://remote.social/~bob")
    check(f.to.get.items[0].getStr == "https://remote.social/~bob")

  test "buildAccept wraps a Follow as its object":
    let follow = buildFollow("https://remote.social/~bob", "https://example.com/~alice")
    let accept = buildAccept("https://example.com/~alice", follow)
    check(accept.`type` == AcceptType)
    check(accept.actor.get.getStr == "https://example.com/~alice")
    let obj = accept.`object`.get
    check(obj{"type"}.getStr == "Follow")
    check(accept.to.isSome)
    check(accept.to.get.items.len == 1)

  test "buildReject wraps a Follow as its object":
    let follow = buildFollow("https://remote.social/~bob", "https://example.com/~alice")
    let reject = buildReject("https://example.com/~alice", follow)
    check(reject.`type` == RejectType)
    check(reject.actor.get.getStr == "https://example.com/~alice")

  test "buildCreate wraps an ObjectBase":
    let note = buildNote("test", "https://example.com/~alice")
    let create = buildCreate("https://example.com/~alice", note,
                             to = @["https://example.com/~bob"])
    check(create.`type` == CreateType)
    check(create.actor.get.getStr == "https://example.com/~alice")
    let obj = create.`object`.get
    check(obj{"type"}.getStr == "Note")
    check(obj{"content"}.getStr == "test")
    check(create.to.get.items[0].getStr == "https://example.com/~bob")

  test "buildDelete references an object by URL":
    let d = buildDelete("https://example.com/~alice", "https://example.com/note/1")
    check(d.`type` == DeleteType)
    check(d.actor.get.getStr == "https://example.com/~alice")
    check(d.`object`.get.getStr == "https://example.com/note/1")

  test "buildUpdate wraps an ObjectBase":
    let note = buildNote("updated", "https://example.com/~alice")
    let update = buildUpdate("https://example.com/~alice", note)
    check(update.`type` == UpdateType)
    check(update.actor.get.getStr == "https://example.com/~alice")
    check(update.`object`.get{"content"}.getStr == "updated")

  test "buildAnnounce wraps an ObjectBase":
    let note = buildNote("boosted", "https://example.com/~alice")
    let announce = buildAnnounce("https://example.com/~alice", note,
                                 to = @["https://example.com/~alice/followers"])
    check(announce.`type` == AnnounceType)
    check(announce.actor.get.getStr == "https://example.com/~alice")
    check(announce.`object`.get{"type"}.getStr == "Note")
    check(announce.to.get.items[0].getStr == "https://example.com/~alice/followers")

  test "buildLike references an object by URL":
    let like = buildLike("https://example.com/~alice", "https://example.com/note/1")
    check(like.`type` == LikeType)
    check(like.actor.get.getStr == "https://example.com/~alice")
    check(like.`object`.get.getStr == "https://example.com/note/1")

  test "buildUndo wraps an ActivityBase":
    let follow = buildFollow("https://example.com/~alice", "https://remote.social/~bob")
    let undo = buildUndo("https://example.com/~alice", follow)
    check(undo.`type` == UndoType)
    check(undo.actor.get.getStr == "https://example.com/~alice")
    let obj = undo.`object`.get
    check(obj{"type"}.getStr == "Follow")

  test "builders produce valid UUID-based IDs":
    let note = buildNote("x", "https://example.com/~alice")
    let f = buildFollow("https://example.com/~alice", "https://remote.social/~bob")
    let accept = buildAccept("https://example.com/~alice", f)
    check(note.id.get.len > 10)
    check(f.id.get.len > 10)
    check(accept.id.get.len > 10)

  test "builders serialize and deserialize roundtrip":
    let note = buildNote("Hello World", "https://example.com/~alice",
                         to = @["https://example.com/~bob"])
    let json = opj.toJson(note)
    let note2 = opj.fromJson(json, Note)
    check(note2.content.get == "Hello World")
    check(note2.attributedTo.get.getStr == "https://example.com/~alice")
    check(note2.to.get.items[0].getStr == "https://example.com/~bob")

suite "C2S Client":
  let fakeKeyHex = "aa" & repeat("bb", 63)
  let actorJson = %*{
    "id": "https://example.com/~alice",
    "inbox": "https://example.com/~alice/inbox",
    "outbox": "https://example.com/~alice/outbox",
    "publicKey": {
      "id": "https://example.com/~alice#main-key",
      "owner": "https://example.com/~alice",
      "publicKeyPem": "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEADummyKeyForTesting=\n-----END PUBLIC KEY-----"
    }
  }

  test "newClient constructs from actor JSON":
    let client = newClient(actorJson, "aa" & repeat("bb", 31))
    check(client.id == "https://example.com/~alice")
    check(client.inbox == "https://example.com/~alice/inbox")
    check(client.outbox == "https://example.com/~alice/outbox")
    check(client.keyId == "https://example.com/~alice#main-key")
    check(client.privateKeyHex.len == 64)

  test "newClient from actor ID raises on unreachable actor":
    expect(Exception):
      discard newClient("https://invalid.example.com/actor", fakeKeyHex)

  test "resolveActorUrl returns URLs as-is":
    check(resolveActorUrl("https://example.com/~bob") == "https://example.com/~bob")

  test "resolveActorUrl raises on invalid handle":
    expect(Exception):
      discard resolveActorUrl("not-a-handle")

  test "sendTo fails gracefully on unreachable inbox":
    let client = newClient(actorJson, fakeKeyHex)
    let result = sendTo(client, %*{"type": "Note"}, "https://invalid.example.com/inbox")
    check(result.success == false)
    check(result.error.len > 0)

  test "follow fails gracefully on unreachable target":
    let client = newClient(actorJson, fakeKeyHex)
    let result = client.follow("https://invalid.example.com/~bob")
    check(result.success == false)
    check(result.error.len > 0)

  test "postNote fails gracefully on unreachable outbox":
    let client = newClient(actorJson, fakeKeyHex)
    let result = client.postNote("Hello World",
                                  to = @["https://invalid.example.com/~bob"])
    check(result.success == false)
    check(result.error.len > 0)

suite "Inbox Dispatcher":
  test "register and dispatch a Follow activity with typed handler":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "inbox": "https://example.com/actor/inbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://example.com/actor#main-key": actorJson else: nil
    )
    var followHandled = false
    var receivedVerifiedBy = ""
    register[Follow](dispatcher, "Follow", proc (f: Follow, verifiedBy: string): InboxResult =
      followHandled = true
      receivedVerifiedBy = verifiedBy
      check(f.`type` == FollowType)
      check(f.actor.get.getStr == "https://example.com/actor")
      check(f.`object`.get.getStr == "https://remote.social/~bob")
      InboxResult(success: true, status: 202)
    )
    let activityJson = %* {
      "@context": "https://www.w3.org/ns/activitystreams",
      "id": "https://example.com/actor/follows/1",
      "type": "Follow",
      "actor": "https://example.com/actor",
      "object": "https://remote.social/~bob"
    }
    let body = $activityJson
    let sig = signRequest("POST", "/actor/inbox", "example.com", body,
                           "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let result = dispatcher.handle(body, headers, "/actor/inbox")
    check(result.success)
    check(result.status == 202)
    check(followHandled)
    check(receivedVerifiedBy == "https://example.com/actor#main-key")

  test "dispatch a Create activity with typed handler":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "inbox": "https://example.com/actor/inbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://example.com/actor#main-key": actorJson else: nil
    )
    var createHandled = false
    register[Create](dispatcher, "Create", proc (c: Create, verifiedBy: string): InboxResult =
      createHandled = true
      check(c.`type` == CreateType)
      check(c.actor.get.getStr == "https://example.com/actor")
      InboxResult(success: true, status: 202)
    )
    let activityJson = %* {
      "@context": "https://www.w3.org/ns/activitystreams",
      "id": "https://example.com/actor/creates/1",
      "type": "Create",
      "actor": "https://example.com/actor",
      "object": {"type": "Note", "content": "Hello"}
    }
    let body = $activityJson
    let sig = signRequest("POST", "/actor/inbox", "example.com", body,
                           "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let result = dispatcher.handle(body, headers, "/actor/inbox")
    check(result.success)
    check(result.status == 202)
    check(createHandled)

  test "unregistered type returns 202 with no handler":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "inbox": "https://example.com/actor/inbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://example.com/actor#main-key": actorJson else: nil
    )
    let activityJson = %* {
      "@context": "https://www.w3.org/ns/activitystreams",
      "type": "Like",
      "actor": "https://example.com/actor",
      "object": "https://remote.social/posts/1"
    }
    let body = $activityJson
    let sig = signRequest("POST", "/actor/inbox", "example.com", body,
                           "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let result = dispatcher.handle(body, headers, "/actor/inbox")
    check(result.success)
    check(result.status == 202)

  test "default handler called for unregistered type":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "inbox": "https://example.com/actor/inbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://example.com/actor#main-key": actorJson else: nil
    )
    var defaultCalled = false
    dispatcher.registerDefault(proc (activity: JsonNode, verifiedBy: string): InboxResult =
      defaultCalled = true
      check(activity{"type"}.getStr == "Like")
      InboxResult(success: true, status: 202)
    )
    let activityJson = %* {
      "@context": "https://www.w3.org/ns/activitystreams",
      "type": "Like",
      "actor": "https://example.com/actor",
      "object": "https://remote.social/posts/1"
    }
    let body = $activityJson
    let sig = signRequest("POST", "/actor/inbox", "example.com", body,
                           "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let result = dispatcher.handle(body, headers, "/actor/inbox")
    check(result.success)
    check(result.status == 202)
    check(defaultCalled)

  test "bad signature returns 401":
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode = nil
    )
    let result = dispatcher.handle("{}", @[("signature", "keyId=\"https://evil#key\",algorithm=\"ed25519\",headers=\"(request-target) host date\",signature=\"abc\"")], "/inbox")
    check(not result.success)
    check(result.status == 401)

  test "missing type field returns 400":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://example.com/actor",
      "inbox": "https://example.com/actor/inbox",
      "publicKey": {
        "id": "https://example.com/actor#main-key",
        "owner": "https://example.com/actor",
        "publicKeyPem": pem
      }
    }
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://example.com/actor#main-key": actorJson else: nil
    )
    let body = """{"@context":"https://www.w3.org/ns/activitystreams","content":"hello"}"""
    let sig = signRequest("POST", "/inbox", "example.com", body,
                           "https://example.com/actor#main-key", secretHex)
    let headers = @[
      ("host", "example.com"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let result = dispatcher.handle(body, headers, "/inbox")
    check(not result.success)
    check(result.status == 400)
    check(result.error.contains("type"))
