## WebFinger (RFC 7033) client and server helpers for ActivityPub actor discovery.
##
## Client: `resolveActor(handle)` fetches an actor JSON document from `@user@domain`.
## Server: `buildJrd(subject, actorUrl)` constructs a JRD JSON response for `/.well-known/webfinger`.

import std/[httpclient, json, uri, strutils]
import ../datatypes/metatypes

proc parseHandle*(handle: string): tuple[user: string, domain: string] =
  ## Parses an ActivityPub actor handle into (username, domain) tuple.
  ##
  ## Accepts formats:
  ## - `@user@domain`
  ## - `user@domain`
  ## - `acct:user@domain`
  ##
  ## Raises `ValueError` if the handle is malformed.
  let clean = handle.strip(chars = {'@', ' '})
  if clean.startsWith("acct:"):
    let inner = clean[5..^1]
    let parts = inner.split('@')
    if parts.len != 2 or parts[0].len == 0 or parts[1].len == 0:
      raise newException(ValueError, "malformed acct: URI: " & handle)
    (parts[0], parts[1])
  elif '@' in clean:
    let parts = clean.split('@')
    if parts.len != 2 or parts[0].len == 0 or parts[1].len == 0:
      raise newException(ValueError, "malformed handle: " & handle)
    (parts[0], parts[1])
  else:
    raise newException(ValueError, "not an actor handle: " & handle)

proc resolveActor*(handle: string): tuple[actorUrl: string, actor: JsonNode] =
  ## Resolves an ActivityPub actor handle to the actor's JSON document and URL.
  ##
  ## Performs WebFinger lookup on the domain, finds the ActivityPub `self` link,
  ## then fetches the actor JSON. Returns (actorUrl, actorJson).
  ##
  ## Raises `IOError` on HTTP failures or missing links.
  let (user, domain) = parseHandle(handle)
  let client = newHttpClient()
  try:
    client.headers = newHttpHeaders({
      "Accept": "application/jrd+json, application/json",
      "User-Agent": "activitypub-nim/0.1.0"
    })
    let wfUrl = "https://" & domain & "/.well-known/webfinger?resource=acct:" & user & "@" & domain
    let wfResp = client.get(wfUrl)
    if wfResp.code != Http200:
      raise newException(IOError, "WebFinger lookup failed (" & $wfResp.code & "): " & domain & " for user " & user)
    let jrd = parseJson(wfResp.body)
    var actorUrl: string
    for link in jrd["links"]:
      if link{"rel"}.getStr == "self":
        let t = link{"type"}.getStr
        if t == "application/activity+json" or
           t == "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\"":
          actorUrl = link["href"].getStr
          break
    if actorUrl.len == 0:
      raise newException(IOError, "no ActivityPub actor link in WebFinger response from " & domain)
    client.headers = newHttpHeaders({
      "Accept": "application/activity+json"
    })
    let actorResp = client.get(actorUrl)
    if actorResp.code != Http200:
      raise newException(IOError, "failed to fetch actor (" & $actorResp.code & "): " & actorUrl)
    (actorUrl, parseJson(actorResp.body))
  finally:
    client.close()

proc buildJrd*(subject: string, actorUrl: string,
                aliases: seq[string] = @[],
                profilePage: string = "",
                avatarUrl: string = ""): JsonNode =
  ## Builds a WebFinger JRD JSON response for serving via `/.well-known/webfinger`.
  ##
  ## - `subject` is the acct URI (e.g. `acct:user@domain`)
  ## - `actorUrl` is the ActivityPub actor URL
  ## - `aliases` optional list of alias URIs
  ## - `profilePage` optional URL for the profile page link
  ## - `avatarUrl` optional URL for the avatar image link
  result = %* {"subject": subject}
  if aliases.len > 0:
    result["aliases"] = %* aliases
  var links = newJArray()
  var selfLink = %* {
    "rel": "self",
    "type": "application/activity+json",
    "href": actorUrl
  }
  links.add(selfLink)
  if profilePage.len > 0:
    links.add(%* {
      "rel": "http://webfinger.net/rel/profile-page",
      "type": "text/html",
      "href": profilePage
    })
  if avatarUrl.len > 0:
    links.add(%* {
      "rel": "http://webfinger.net/rel/avatar",
      "type": "image/jpeg",
      "href": avatarUrl
    })
  result["links"] = links
