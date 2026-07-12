## Collection pagination — fetch and iterate ActivityPub collections
## (outbox, followers, following, etc.) with automatic page traversal.
##
## Usage:
##   let coll = fetchCollection("https://remote.social/users/alice/outbox")
##   let page = fetchCollectionPage(coll.first.get.getStr)
##   let allItems = fetchAllItems("https://remote.social/users/alice/followers")

import std/json
import openparser/json as opj
import ../datatypes/[metatypes, collectiontypes]
import ./federation

export metatypes, collectiontypes

proc fetchCollection*(url: string): Collection =
  ## Fetches a `Collection` or `OrderedCollection` from a URL.
  ##
  ## Parses the JSON response into a `Collection` type.
  ## Raises `IOError` if the URL is unreachable, or `ValueError` if the
  ## response is not a valid collection.
  let json = fetchObject(url)
  let typeStr = json{"type"}.getStr("")
  if typeStr notin ["Collection", "OrderedCollection"]:
    raise newException(ValueError, "not a collection: " & url & " (type=" & typeStr & ")")
  result = opj.fromJson($json, Collection)

proc fetchCollectionPage*(url: string): CollectionPage =
  ## Fetches a `CollectionPage` or `OrderedCollectionPage` from a URL.
  ##
  ## Parses the JSON response into a `CollectionPage` type.
  ## Raises `IOError` if the URL is unreachable, or `ValueError` if the
  ## response is not a valid collection page.
  let json = fetchObject(url)
  let typeStr = json{"type"}.getStr("")
  if typeStr notin ["CollectionPage", "OrderedCollectionPage"]:
    raise newException(ValueError, "not a collection page: " & url & " (type=" & typeStr & ")")
  result = opj.fromJson($json, CollectionPage)

proc fetchAllItems*(url: string): seq[JsonNode] =
  ## Fetches all items from a paginated collection by following `first` → `next` links.
  ##
  ## If the collection has inline `items`/`orderedItems`, returns those directly.
  ## Otherwise follows the pagination chain (supports both Collection and CollectionPage).
  ##
  ## Raises `IOError` on network errors.
  let json = fetchObject(url)
  let typeStr = json{"type"}.getStr("")

  # Try inline items first
  if json{"items"}.kind == JArray:
    for item in json["items"]:
      result.add(item)
    return
  if json{"orderedItems"}.kind == JArray:
    for item in json["orderedItems"]:
      result.add(item)
    return

  # Follow first link
  var pageUrl: string
  if json{"first"}.kind == JString:
    pageUrl = json{"first"}.getStr
  elif json{"first"}.kind == JObject and json{"first"}{"id"}.kind == JString:
    pageUrl = json{"first"}{"id"}.getStr
  elif typeStr in ["CollectionPage", "OrderedCollectionPage"] and json{"id"}.kind == JString:
    pageUrl = json{"id"}.getStr
  else:
    return

  while pageUrl.len > 0:
    let pageJson = fetchObject(pageUrl)
    if pageJson{"items"}.kind == JArray:
      for item in pageJson["items"]:
        result.add(item)
    if pageJson{"orderedItems"}.kind == JArray:
      for item in pageJson["orderedItems"]:
        result.add(item)
    if pageJson{"next"}.kind == JString:
      pageUrl = pageJson{"next"}.getStr
    elif pageJson{"next"}.kind == JObject and pageJson{"next"}{"id"}.kind == JString:
      pageUrl = pageJson{"next"}{"id"}.getStr
    else:
      pageUrl = ""
