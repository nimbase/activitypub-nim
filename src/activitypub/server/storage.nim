## In-memory storage for ActivityPub actors, activities, and relationships.
##
## Provides an `ActivityStore` with basic CRUD operations for testing and
## lightweight single-node deployments.

import std/[json, tables, strutils]
import openparser/json as opj
import ../datatypes/[metatypes, collectiontypes, coretypes, activitytypes]
import ./crypto

export metatypes, collectiontypes, coretypes, activitytypes

type
  ActorData* = object
    json*: JsonNode
    username*: string
    privateKeyHex*: string
    publicKeyPem*: string

  ActivityStore* = ref object
    actors*: OrderedTable[string, ActorData]
    activities*: Table[string, seq[JsonNode]]
    followerUrls*: Table[string, seq[string]]
    followingUrls*: Table[string, seq[string]]

proc newActivityStore*(): ActivityStore =
  ## Creates a new empty `ActivityStore`.
  ActivityStore(
    actors: initOrderedTable[string, ActorData](),
    activities: initTable[string, seq[JsonNode]](),
    followerUrls: initTable[string, seq[string]](),
    followingUrls: initTable[string, seq[string]]()
  )

proc registerActor*(store: ActivityStore; username, domain: string;
                    name: string = ""; iconUrl: string = ""): string =
  ## Registers a new actor in the store with an auto-generated Ed25519 keypair.
  ##
  ## Creates the actor's JSON-LD document with inbox, outbox, followers,
  ## following URLs, and a public key. Returns the actor's ID URL.
  ##
  ## - `username`: the actor's handle (without @)
  ## - `domain`: the server domain
  ## - `name`: optional display name
  ## - `iconUrl`: optional avatar URL
  let (publicPem, secretHex) = generateEd25519KeypairPem()
  let actorId = "https://" & domain & "/users/" & username
  let actorJson = %*{
    "@context": [
      "https://www.w3.org/ns/activitystreams",
      "https://w3id.org/security/v1"
    ],
    "id": actorId,
    "type": "Person",
    "preferredUsername": username,
    "name": (if name.len > 0: name else: username),
    "inbox": actorId & "/inbox",
    "outbox": actorId & "/outbox",
    "followers": actorId & "/followers",
    "following": actorId & "/following",
    "publicKey": {
      "id": actorId & "#main-key",
      "owner": actorId,
      "publicKeyPem": publicPem
    }
  }
  if iconUrl.len > 0:
    actorJson["icon"] = %*{"type": "Image", "mediaType": "image/jpeg", "url": iconUrl}
  store.actors[username] = ActorData(
    json: actorJson,
    username: username,
    privateKeyHex: secretHex,
    publicKeyPem: publicPem
  )
  store.activities[username] = @[]
  store.followerUrls[username] = @[]
  store.followingUrls[username] = @[]
  result = actorId

proc findActorByUsername*(store: ActivityStore; username: string): ActorData =
  ## Looks up an actor by username. Returns `ActorData` or raises `KeyError`.
  store.actors[username]

proc findActorByAcctUri*(store: ActivityStore; acctUri: string): ActorData =
  ## Looks up an actor by `acct:user@domain` URI.
  ## Returns `ActorData` or raises `KeyError`.
  let clean = acctUri.strip(chars = {'@', ' '})
  let uriStr = if clean.startsWith("acct:"): clean[5..^1] else: clean
  let parts = uriStr.split('@')
  if parts.len != 2:
    raise newException(ValueError, "invalid acct URI: " & acctUri)
  store.actors[parts[0]]

proc findActorByKeyId*(store: ActivityStore; keyId: string): ActorData =
  ## Finds an actor whose publicKey id matches `keyId`.
  ## Iterates all actors. Raises `KeyError` if not found.
  for username, data in store.actors:
    if data.json["publicKey"]["id"].getStr == keyId:
      return data
  raise newException(KeyError, "no actor with keyId: " & keyId)

proc storeActivity*(store: ActivityStore; username: string; activity: JsonNode) =
  ## Appends an activity to the actor's outbox.
  if not store.activities.hasKey(username):
    store.activities[username] = @[]
  store.activities[username].add(activity)

proc getOutboxItems*(store: ActivityStore; username: string): seq[JsonNode] =
  ## Returns all activities in an actor's outbox.
  ## Returns empty seq if the actor has no activities.
  if store.activities.hasKey(username):
    store.activities[username]
  else:
    @[]

proc addFollowerUrl*(store: ActivityStore; username: string; followerActorUrl: string) =
  ## Adds a follower URL to an actor's followers collection.
  if not store.followerUrls.hasKey(username):
    store.followerUrls[username] = @[]
  if followerActorUrl notin store.followerUrls[username]:
    store.followerUrls[username].add(followerActorUrl)

proc removeFollowerUrl*(store: ActivityStore; username: string; followerActorUrl: string) =
  ## Removes a follower URL from an actor's followers collection.
  if store.followerUrls.hasKey(username):
    let idx = store.followerUrls[username].find(followerActorUrl)
    if idx >= 0:
      store.followerUrls[username].delete(idx)

proc getFollowerUrls*(store: ActivityStore; username: string): seq[string] =
  ## Returns all follower actor URLs for an actor.
  if store.followerUrls.hasKey(username):
    store.followerUrls[username]
  else:
    @[]

proc getFollowingUrls*(store: ActivityStore; username: string): seq[string] =
  ## Returns all following actor URLs for an actor.
  if store.followingUrls.hasKey(username):
    store.followingUrls[username]
  else:
    @[]
