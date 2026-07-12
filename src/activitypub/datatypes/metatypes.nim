import std/[uri, options]
import pkg/openparser/json
export uri, options, json

type
  ID* = string
    ## Represents a unique identifier for an ActivityStreams object or link.
    ## Typically a URI or IRI that can be dereferenced to obtain more information about the object.

  MimeType* = distinct string
    ## Represents a MIME type, used to specify the media type of content.
    ## Examples include "text/plain", "image/jpeg", "application/json", etc.

  Addresses* = object
    ## Normalizes single-value JSON fields to arrays for `to`/`cc`/`bto`/`bcc` etc.
    ## Accepts both `"to": "someone"` and `"to": ["someone", "someone-else"]`
    items*: seq[JsonNode]

  PublicKey* = object
    ## ActivityPub actor public key descriptor.
    ## https://www.w3.org/TR/activitypub/#public-key
    id*: Option[ID]
    owner*: Option[ID]
    publicKeyPem*: Option[string]

  Endpoints* = object
    ## ActivityPub actor endpoints extension.
    ## https://www.w3.org/TR/activitypub/#endpoints
    proxyUrl*: Option[ID]
    oauthAuthorizationEndpoint*: Option[ID]
    oauthTokenEndpoint*: Option[ID]
    provideClientKey*: Option[ID]
    signClientKey*: Option[ID]
    sharedInbox*: Option[ID]

proc parseHook*(parser: var json.JsonParser, v: var Addresses) =
  if parser.curr.kind == jtkLBracket:
    parser.expectSkip(jtkLBracket)
    while parser.curr.kind != jtkRBracket:
      var item: JsonNode
      parser.parseHook(item)
      v.items.add(item)
      ensureComma()
    parser.expectSkip(jtkRBracket)
  else:
    var item: JsonNode
    parser.parseHook(item)
    v.items = @[item]

proc dumpHook*(s: var string, v: Addresses) =
  s.add("[")
  for i, item in v.items:
    if i > 0: s.add(",")
    dumpHook(s, item)
  s.add("]")
