## Example 03 — Activity builders
##
## Use the high-level builders to construct common activities:
## Follow, Accept, Reject, Create, Delete, Update, Announce, Like, Undo.
##
##   nim c -r examples/ex_03_builders.nim

import ../src/activitypub

const alice = "https://example.com/users/alice"
const bob = "https://remote.social/users/bob"
const publicAudience = "https://www.w3.org/ns/activitystreams#Public"

let follow = buildFollow(alice, bob)
echo "== Follow =="
echo follow.toJson()
echo ""

let accept = buildAccept(alice, follow)
echo "== Accept (of the Follow) =="
echo accept.toJson()
echo ""

let reject = buildReject(bob, follow)
echo "== Reject (of the Follow) =="
echo reject.toJson()
echo ""

let note = buildNote(
  "This is a note wrapped in a Create activity",
  alice,
  to = @[publicAudience],
  cc = @[bob]
)
echo "== Note =="
echo note.toJson()
echo ""

let create = buildCreate(alice, note, to = @[publicAudience], cc = @[bob])
echo "== Create =="
echo create.toJson()
echo ""

let update = buildUpdate(alice, note)
echo "== Update =="
echo update.toJson()
echo ""

let delete = buildDelete(alice, note.id.get())
echo "== Delete =="
echo delete.toJson()
echo ""

let announce = buildAnnounce(alice, note, to = @[publicAudience])
echo "== Announce =="
echo announce.toJson()
echo ""

let like = buildLike(alice, "https://remote.social/posts/123")
echo "== Like =="
echo like.toJson()
echo ""

let undoFollow = buildUndo(alice, follow)
echo "== Undo(Follow) =="
echo undoFollow.toJson()
echo ""

echo "== Timestamp helper =="
echo "nowIso(): ", nowIso()
