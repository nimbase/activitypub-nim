# ActivityPub implementation in Nim
#   (c) 2026 Made by Humans from OpenPeeps | MIT License
#   https://github.com/openpeeps/activitypub-nim

## This module defines the collection types for ActivityStreams
## objects and links as per the ActivityStreams Vocabulary.
import ./metatypes, ./coretypes

type
  CollectionType* = enum
    ## Defines the different types of Collections in the ActivityStreams Vocabulary.
    ctCollection = "Collection"
    ctOrderedCollection = "OrderedCollection"
    ctCollectionPage = "CollectionPage"
    ctOrderedCollectionPage = "OrderedCollectionPage"

  CollectionBase* = object of ObjectBase
    ## Base type for Collection and OrderedCollection in the ActivityStreams Vocabulary.
    ## https://www.w3.org/TR/activitystreams-core/#collections
    `type`*: CollectionType
      ## The type of the collection, indicating its role or purpose.
    totalItems*: Option[int]
      ## The total number of items in the collection.
    current*: Option[JsonNode]
      ## A reference to the current page of items in the collection, if paginated.
    first*: Option[JsonNode]
      ## A reference to the first page of items in the collection, if paginated.
    last*: Option[JsonNode]
      ## A reference to the last page of items in the collection, if paginated.

  Collection* = object of CollectionBase
    ## Represents a Collection in the ActivityStreams Vocabulary.
    ## https://www.w3.org/TR/activitystreams-core/#collections
    items*: Option[seq[JsonNode]]
      ## A list of items contained in the collection.

  OrderedCollection* = object of CollectionBase
    ## Represents an OrderedCollection in the ActivityStreams Vocabulary.
    ## https://www.w3.org/TR/activitystreams-core/#orderedcollections
    orderedItems*: Option[seq[JsonNode]]
      ## A list of items contained in the ordered collection, in a specific order.

  CollectionPage* = object of CollectionBase
    ## Represents a CollectionPage in the ActivityStreams Vocabulary.
    ## https://www.w3.org/TR/activitystreams-core/#collectionpages
    items*: Option[seq[JsonNode]]
      ## A list of items contained in the collection page.
    partOf*: Option[JsonNode]
      ## Identifies the collection to which this page belongs.
    next*: Option[JsonNode]
      ## A link to the next page in the collection.
    prev*: Option[JsonNode]
      ## A link to the previous page in the collection.

  OrderedCollectionPage* = object of CollectionPage
    ## Represents an OrderedCollectionPage in the ActivityStreams Vocabulary.
    ## https://www.w3.org/TR/activitystreams-core/#orderedcollectionpages
    orderedItems*: Option[seq[JsonNode]]
      ## A list of items contained in the ordered collection page, in a specific order.
    startIndex*: Option[int]
      ## A zero-based index value indicating the position of the first item in this page
      ## relative to the containing ordered collection.
