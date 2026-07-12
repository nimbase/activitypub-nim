## Cryptographic operations for ActivityPub HTTP Signatures.
##
## Uses `e2ee` (Monocypher) for Ed25519 and `checksums` for SHA-256.
## RSA-SHA256 via `openssl dgst` subprocess as fallback.

import std/[base64, osproc, strutils, times, random, os]
import e2ee/signs
import checksums/sha2
export signs

const spkiPrefixEd25519* = [
  byte 0x30, 0x2A, 0x30, 0x05, 0x06, 0x03,
  0x2B, 0x65, 0x70, 0x03, 0x21, 0x00
]

proc publicKeyToPemEd25519*(key: PublicKey): string =
  ## Converts an Ed25519 `PublicKey` (32 bytes) to PEM format.
  ##
  ## Wraps the raw key in SPKI (SubjectPublicKeyInfo) DER encoding
  ## per RFC 8410, then base64-encodes with PEM armor.
  let der = @spkiPrefixEd25519 & @key
  let b64 = encode(der)
  result = "-----BEGIN PUBLIC KEY-----\n"
  var i = 0
  while i < b64.len:
    let chunk = min(64, b64.len - i)
    result.add(b64[i ..< i + chunk])
    result.add("\n")
    i += chunk
  result.add("-----END PUBLIC KEY-----\n")

proc pemToPublicKeyEd25519*(pem: string): PublicKey =
  ## Parses an Ed25519 PEM public key back into a `PublicKey` (32 bytes).
  ##
  ## Strips PEM armor, base64-decodes, validates SPKI prefix, and extracts the raw key.
  ## Raises `ValueError` if the PEM is invalid.
  var clean = pem.multiReplace([
    ("-----BEGIN PUBLIC KEY-----", ""),
    ("-----END PUBLIC KEY-----", ""),
    ("\n", ""), ("\r", "")
  ]).strip()
  let der = decode(clean)
  if der.len != 44:
    raise newException(ValueError, "invalid Ed25519 public key PEM (wrong length)")
  for i in 0..11:
    if der[i] != spkiPrefixEd25519[i].char:
      raise newException(ValueError, "invalid Ed25519 public key PEM (bad prefix)")
  for i in 0..31:
    result[i] = uint8(der[i + 12])

proc generateEd25519Keypair*(): tuple[publicKey: PublicKey, secretKey: SecretKey] =
  ## Generates an Ed25519 keypair and returns (PublicKey, SecretKey).
  let kp = generateSigningKeyPair()
  (kp.publicKey, kp.secretKey)

proc generateEd25519KeypairPem*(): tuple[publicPem: string, secretHex: string] =
  ## Generates an Ed25519 keypair and returns (publicKeyPem, secretKeyHex).
  ##
  ## The public key is PEM-formatted; the secret key is a 128-char hex string.
  let kp = generateSigningKeyPair()
  (publicKeyToPemEd25519(kp.publicKey), secretKeyToHex(kp.secretKey))

proc signEd25519Raw*(data: string, secretKey: SecretKey): seq[byte] =
  ## Signs `data` with an Ed25519 `SecretKey` and returns raw 64-byte signature.
  let sig = sign(secretKey, data)
  @sig

proc verifyEd25519Raw*(data: string, signature: seq[byte], publicKey: PublicKey): bool =
  ## Verifies an Ed25519 signature (raw bytes) against `data` with a `PublicKey`.
  if signature.len != 64:
    return false
  var sig: Signature
  for i in 0..63:
    sig[i] = signature[i]
  verify(publicKey, data, sig)

proc signEd25519*(data: string, secretKeyHex: string): string =
  ## Signs `data` with an Ed25519 secret key (128-char hex), returns Base64 signature.
  ##
  ## This is the primary signing function for HTTP Signatures.
  let sk = secretKeyFromHex(secretKeyHex)
  let sig = sign(sk, data)
  encode(@sig)

proc verifyEd25519*(data: string, signatureBase64: string, publicKeyPem: string): bool =
  ## Verifies a Base64-encoded Ed25519 signature against `data` using a PEM public key.
  ##
  ## This is the primary verification function for HTTP Signatures.
  let pk = pemToPublicKeyEd25519(publicKeyPem)
  let sigStr = decode(signatureBase64)
  var sigBytes = newSeq[byte](sigStr.len)
  for i in 0..<sigStr.len:
    sigBytes[i] = byte(sigStr[i])
  verifyEd25519Raw(data, sigBytes, pk)

proc signRsaSha256*(data: string, pemPrivateKey: string): string =
  ## Signs `data` using RSA-SHA256 via an `openssl dgst` subprocess.
  ##
  ## Fallback for legacy ActivityPub implementations that only support RSA keys.
  ## Returns Base64-encoded signature.
  ## Raises `IOError` if OpenSSL fails.
  let tmpId = $getTime().toUnix & "_" & $rand(high(int))
  let tmpData = "/tmp/ap_sign_data_" & tmpId & ".bin"
  let tmpKey = "/tmp/ap_rsa_key_" & tmpId & ".pem"
  let tmpSig = "/tmp/ap_rsa_sig_" & tmpId & ".bin"
  try:
    writeFile(tmpData, data)
    writeFile(tmpKey, pemPrivateKey)
    let cmd = "openssl dgst -sha256 -sign \"" & tmpKey & "\" -out \"" & tmpSig & "\" \"" & tmpData & "\""
    let res = execCmdEx(cmd)
    if res.exitCode != 0:
      raise newException(IOError, "OpenSSL RSA-SHA256 signing failed: " & res.output)
    result = encode(readFile(tmpSig))
  finally:
    try: removeFile(tmpData) except: discard
    try: removeFile(tmpKey) except: discard
    try: removeFile(tmpSig) except: discard

proc verifyRsaSha256*(data: string, signatureBase64: string, pemPublicKey: string): bool =
  ## Verifies an RSA-SHA256 signature via an `openssl dgst` subprocess.
  ##
  ## Fallback for legacy ActivityPub implementations. Returns true if valid.
  let tmpId = $getTime().toUnix & "_" & $rand(high(int))
  let tmpData = "/tmp/ap_ver_data_" & tmpId & ".bin"
  let tmpKey = "/tmp/ap_ver_pubkey_" & tmpId & ".pem"
  let tmpSig = "/tmp/ap_ver_sig_" & tmpId & ".bin"
  try:
    writeFile(tmpData, data)
    writeFile(tmpKey, pemPublicKey)
    writeFile(tmpSig, decode(signatureBase64))
    let cmd = "openssl dgst -sha256 -verify \"" & tmpKey & "\" -signature \"" & tmpSig & "\" \"" & tmpData & "\""
    let res = execCmdEx(cmd)
    res.exitCode == 0
  finally:
    try: removeFile(tmpData) except: discard
    try: removeFile(tmpKey) except: discard
    try: removeFile(tmpSig) except: discard

proc sha256Digest*(body: string): string =
  ## Computes an HTTP `Digest` header value (SHA-256) for a request body.
  ##
  ## Returns in the format `SHA-256=<base64>`.
  var sha = initSha_256()
  sha.update(body)
  let d = sha.digest()
  var raw = newString(32)
  for i in 0..31:
    raw[i] = d[i]
  "SHA-256=" & encode(raw)
