## Example 04 — WebFinger discovery
##
## Parse actor handles, resolve remote actors via WebFinger (requires
## network), and build JRD responses for serving /.well-known/webfinger.
##
##   nim c -r examples/ex_04_webfinger.nim

import ../src/activitypub

echo "== parseHandle =="
let (user, domain) = parseHandle("@alice@example.com")
echo "user: ", user
echo "domain: ", domain
echo "parseHandle('acct:bob@remote.social'): ",
  parseHandle("acct:bob@remote.social")
echo ""

echo "== buildJrd (server side) =="
let jrd = buildJrd(
  subject = "acct:alice@example.com",
  actorUrl = "https://example.com/users/alice",
  aliases = @["https://example.com/@alice"],
  profilePage = "https://example.com/@alice",
  avatarUrl = "https://example.com/avatar/alice.jpg"
)
echo jrd.pretty()
echo ""

# Requires network access to reach a live ActivityPub server:
echo "== resolveActor (requires network) =="
echo "Uncomment to try resolving a real handle, e.g.:"
echo "  let (url, actor) = resolveActor(\"@zuck@mastodon.social\")"
echo "  echo url"
