import unittest, std/[json, strutils]
import openparser/json as opj
import activitypub

suite "Collection Pagination":
  test "parse a Collection with inline items":
    let data = """{
      "@context": "https://www.w3.org/ns/activitystreams",
      "id": "https://example.com/outbox",
      "type": "OrderedCollection",
      "totalItems": 2,
      "orderedItems": [
        {"type": "Create", "actor": "https://example.com/~alice", "object": {"type": "Note", "content": "Hello"}},
        {"type": "Create", "actor": "https://example.com/~alice", "object": {"type": "Note", "content": "World"}}
      ]
    }"""
    let coll = opj.fromJson(data, OrderedCollection)
    check(coll.`type` == ctOrderedCollection)
    check(coll.totalItems.get == 2)
    check(coll.orderedItems.get.len == 2)

  test "parse a paginated Collection with first link":
    let data = """{
      "@context": "https://www.w3.org/ns/activitystreams",
      "id": "https://example.com/outbox",
      "type": "OrderedCollection",
      "totalItems": 5,
      "first": "https://example.com/outbox?page=1"
    }"""
    let coll = opj.fromJson(data, OrderedCollection)
    check(coll.`type` == ctOrderedCollection)
    check(coll.totalItems.get == 5)
    check(coll.first.get.getStr == "https://example.com/outbox?page=1")

  test "parse a CollectionPage":
    let data = """{
      "@context": "https://www.w3.org/ns/activitystreams",
      "id": "https://example.com/outbox?page=1",
      "type": "OrderedCollectionPage",
      "partOf": "https://example.com/outbox",
      "orderedItems": [
        {"type": "Create", "actor": "https://example.com/~alice", "object": {"type": "Note", "content": "Page1"}}
      ],
      "next": "https://example.com/outbox?page=2"
    }"""
    let page = opj.fromJson(data, OrderedCollectionPage)
    check(page.`type` == ctOrderedCollectionPage)
    check(page.orderedItems.get.len == 1)
    check(page.next.get.getStr == "https://example.com/outbox?page=2")
    check(page.partOf.get.getStr == "https://example.com/outbox")

  test "parse a Collection with last link":
    let data = """{
      "@context": "https://www.w3.org/ns/activitystreams",
      "id": "https://example.com/followers",
      "type": "Collection",
      "totalItems": 100,
      "first": "https://example.com/followers?page=1",
      "last": "https://example.com/followers?page=5"
    }"""
    let coll = opj.fromJson(data, Collection)
    check(coll.`type` == ctCollection)
    check(coll.last.get.getStr == "https://example.com/followers?page=5")

  test "fetchCollection fails gracefully on unreachable URL":
    expect(IOError, OSError):
      discard fetchCollection("http://127.0.0.1:1/nonexistent-collection")

  test "fetchAllItems fails gracefully on unreachable URL":
    let result = try:
      fetchAllItems("http://127.0.0.1:1/nonexistent")
    except CatchableError:
      @[]
    check(result.len == 0)

suite "Full Pipeline Integration":
  test "build → sign → verify → dispatch Follow":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let localActorJson = %* {
      "id": "https://local.example/~alice",
      "inbox": "https://local.example/~alice/inbox",
      "publicKey": {
        "id": "https://local.example/~alice#main-key",
        "owner": "https://local.example/~alice",
        "publicKeyPem": pem
      }
    }
    let localClient = newClient(localActorJson, secretHex)

    let follow = buildFollow(localClient.id, "https://remote.social/~bob")
    let activityJson = opj.toJsonNode(follow)
    let body = $activityJson

    let sig = signRequest("POST", "/~alice/inbox", "local.example", body,
                           localClient.keyId, secretHex)
    let headers = @[
      ("host", "local.example"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]

    var followHandled = false
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == localClient.keyId: localActorJson else: nil
    )
    register[Follow](dispatcher, "Follow", proc (f: Follow, verifiedBy: string): InboxResult =
      followHandled = true
      check(f.actor.get.getStr == "https://local.example/~alice")
      check(f.`object`.get.getStr == "https://remote.social/~bob")
      check(verifiedBy == "https://local.example/~alice#main-key")
      InboxResult(success: true, status: 202)
    )

    let result = dispatcher.handle(body, headers, "/~alice/inbox")
    check(result.success)
    check(followHandled)

  test "full roundtrip: build Follow → deliver → verify → accept → verify Accept":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://local.example/~alice",
      "inbox": "https://local.example/~alice/inbox",
      "publicKey": {
        "id": "https://local.example/~alice#main-key",
        "owner": "https://local.example/~alice",
        "publicKeyPem": pem
      }
    }

    let follow = buildFollow("https://remote.social/~bob", "https://local.example/~alice")
    let accept = buildAccept("https://local.example/~alice", follow)

    let acceptJson = opj.toJsonNode(accept)
    let body = $acceptJson
    let sig = signRequest("POST", "/~bob/inbox", "remote.social", body,
                           "https://local.example/~alice#main-key", secretHex)
    let headers = @[
      ("host", "remote.social"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]

    var acceptHandled = false
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://local.example/~alice#main-key": actorJson else: nil
    )
    register[Accept](dispatcher, "Accept", proc (a: Accept, verifiedBy: string): InboxResult =
      acceptHandled = true
      check(a.`type` == AcceptType)
      check(a.actor.get.getStr == "https://local.example/~alice")
      InboxResult(success: true, status: 202)
    )

    let result = dispatcher.handle(body, headers, "/~bob/inbox")
    check(result.success)
    check(acceptHandled)

  test "postNote → outbox → create dispatcher":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://local.example/~alice",
      "inbox": "https://local.example/~alice/inbox",
      "outbox": "https://local.example/~alice/outbox",
      "publicKey": {
        "id": "https://local.example/~alice#main-key",
        "owner": "https://local.example/~alice",
        "publicKeyPem": pem
      }
    }

    let note = buildNote("Hello Pipeline", "https://local.example/~alice",
                          to = @["https://remote.social/~bob"])
    let create = buildCreate("https://local.example/~alice", note)
    let activityJson = opj.toJsonNode(create)
    let body = $activityJson

    let sig = signRequest("POST", "/~alice/outbox", "local.example", body,
                          "https://local.example/~alice#main-key", secretHex)
    let headers = @[
      ("host", "local.example"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]

    var createHandled = false
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://local.example/~alice#main-key": actorJson else: nil
    )
    register[Create](dispatcher, "Create", proc (c: Create, verifiedBy: string): InboxResult =
      createHandled = true
      check(c.actor.get.getStr == "https://local.example/~alice")
      let obj = c.`object`.get
      check(obj{"type"}.getStr == "Note")
      check(obj{"content"}.getStr == "Hello Pipeline")
      InboxResult(success: true, status: 202)
    )

    let result = dispatcher.handle(body, headers, "/~alice/outbox")
    check(result.success)
    check(createHandled)

  test "buildFollow → buildUndo → verify Undo activity":
    let (pem, secretHex) = generateEd25519KeypairPem()
    let actorJson = %* {
      "id": "https://local.example/~alice",
      "inbox": "https://local.example/~alice/inbox",
      "publicKey": {
        "id": "https://local.example/~alice#main-key",
        "owner": "https://local.example/~alice",
        "publicKeyPem": pem
      }
    }

    let follow = buildFollow("https://local.example/~alice", "https://remote.social/~bob")
    let undo = buildUndo("https://local.example/~alice", follow)
    let activityJson = opj.toJsonNode(undo)
    let body = $activityJson
    let sig = signRequest("POST", "/~bob/inbox", "remote.social", body,
                           "https://local.example/~alice#main-key", secretHex)
    let headers = @[
      ("host", "remote.social"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]

    var undoHandled = false
    var dispatcher = newDispatcher(
      proc (keyId: string): JsonNode =
        if keyId == "https://local.example/~alice#main-key": actorJson else: nil
    )
    register[Undo](dispatcher, "Undo", proc (u: Undo, verifiedBy: string): InboxResult =
      undoHandled = true
      check(u.`type` == UndoType)
      let obj = u.`object`.get
      check(obj{"type"}.getStr == "Follow")
      InboxResult(success: true, status: 202)
    )

    let result = dispatcher.handle(body, headers, "/~bob/inbox")
    check(result.success)
    check(undoHandled)

suite "ActivityStore":
  test "registerActor creates actor with keypair":
    let store = newActivityStore()
    let actorId = store.registerActor("alice", "example.com")
    check(actorId == "https://example.com/users/alice")
    let actor = store.findActorByUsername("alice")
    check(actor.json["preferredUsername"].getStr == "alice")
    check(actor.privateKeyHex.len == 128)
    check(actor.publicKeyPem.contains("BEGIN PUBLIC KEY"))

  test "registerActor with name and icon":
    let store = newActivityStore()
    discard store.registerActor("bob", "example.com", name = "Bob Smith",
                                iconUrl = "https://example.com/icon.jpg")
    let actor = store.findActorByUsername("bob")
    check(actor.json["name"].getStr == "Bob Smith")
    check(actor.json["icon"]["url"].getStr == "https://example.com/icon.jpg")

  test "findActorByUsername raises KeyError on missing actor":
    let store = newActivityStore()
    expect KeyError:
      discard store.findActorByUsername("nonexistent")

  test "findActorByAcctUri resolves acct URIs":
    let store = newActivityStore()
    discard store.registerActor("alice", "example.com")
    let actor = store.findActorByAcctUri("acct:alice@example.com")
    check(actor.json["preferredUsername"].getStr == "alice")

  test "findActorByKeyId finds by public key id":
    let store = newActivityStore()
    let actorId2 = store.registerActor("alice", "example.com")
    let actor = store.findActorByKeyId(actorId2 & "#main-key")
    check(actor.username == "alice")

  test "storeActivity and getOutboxItems":
    let store = newActivityStore()
    discard store.registerActor("alice", "example.com")
    let activity = %* {"type": "Create", "actor": "https://example.com/users/alice"}
    store.storeActivity("alice", activity)
    let items = store.getOutboxItems("alice")
    check(items.len == 1)
    check(items[0]{"type"}.getStr == "Create")

  test "addFollowerUrl and removeFollowerUrl":
    let store = newActivityStore()
    discard store.registerActor("alice", "example.com")
    store.addFollowerUrl("alice", "https://remote.social/users/bob")
    check(store.getFollowerUrls("alice") == @["https://remote.social/users/bob"])
    store.addFollowerUrl("alice", "https://other.social/users/carol")
    check(store.getFollowerUrls("alice").len == 2)
    store.removeFollowerUrl("alice", "https://remote.social/users/bob")
    check(store.getFollowerUrls("alice").len == 1)

  test "duplicate follower is not added twice":
    let store = newActivityStore()
    discard store.registerActor("alice", "example.com")
    store.addFollowerUrl("alice", "https://remote.social/users/bob")
    store.addFollowerUrl("alice", "https://remote.social/users/bob")
    check(store.getFollowerUrls("alice").len == 1)

suite "ActivityPubServer":
  test "newActivityPubServer creates server with store":
    let store = newActivityStore()
    discard store.registerActor("alice", "example.com")
    let server = newActivityPubServer("example.com", store)
    check(server.domain == "example.com")

  test "server register delegates to dispatcher":
    let store = newActivityStore()
    discard store.registerActor("alice", "example.com")
    var server = newActivityPubServer("example.com", store)
    var followHandled = false
    register[Follow](server.dispatcher, "Follow", proc (f: Follow, verifiedBy: string): InboxResult =
      followHandled = true
      InboxResult(success: true, status: 202)
    )
    let aliceData = store.findActorByUsername("alice")
    let pem2 = aliceData.publicKeyPem
    let secretHex2 = aliceData.privateKeyHex
    let body = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Follow","actor":"https://example.com/users/alice","object":"https://remote.social/users/bob"}"""
    let sig = signRequest("POST", "/users/alice/inbox", "example.com", body,
                           "https://example.com/users/alice#main-key", secretHex2)
    let headers = @[
      ("host", "example.com"),
      ("date", sig.date),
      ("digest", sig.digest),
      ("signature", sig.signature)
    ]
    let result = server.dispatcher.handle(body, headers, "/users/alice/inbox")
    check(result.success)
    check(followHandled)
