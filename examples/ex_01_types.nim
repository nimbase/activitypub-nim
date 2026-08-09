## Example 01 — ActivityStreams data types
##
## Create and serialize ActivityStreams types (objects, activities,
## actors, collections) and parse them back from JSON.
##
##   nim c -r examples/ex_01_types.nim

import ../src/activitypub

let note = buildNote(
  content = "Hello fediverse!",
  attributedTo = "https://example.com/users/alice",
  to = @["https://www.w3.org/ns/activitystreams#Public"]
)
echo "== Note =="
echo note.toJson()
echo ""

let follow = buildFollow(
  actor = "https://example.com/users/alice",
  target = "https://remote.social/users/bob"
)
echo "== Follow =="
echo follow.toJson()
echo ""

var person = newPerson("https://example.com/users/alice")
person.name = some("Alice")
person.preferredUsername = some("alice")
person.inbox = some(%* "https://example.com/users/alice/inbox")
person.outbox = some(%* "https://example.com/users/alice/outbox")

echo "== Person =="
echo person.toJson()
echo ""

let (publicPem, _) = generateEd25519KeypairPem()
person.publicKey = some(metatypes.PublicKey(
  id: some("https://example.com/users/alice#main-key"),
  owner: some("https://example.com/users/alice"),
  publicKeyPem: some(publicPem)
))

echo "== Person with public key =="
echo person.toJson()
echo ""

var collection = OrderedCollection(
  `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
  id: some("https://example.com/users/alice/outbox"),
  `type`: ctOrderedCollection,
  totalItems: some(2),
  orderedItems: some(@[follow.toJsonNode(), note.toJsonNode()])
)
echo "== OrderedCollection =="
echo collection.toJson()
echo ""

# Round-trip: parse JSON back into a Note
let json = note.toJson()
let parsed = fromJson(json, Note)
echo "== Parsed back from JSON =="
echo "id: ", parsed.id.get()
echo "content: ", parsed.content.get()
echo "published: ", parsed.published.get()
