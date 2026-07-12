<p align="center">
  ActivityPub implementation in Nim 
</p>

<p align="center">
  <code>nimble install activitypub</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/activitypub-nim/">API reference</a><br>
  <img src="https://github.com/openpeeps/activitypub-nim/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/activitypub-nim/workflows/docs/badge.svg" alt="Github Actions">
</p>


## Features
- Full ActivityPub core, activity, and actor data types (JSON-LD serialization/deserialization)
- WebFinger client (`webfinger`, `buildJrd`)
- HTTP Signatures (Ed25519 and RSA SHA-256)
- Ed25519 and RSA keypair generation, PEM export/import
- Federation engine: deliver activities to remote inboxes, fetch remote actors
- Client-to-Server (C2S) API: `postToOutbox`, `getOutbox`, `getFollowers`, `getFollowing`
- Inbox dispatcher with type-based routing and HTTP Signature verification
- Activity builders: `buildFollow`, `buildAccept`, `buildReject`, `buildUndo`, `buildCreate`, `buildDelete`, `buildNote`, `buildCollectionPage`, `buildOrderedCollection`, `buildCollection`
- Collection pagination: `fetchCollection`, `fetchCollectionPage`, `fetchAllItems`
- Built-in HTTP server (powered by [pkg/powpow](https://github.com/openpeeps/powpow)) with:
  - Routes for WebFinger
  - Actor profiles, inbox, outbox, followers, and following

### Requirements
```
requires "nim >= 2.0.0"
requires "openparser >= 0.1.6"
requires "checksums >= 0.2.2"
requires "e2ee > 0.1.0"       # `monocypher` is required
requires "powpow > 0.1.4"
requires "ormin#head"
```

## Roadmap
- Persistent storage backends (SQLite, PostgreSQL) using [pkg/ormin](https://github.com/araq/ormin)
- C2S client-to-server endpoints (POST `/users/{id}/outbox`, GET `/users/{id}/following`)
- Activity forwarding and shared inbox support
- Object retrieval with forward/fetch (`object` property resolution)
- ActivityStreams vocabulary types coverage
- Linked Data Signatures (2017/2019)
- FEP compatibility (FEP-2677, FEP-8cf5, FEP-7888)
- Rate limiting and request validation middleware
- Support non-spec ecosystem extensions (Mastodon's Hashtag, Emoji, PropertyValue)
- API stabilization for v1.0.0 release

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/activitypub-nim/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/activitypub-nim/fork)

|  |  |
|---|---|
| <a href="https://opencode.ai/go?ref=BHMEEK48QX"><img src="https://github.com/openpeeps/pistachio/blob/main/.github/opencode.png" alt="OpenCode"></a> | Switch to **Open-Source LLMs** via OpenCode GO, choosing from a variety of powerful models such as DeepSeek, Qwen, Kimi, GLM-5, MiniMax, MiMo. 🍕 [Use our referral link to get started!](https://opencode.ai/go?ref=BHMEEK48QX)|

### 🎩 License
`MIT` license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2026 OpenPeeps & Contributors &mdash; All rights reserved.
