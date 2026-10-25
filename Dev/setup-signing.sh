#!/bin/bash
#
# Creates the local code-signing identity that keeps the Keychain quiet.
#
# Why this exists
# ---------------
# MediaTracker stores API keys and the Supabase sync key in the login Keychain. A keychain item
# remembers the designated requirement of the app that created it. Ad-hoc signing (`codesign
# --sign -`) builds that requirement out of the binary's cdhash, so every rebuild looks like a
# different app and macOS asks for approval again. A certificate — any certificate, including a
# self-signed one — changes the requirement to `identifier + certificate`, which is stable across
# rebuilds. No Apple Developer Program membership is involved: the certificate is generated here,
# added to your login keychain, and trusted for code signing in the user domain. `codesign` accepts
# it for apps that only run on this Mac.
#
# The identity carries no access-control policy, so it never asks for a password or Touch ID when
# the app reads its own items. It is a signing identity, not an authentication prompt.
#
# Usage
# -----
#   ./Dev/setup-signing.sh            # create it (no-op if it already exists)
#
# `install.sh` then signs with it automatically. Re-running is safe.
#
set -euo pipefail

IDENTITY="${1:-MediaTracker Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✅ Signing identity \"$IDENTITY\" already exists and is valid."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "🔑 Generating a self-signed code-signing certificate named \"$IDENTITY\"…"
cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

# macOS's PKCS#12 importer rejects OpenSSL 3's default (AES-256 + SHA-256 MAC) bundles. Try the
# legacy form first and fall back to explicit SHA-1 parameters for LibreSSL, which is what ships
# in /usr/bin/openssl.
P12_PASS="$(uuidgen)"
if ! openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/id.p12" -passout "pass:$P12_PASS" 2>/dev/null; then
    openssl pkcs12 -export -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/id.p12" -passout "pass:$P12_PASS" 2>/dev/null
fi

echo "📥 Importing into the login keychain…"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Trust for code signing in the *user* domain only — no sudo, nothing machine-wide.
echo "🔏 Trusting it for code signing (user domain)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✅ Created \"$IDENTITY\"."
    echo "   ./install.sh will now sign with it, and the app will read its Keychain items without asking."
    echo
    echo "   To sign GitHub release builds with it too, export the identity from Keychain Access"
    echo "   (My Certificates → right-click → Export → .p12) and add it as the repository secrets"
    echo "   CERT_P12_BASE64 and CERT_PASSWORD."
else
    cat <<EOF
⚠️  The certificate was imported but is not yet valid for code signing.

Set it up by hand instead:

  1. Keychain Access → Keychain Access menu → Certificate Assistant → Create a Certificate…
  2. Name:            $IDENTITY
     Identity Type:   Self Signed Root
     Certificate Type: Code Signing
  3. Create, then open the certificate, expand "Trust", and set "Code Signing" to "Always Trust".

Verify with: security find-identity -v -p codesigning | grep "$IDENTITY"
EOF
    exit 1
fi
