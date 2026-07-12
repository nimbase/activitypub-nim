# ActivityPub implementation in Nim
#   (c) 2026 Made by Humans from OpenPeeps | MIT License
#   https://github.com/openpeeps/activitypub-nim

import ./metatypes, ./coretypes

## This module defines the Activity types for ActivityStreams
## as per the ActivityStreams Vocabulary.
##
## https://www.w3.org/TR/activitystreams-vocabulary/#activity-types

type
  ActivityType* = enum
    ## ActivityStreams Activity Types
    AcceptType = "Accept"
    AddType = "Add"
    AnnounceType = "Announce"
    ArriveType = "Arrive"
    BlockType = "Block"
    CreateType = "Create"
    DeleteType = "Delete"
    DislikeType = "Dislike"
    FlagType = "Flag"
    FollowType = "Follow"
    IgnoreType = "Ignore"
    InviteType = "Invite"
    JoinType = "Join"
    LeaveType = "Leave"
    LikeType = "Like"
    ListenType = "Listen"
    MoveType = "Move"
    OfferType = "Offer"
    QuestionType = "Question"
    RejectType = "Reject"
    ReadType = "Read"
    RemoveType = "Remove"
    TentativeRejectType = "TentativeReject"
    TentativeAcceptType = "TentativeAccept"
    TravelType = "Travel"
    UndoType = "Undo"
    UpdateType = "Update"
    ViewType = "View"

  ActivityBase* = object of ObjectBase
    ## Base Activity object that includes common properties for all Activity types.
    `type`*: ActivityType
    actor*: Option[JsonNode]
      ## The actor that performed the activity.
    `object`*: Option[JsonNode]
      ## The direct object of the activity.
    target*: Option[JsonNode]
      ## The target of the activity.
    `result`*: Option[JsonNode]
      ## The result of the activity.
    origin*: Option[JsonNode]
      ## The origin of the activity.
    instrument*: Option[JsonNode]
      ## The instrument used to perform the activity.

  IntransitiveActivityBase* = object of ActivityBase
    ## Base type for activities that do not have an `object` property.
    ## Examples: Arrive, Question, Travel

  #
  # Concrete Activity Types
  #

  Accept* = object of ActivityBase
    ## Actor accepts the object (e.g., accepts a Follow request).
  Add* = object of ActivityBase
    ## Actor adds the object to the target.
  Announce* = object of ActivityBase
    ## Actor shares/boosts the object.
  Arrive* = object of IntransitiveActivityBase
    ## Actor has arrived at the location. No object property.
  Block* = object of ActivityBase
    ## Actor blocks the object (stronger form of Ignore).
  Create* = object of ActivityBase
    ## Actor created the object.
  Delete* = object of ActivityBase
    ## Actor deleted the object.
  Dislike* = object of ActivityBase
    ## Actor dislikes the object.
  Flag* = object of ActivityBase
    ## Actor flagged the object as inappropriate.
  Follow* = object of ActivityBase
    ## Actor is following the object. Used to subscribe to an actor's activities.
  Ignore* = object of ActivityBase
    ## Actor is ignoring the object.
  Invite* = object of ActivityBase
    ## A specialization of Offer: actor invites the object to the target.
  Join* = object of ActivityBase
    ## Actor has joined the object (e.g., a Group).
  Leave* = object of ActivityBase
    ## Actor has left the object.
  Like* = object of ActivityBase
    ## Actor likes/recommends/endorses the object.
  Listen* = object of ActivityBase
    ## Actor listened to the object.
  Move* = object of ActivityBase
    ## Actor moved the object from origin to target.
  Offer* = object of ActivityBase
    ## Actor is offering the object to the target.
  Question* = object of IntransitiveActivityBase
    ## A question being asked.
    oneOf*: Option[seq[JsonNode]]
      ## A list of possible answers (exclusive choice).
    anyOf*: Option[seq[JsonNode]]
      ## A list of possible answers (inclusive choice).
    closed*: Option[JsonNode]
      ## Indicates when or if the question was closed.
      ## Can be a date-time string, boolean, or nil.
  Read* = object of ActivityBase
    ## Actor read the object.
  Reject* = object of ActivityBase
    ## Actor rejects the object (e.g., rejects a Follow request).
  Remove* = object of ActivityBase
    ## Actor removes the object. `origin` indicates the context it is removed from.
  TentativeAccept* = object of ActivityBase
    ## Acceptance is tentative.
  TentativeReject* = object of ActivityBase
    ## Rejection is tentative.
  Travel* = object of IntransitiveActivityBase
    ## Actor is traveling to target from origin.
  Undo* = object of ActivityBase
    ## Actor undoes the object activity (e.g., undoes a Like).
  Update* = object of ActivityBase
    ## Actor updated the object.
  View* = object of ActivityBase
    ## Actor viewed the object.

# https://github.com/go-ap/activitypub/blob/master/activity.go#L17

const
  ContentManagementActivityTypes* = {CreateType, DeleteType, UpdateType}
    ## use case primarily deals with activities that involve
    ## the creation, modification or deletion of content.
    ## https://www.w3.org/TR/activitystreams-vocabulary/#motivations-crud
  CollectionManagementActivityTypes* = {AddType, MoveType, RemoveType}

  ReactionsActivityTypes* = {
    AcceptType, BlockType, DislikeType,
    FlagType, IgnoreType, LikeType, RejectType,
    TentativeAcceptType, TentativeRejectType
  }

    ## ReactionsActivityTypes use case primarily deals with reactions to content
    ## This can include activities such as liking or disliking content, ignoring
    ## updates, flagging content as being inappropriate, accepting or rejecting objects, etc.

  EventRSVPActivityTypes = {
    AcceptType, IgnoreType, InviteType, RejectType,
    TentativeAcceptType, TentativeRejectType,
  }

  GroupManagementActivityTypes = {AddType, JoinType, LeaveType, RemoveType}
