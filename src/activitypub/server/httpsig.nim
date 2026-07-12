## HTTP Signatures (draft-cavage-12) for ActivityPub federation.
##
## Supports Ed25519 (primary) and RSA-SHA256 (legacy via openssl).
## Signing string format: each `header: value` line terminated with `\n`, including last line.

import std/[tables, times, strutils]
import std/json as stdjson
import ./crypto, ../datatypes/metatypes

export crypto

type
  SignatureParams* = object
    keyId*: string
    algorithm*: string
    headers*: seq[string]
    signature*: string

  HttpSignatureResult* = object
    date*: string
    digest*: string
    signature*: string

const
  dayNames: array[7, string] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  monthNumbers: array[12, string] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

proc httpDate*(t: Time = getTime()): string =
  ## Formats a `Time` as an HTTP-date string (RFC 7231, e.g. `Mon, 15 Jan 2024 10:00:00 GMT`).
  ##
  ## Used for the `Date` header in signed HTTP requests.
  let dt = t.utc
  result = dayNames[dt.weekday.ord] & ", "
  result.add(($dt.monthday).align(2, '0') & " ")
  result.add(monthNumbers[dt.month.ord - 1] & " ")
  result.add($dt.year & " ")
  result.add(($dt.hour).align(2, '0') & ":")
  result.add(($dt.minute).align(2, '0') & ":")
  result.add(($dt.second).align(2, '0') & " GMT")

proc parseHttpDate*(s: string): Time =
  ## Parses an HTTP-date string back into a `Time`.
  ## Reverse of `httpDate`.
  let parts = s.strip().split({' ', ','})
  var day, year, hour, minute, second: int
  var monthStr = ""
  var idx = 0
  for p in parts:
    if p.len == 0: continue
    case idx
    of 0: discard
    of 1: day = parseInt(p)
    of 2: monthStr = p
    of 3: year = parseInt(p)
    of 4:
      let timeParts = p.split(':')
      hour = parseInt(timeParts[0])
      minute = parseInt(timeParts[1])
      second = parseInt(timeParts[2])
    else: discard
    inc idx
  var month: Month
  for i, name in monthNumbers:
    if name == monthStr:
      month = Month(i + 1)
      break
  result = dateTime(year, month, day, hour, minute, second, 0, utc()).toTime

proc parseSignatureHeader*(header: string): SignatureParams =
  ## Parses an HTTP `Signature` header into `SignatureParams`.
  ##
  ## Extracts keyId, algorithm, headers, and signature from the structured format:
  ## `keyId="...",algorithm="ed25519",headers="...",signature="..."`
  result.algorithm = "ed25519"
  result.headers = @["(request-target)", "host", "date"]
  for part in header.split(','):
    let trimmed = part.strip()
    let eqPos = trimmed.find('=')
    if eqPos < 0: continue
    let key = trimmed[0..<eqPos].strip()
    var val = trimmed[eqPos+1..^1].strip()
    if val.startsWith('"') and val.endsWith('"'):
      val = val[1..^2]
    case key
    of "keyId": result.keyId = val
    of "algorithm": result.algorithm = val
    of "headers": result.headers = val.splitWhitespace()
    of "signature": result.signature = val
    else: discard

proc buildSigningString(`method`, path: string,
                         headers: seq[(string, string)],
                         signedHeaders: seq[string],
                         digest, date: string): string =
  ## Builds the signing string per draft-cavage-12.
  ##
  ## Each selected header is serialized as `lowercase-header: value\n`.
  ## `(request-target)` is synthesized as `(request-target): method path\n`.
  var headerMap = newTable[string, string]()
  for (k, v) in headers:
    headerMap[k.toLowerAscii()] = v
  if digest.len > 0: headerMap["digest"] = digest
  if date.len > 0: headerMap["date"] = date
  for h in signedHeaders:
    let hl = h.toLowerAscii()
    if hl == "(request-target)":
      result.add("(request-target): ")
      result.add(`method`.toLowerAscii())
      result.add(" ")
      result.add(path)
    elif hl == "digest" and digest.len > 0:
      result.add("digest: "); result.add(digest)
    elif hl == "date" and date.len > 0:
      result.add("date: "); result.add(date)
    elif headerMap.hasKey(hl):
      result.add(hl); result.add(": "); result.add(headerMap[hl])
    else: continue
    result.add("\n")

proc getPublicKeyPem*(actor: stdjson.JsonNode, keyId: string): string =
  ## Extracts a public key PEM from an actor document, matching by `keyId`.
  ##
  ## Handles both `publicKey` as a single object or an array (Pleroma-style).
  ## Returns empty string if not found.
  let pkNode = actor{"publicKey"}
  if pkNode.isNil or pkNode.kind == JNull: return ""
  case pkNode.kind
  of JArray:
    for pk in pkNode.items:
      if keyId.len == 0 or pk{"id"}.getStr == keyId:
        return pk{"publicKeyPem"}.getStr
  of JObject:
    if keyId.len == 0 or pkNode{"id"}.getStr == keyId:
      return pkNode{"publicKeyPem"}.getStr
  else: discard

proc signRequest*(`method`, path, host, body, keyId, secretKeyHex: string,
                   algorithm = "ed25519"): HttpSignatureResult =
  ## Signs an HTTP request with Ed25519 (or RSA-SHA256) per HTTP Signatures draft.
  ##
  ## Returns `HttpSignatureResult` with `date`, `digest`, and `signature` (the full
  ## Signature header value). The caller should attach these as the `Date`,
  ## `Digest`, and `Signature` headers respectively.
  ##
  ## Signed headers: (request-target), host, date, digest.
  let date = httpDate()
  let digest = sha256Digest(body)
  let signedHeaders = @["(request-target)", "host", "date", "digest"]
  let headers = @[("host", host)]
  let signingStr = buildSigningString(`method`, path, headers, signedHeaders, digest, date)
  let sigB64 = case algorithm
    of "ed25519": signEd25519(signingStr, secretKeyHex)
    of "rsa-sha256": signRsaSha256(signingStr, secretKeyHex)
    else: raise newException(ValueError, "unsupported algorithm: " & algorithm)
  let headersParam = signedHeaders.join(" ")
  HttpSignatureResult(
    date: date,
    digest: digest,
    signature: "keyId=\"" & keyId & "\"," &
               "algorithm=\"" & algorithm & "\"," &
               "headers=\"" & headersParam & "\"," &
               "signature=\"" & sigB64 & "\""
  )

proc verifyRequest*(`method`, path, body: string,
                     reqHeaders: seq[(string, string)],
                     actorJson: stdjson.JsonNode,
                     maxSkewSeconds: int64 = 30): bool =
  ## Verifies an HTTP Signature on an incoming request.
  ##
  ## Validates the `Digest` header, checks `Date` freshness (max 30s skew),
  ## reconstructs the signing string from the signed headers, and verifies
  ## the signature against the actor's public key.
  ##
  ## Supports Ed25519 and RSA-SHA256.
  ## Returns true if the signature is valid.
  var hmap = newTable[string, string]()
  for (k, v) in reqHeaders:
    hmap[k.toLowerAscii()] = v
  if not hmap.hasKey("signature"):
    return false
  let sigParams = parseSignatureHeader(hmap["signature"])
  if sigParams.signature.len == 0:
    return false
  let expectedDigest = sha256Digest(body)
  let reqDigest = hmap.getOrDefault("digest", "")
  if reqDigest.len > 0 and reqDigest != expectedDigest:
    return false
  let reqDate = hmap.getOrDefault("date", "")
  if reqDate.len > 0:
    try:
      let diff = (getTime() - parseHttpDate(reqDate)).inSeconds()
      if abs(diff) > maxSkewSeconds:
        return false
    except: discard
  let signingStr = buildSigningString(`method`, path, reqHeaders, sigParams.headers, reqDigest, reqDate)
  let publicKeyPem = getPublicKeyPem(actorJson, sigParams.keyId)
  if publicKeyPem.len == 0:
    return false
  case sigParams.algorithm
  of "ed25519":
    verifyEd25519(signingStr, sigParams.signature, publicKeyPem)
  of "rsa-sha256":
    verifyRsaSha256(signingStr, sigParams.signature, publicKeyPem)
  else:
    false
