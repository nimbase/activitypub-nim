# ActivityPub implementation in Nim
#   (c) 2026 Made by Humans from OpenPeeps | MIT License
#   https://github.com/openpeeps/activitypub-nim

import ./metatypes, ./coretypes

## This module defines the Actor types for ActivityStreams
## as per the ActivityStreams Vocabulary.
##
## https://www.w3.org/TR/activitystreams-vocabulary/#actor-types

type
  ActorTypes* = enum
    ## Defines the different types of Actors in the ActivityStreams Vocabulary.
    ## https://www.w3.org/TR/activitystreams-vocabulary/#actor-types
    ApplicationType = "Application"
    GroupType = "Group"
    OrganizationType = "Organization"
    PersonType = "Person"
    ServiceType = "Service"

  ActorBase* = object of ObjectBase
    ## Base Actor object that includes common properties for all Actor types.
    `type`*: ActorTypes
    inbox*: Option[JsonNode]
      ## The inbox URL where the Actor receives activities.
    outbox*: Option[JsonNode]
      ## The outbox URL where the Actor sends activities.
    following*: Option[JsonNode]
      ## The URL of the collection of entities the Actor is following.
    followers*: Option[JsonNode]
      ## The URL of the collection of followers for the Actor.
    liked*: Option[JsonNode]
      ## The URL of the collection of objects the Actor has liked.
    preferredUsername*: Option[string]
      ## A short username with no uniqueness guarantees.
    endpoints*: Option[Endpoints]
      ## A JSON object mapping additional endpoints.
    streams*: Option[seq[JsonNode]]
      ## A list of supplementary Collections of interest.
    publicKey*: Option[PublicKey]
      ## The public key associated with the Actor.

  Application* = object of ActorBase
    ## Represents an Application actor in the ActivityStreams Vocabulary.

  Person* = object of ActorBase
    ## Represents a Person actor in the ActivityStreams Vocabulary.

  Service* = object of ActorBase
    ## Represents a Service actor in the ActivityStreams Vocabulary.

  Organization* = object of ActorBase
    ## Represents an Organization actor in the ActivityStreams Vocabulary.

  Group* = object of ActorBase
    ## Represents a Group actor in the ActivityStreams Vocabulary.

proc newActorBase*(atype: ActorTypes, id: ID = default(ID)): ActorBase =
  ActorBase(`type`: atype, id: some(id))

proc newApplication*(id: ID = default(ID)): Application =
  Application(`type`: ApplicationType, id: some(id))

proc newPerson*(id: ID = default(ID)): Person =
  Person(`type`: PersonType, id: some(id))

proc newService*(id: ID = default(ID)): Service =
  Service(`type`: ServiceType, id: some(id))

proc newOrganization*(id: ID = default(ID)): Organization =
  Organization(`type`: OrganizationType, id: some(id))

proc newGroup*(id: ID = default(ID)): Group =
  Group(`type`: GroupType, id: some(id))
