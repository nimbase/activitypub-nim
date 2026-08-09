## Example 02 — Crypto & HTTP Signatures
##
## Generate Ed25519 keypairs, sign and verify messages, compute SHA-256
## digests, and sign/verify HTTP requests per HTTP Signatures draft-cavage-12.
##
##   nim c -r examples/ex_02_crypto.nim

import ../src/activitypub

echo "== Keypair generation =="
let (publicPem, secretHex) = generateEd25519KeypairPem()
echo "public PEM:\n", publicPem
echo "secret hex (first 16 chars): ", secretHex[0 ..< 16], "..."

# Parse the public PEM back
let rawKey = pemToPublicKeyEd25519(publicPem)
echo "raw public key (32 bytes): ", rawKey.len
echo ""

echo "== Signing & verification =="
let message = "Hello, signed message!"
let signature = signEd25519(message, secretHex)
echo "signature (base64): ", signature
echo "verify: ", verifyEd25519(message, signature, publicPem)
echo "verify (tampered): ", verifyEd25519(message & "x", signature, publicPem)
echo ""

echo "== SHA-256 Digest =="
let digest = sha256Digest("{\"hello\":\"world\"}")
echo "digest header: ", digest
echo ""

echo "== HTTP Signatures =="
let body = """{"@context":"https://www.w3.org/ns/activitystreams","type":"Follow","actor":"https://example.com/users/alice","object":"https://remote.social/users/bob"}"""
let signed = signRequest(
  "POST", "/users/bob/inbox", "remote.social", body,
  "https://example.com/users/alice#main-key", secretHex
)
echo "date: ", signed.date
echo "digest: ", signed.digest
echo "signature: ", signed.signature
echo ""

# The remote server would reconstruct the actor JSON from the keyId
# and call verifyRequest. Build a minimal actor document with our public key.
let actorJson = %*{
  "id": "https://example.com/users/alice",
  "publicKey": {
    "id": "https://example.com/users/alice#main-key",
    "owner": "https://example.com/users/alice",
    "publicKeyPem": publicPem
  }
}
let headers = @[
  ("host", "remote.social"),
  ("date", signed.date),
  ("digest", signed.digest),
  ("signature", signed.signature)
]
echo "== Request verification =="
echo "verifyRequest: ", verifyRequest("POST", "/users/bob/inbox", body, headers, actorJson)
