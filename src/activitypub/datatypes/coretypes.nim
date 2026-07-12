# ActivityPub implementation in Nim
#   (c) 2026 Made by Humans from OpenPeeps | MIT License
#   https://github.com/openpeeps/activitypub-nim

## This module defines the core types for ActivityStreams
## objects and links as per the ActivityStreams Vocabulary.
##
## https://www.w3.org/TR/activitystreams-vocabulary/#core-types

import ./metatypes

type
  ObjectType* = enum
    ## ActivityStreams Object Types
    otObject = "Object"
    otArticle = "Article"
    otAudio = "Audio"
    otDocument = "Document"
    otEvent = "Event"
    otImage = "Image"
    otNote = "Note"
    otPage = "Page"
    otPlace = "Place"
    otProfile = "Profile"
    otRelationship = "Relationship"
    otTombstone = "Tombstone"
    otVideo = "Video"

  PlaceUnits* = enum
    puCm = "cm"
    puFeet = "feet"
    puInches = "inches"
    puKm = "km"
    puM = "m"
    puMiles = "miles"

  Source* = object
    ## Original source content before rendering/transformation
    content*: Option[string]
    mediaType*: Option[MimeType]

  ObjectBase* = object of RootObj
    ## Base ActivityStreams Object
    `@context`*: Option[JsonNode]
      ## The JSON-LD context for the object, which can be a single IRI or an array of IRIs.
    id*: Option[ID]
      ## The unique identifier for the object, typically a URI or IRI that
      ## can be dereferenced to obtain more information about the object.
    name*: Option[string]
      ## The name of the object, a simple human-readable plain-text string.
    content*: Option[string]
      ## The content or textual representation, typically HTML.
    summary*: Option[string]
      ## A short summary, often used as a "content warning" or "subject line".
    mediaType*: Option[MimeType]
      ## The media type of the content, if applicable (e.g., "text/plain", "image/jpeg").
    published*: Option[string]
      ## The publication date of the object, if applicable (ISO 8601).
    updated*: Option[string]
      ## The last updated date of the object, if applicable (ISO 8601).
    startTime*: Option[string]
      ## The start time of the object, if applicable (ISO 8601).
    endTime*: Option[string]
      ## The end time of the object, if applicable (ISO 8601).
    duration*: Option[string]
      ## The duration of the object, if applicable (ISO 8601 duration format).
    url*: Option[JsonNode]
      ## A reference to the URL of the object, which can be a string URI or a Link object.
    attributedTo*: Option[JsonNode]
      ## The actor or actors to which the object is attributed.
      ## This can be an Actor or a Link to an Actor.
    attachment*: Option[seq[JsonNode]]
      ## An attachment associated with the object. This can be an Object or a Link.
    audience*: Option[JsonNode]
      ## The intended audience for the object.
    to*: Option[Addresses]
      ## The primary audience for the object.
    bto*: Option[Addresses]
      ## The private primary audience (Blind To).
    cc*: Option[Addresses]
      ## The secondary audience for the object.
    bcc*: Option[Addresses]
      ## The private secondary audience (Blind Carbon Copy).
    context*: Option[JsonNode]
      ## A reference to the context of the object, which can be an Object or a Link.
    generator*: Option[JsonNode]
      ## A reference to the software used to generate the object.
    icon*: Option[JsonNode]
      ## An icon associated with the object. This can be an Object or a Link.
    image*: Option[JsonNode]
      ## An image associated with the object. This can be an Object or a Link.
    inReplyTo*: Option[JsonNode]
      ## A reference to the object that this object is in reply to.
    location*: Option[JsonNode]
      ## A reference to the location of the object.
    preview*: Option[JsonNode]
      ## A preview of the object.
    replies*: Option[JsonNode]
      ## A reference to the replies to the object, typically a Collection.
    tag*: Option[seq[JsonNode]]
      ## Tags associated with the object.
    contentMap*: Option[JsonNode]
      ## A map of language tags to content values.
    nameMap*: Option[JsonNode]
      ## A map of language tags to name values.
    summaryMap*: Option[JsonNode]
      ## A map of language tags to summary values.
    likes*: Option[JsonNode]
      ## A reference to the likes of the object, typically a Collection.
    shares*: Option[JsonNode]
      ## A reference to the shares of the object, typically a Collection.
    source*: Option[Source]
      ## The original source content before rendering/transformation.

  Article* = object of ObjectBase
    ## Represents an Article object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otArticle

  Audio* = object of ObjectBase
    ## Represents an Audio object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otAudio

  Document* = object of ObjectBase
    ## Represents a Document object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otDocument

  Event* = object of ObjectBase
    ## Represents an Event object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otEvent

  Image* = object of ObjectBase
    ## Represents an Image object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otImage

  Note* = object of ObjectBase
    ## Represents a Note object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otNote

  Page* = object of ObjectBase
    ## Represents a Page object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otPage

  Video* = object of ObjectBase
    ## Represents a Video object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otVideo

  Place* = object of ObjectBase
    ## Represents a Place object in the ActivityStreams Vocabulary.
    `type`*: ObjectType = otPlace
    accuracy*: Option[float]
      ## The accuracy of the location information, in meters.
    altitude*: Option[float]
      ## The altitude of the place, in meters above sea level.
    latitude*: Option[float]
      ## The latitude of the place, in decimal degrees.
    longitude*: Option[float]
      ## The longitude of the place, in decimal degrees.
    radius*: Option[float]
      ## The radius of the place, in meters.
    units*: Option[PlaceUnits]
      ## The units used for measurements (e.g., "m" for meters, "km" for kilometers).

  Profile* = object of ObjectBase
    `type`*: ObjectType = otProfile
    describes*: Option[JsonNode]
      ## A reference to the object that this profile describes.

  Relationship* = object of ObjectBase
    `type`*: ObjectType = otRelationship
    subject*: Option[JsonNode]
    `object`*: Option[JsonNode]
    relationship*: Option[JsonNode]

  Tombstone* = object of ObjectBase
    `type`*: ObjectType = otTombstone
    formerType*: Option[seq[ObjectType]]
    deleted*: Option[string]
      ## The date the object was deleted (ISO 8601).

  LinkType* = enum
    ## ActivityStreams Link Types
    ltLink = "Link"
    ltMention = "Mention"

  LinkBase* = object of RootObj
    ## Base ActivityStreams Link
    `type`*: Option[LinkType] = none(LinkType)
    id*: Option[ID]
    href*: Option[ID]
    rel*: Option[seq[string]]
    mediaType*: Option[MimeType]
    name*: Option[string]
    hreflang*: Option[seq[string]]
    height*: Option[int]
    width*: Option[int]
    preview*: Option[JsonNode]

  Link* = object of LinkBase
  Mention* = object of LinkBase

#
# Public API — Constructors
#
proc newArticle*(id: ID = default(ID)): Article =
  Article(id: some(id))

proc newAudio*(id: ID = default(ID)): Audio =
  Audio(id: some(id))

proc newDocument*(id: ID = default(ID)): Document =
  Document(id: some(id))

proc newEvent*(id: ID = default(ID)): Event =
  Event(id: some(id))

proc newImage*(id: ID = default(ID)): Image =
  Image(id: some(id))

proc newNote*(id: ID = default(ID)): Note =
  Note(id: some(id))

proc newPage*(id: ID = default(ID)): Page =
  Page(id: some(id))

proc newVideo*(id: ID = default(ID)): Video =
  Video(id: some(id))

proc newPlace*(id: ID = default(ID)): Place =
  Place(id: some(id))

proc newProfile*(id: ID = default(ID)): Profile =
  Profile(id: some(id))

proc newRelationship*(id: ID = default(ID)): Relationship =
  Relationship(id: some(id))

proc newTombstone*(id: ID = default(ID)): Tombstone =
  Tombstone(id: some(id))

proc newLink*(id: ID = default(ID), href: ID = default(ID)): Link =
  Link(id: some(id), href: some(href))

proc newMention*(id: ID = default(ID), href: ID = default(ID)): Mention =
  Mention(id: some(id), href: some(href))
