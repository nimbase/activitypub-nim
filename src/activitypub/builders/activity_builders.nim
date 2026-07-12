## Activity builders — construct ActivityPub activities and objects with
## auto-generated UUIDs, timestamps, and `@context`.
##
## All builders return fully-populated Nim types ready for serialization or delivery.

import std/[times, options]
import openparser/json as opj
import openparser/uuid
import ../datatypes/[metatypes, coretypes, activitytypes]

export metatypes, coretypes, activitytypes

proc toAddresses(addrs: openArray[string]): Option[Addresses] =
  if addrs.len == 0: return none(Addresses)
  var items: seq[JsonNode]
  for a in addrs:
    items.add(%* a)
  some(Addresses(items: items))

proc nowIso*(): string =
  ## Returns the current UTC time as an ISO 8601 string (`2024-01-15T10:00:00Z`).
  getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc buildNote*(content: string, attributedTo: string,
                summary: string = "",
                to: seq[string] = @[], cc: seq[string] = @[]): Note =
  ## Builds a `Note` object with auto-generated UUID, `@context`, and `published` timestamp.
  ##
  ## - `content`: the note body text
  ## - `attributedTo`: the actor URL of the author
  ## - `summary`: optional content warning / summary
  ## - `to`, `cc`: addressing arrays of actor URLs
  var note = Note(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: otNote,
    content: some(content),
    attributedTo: some(%* attributedTo),
    published: some(nowIso()),
    to: toAddresses(to),
    cc: toAddresses(cc)
  )
  if summary.len > 0:
    note.summary = some(summary)
  note

proc buildFollow*(actor, target: string): Follow =
  ## Builds a `Follow` activity: `actor` is following `target`.
  ##
  ## The `to` field is set to the target's actor URL so they receive the activity.
  Follow(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: FollowType,
    actor: some(%* actor),
    `object`: some(%* target),
    to: some(Addresses(items: @[%* target]))
  )

proc followerAddress(follow: Follow): Option[Addresses] =
  let actorNode = follow.actor
  if actorNode.isSome:
    let actorVal = actorNode.get
    if actorVal.kind == JString:
      return some(Addresses(items: @[actorVal]))
  none(Addresses)

proc buildAccept*(actor: string, follow: Follow): Accept =
  ## Builds an `Accept` activity in response to a `Follow`.
  ##
  ## The original `Follow` is embedded as the `object`. The `to` field is set to
  ## the follower's actor URL extracted from the Follow activity.
  Accept(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: AcceptType,
    actor: some(%* actor),
    `object`: some(opj.toJsonNode(follow)),
    to: followerAddress(follow)
  )

proc buildReject*(actor: string, follow: Follow): Reject =
  ## Builds a `Reject` activity in response to a `Follow`.
  ##
  ## Same structure as `buildAccept` but with `type` set to `Reject`.
  Reject(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: RejectType,
    actor: some(%* actor),
    `object`: some(opj.toJsonNode(follow)),
    to: followerAddress(follow)
  )

proc buildCreate*[T: ObjectBase](actor: string, obj: T,
                  to: seq[string] = @[], cc: seq[string] = @[]): Create =
  ## Wraps an `ObjectBase` (e.g. `Note`, `Article`) in a `Create` activity.
  ##
  ## Generic over `T: ObjectBase` — preserves all type-specific fields including
  ## the concrete object `type` (e.g. `"Note"`, `"Article"`).
  Create(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: CreateType,
    actor: some(%* actor),
    `object`: some(opj.toJsonNode(obj)),
    to: toAddresses(to),
    cc: toAddresses(cc)
  )

proc buildDelete*(actor, objectId: string): Delete =
  ## Builds a `Delete` activity referencing an object by URL.
  ##
  ## The `object` field is set to the object's URL string (not the full object).
  Delete(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: DeleteType,
    actor: some(%* actor),
    `object`: some(%* objectId)
  )

proc buildUpdate*[T: ObjectBase](actor: string, obj: T): Update =
  ## Builds an `Update` activity wrapping an updated object.
  ##
  ## Generic over `T: ObjectBase` — the updated object is embedded as `object`.
  Update(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: UpdateType,
    actor: some(%* actor),
    `object`: some(opj.toJsonNode(obj))
  )

proc buildAnnounce*[T: ObjectBase](actor: string, obj: T,
                    to: seq[string] = @[], cc: seq[string] = @[]): Announce =
  ## Builds an `Announce` (boost/repeat) activity wrapping an object.
  ##
  ## Generic over `T: ObjectBase` — the announced object is embedded as `object`.
  Announce(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: AnnounceType,
    actor: some(%* actor),
    `object`: some(opj.toJsonNode(obj)),
    to: toAddresses(to),
    cc: toAddresses(cc)
  )

proc buildLike*(actor, objectId: string): Like =
  ## Builds a `Like` activity referencing an object by URL.
  ##
  ## The `object` field is set to the liked object's URL.
  Like(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: LikeType,
    actor: some(%* actor),
    `object`: some(%* objectId)
  )

proc buildUndo*[T: ActivityBase](actor: string, obj: T): Undo =
  ## Wraps an `ActivityBase` (e.g. `Follow`, `Like`) in an `Undo` activity.
  ##
  ## Generic over `T: ActivityBase` — the original activity is embedded as `object`.
  Undo(
    `@context`: some(%* "https://www.w3.org/ns/activitystreams"),
    id: some($v4()),
    `type`: UndoType,
    actor: some(%* actor),
    `object`: some(opj.toJsonNode(obj))
  )
