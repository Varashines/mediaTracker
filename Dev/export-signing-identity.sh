#!/bin/bash
#
# Makes CI sign with the same certificate this Mac signs with.
#
# Why this exists
# ---------------
# A Keychain item's ACL records the *certificate leaf hash* of the app that created it, not
# the certificate's display name. Regenerating the identity — a new Mac, a deleted keychain
# item, a re-run of setup-signing.sh — therefore produces a different app under the same
# name, and every existing install starts asking for approval. The same happens in reverse
# if CI keeps signing with the old .p12.
#
# This script removes the manual copy step: it exports the local identity, uploads it as
# CERT_P12_BASE64/CERT_PASSWORD, and records the certificate hash as SIGNING_CERT_SHA1 so
# both workflows can fail on drift instead of shipping a DMG that no longer matches.
#
# Usage
# -----
#   ./Dev/export-signing-identity.sh          # confirm, then upload
#   ./Dev/export-signing-identity.sh --yes    # no prompt (for scripting)
#
# Requires: gh (authenticated), an unlocked login keychain, and the identity created by
# Dev/setup-signing.sh.
#
set -euo pipefail

IDENTITY="${SIGNING_IDENTITY:-MediaTracker Local Signing}"
KEYCHAIN="${KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
ASSUME_YES=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y) ASSUME_YES=true ;;
        --help|-h)
            echo "Usage: $0 [--yes]"
            echo "  --yes   skip the confirmation prompt"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (try --help)"
            exit 1
            ;;
    esac
done

command -v gh >/dev/null 2>&1 || { echo "❌ gh is required: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ gh is not logged in: gh auth login"; exit 1; }

if [ ! -f "$KEYCHAIN" ]; then
    echo "❌ Keychain not found at $KEYCHAIN"
    exit 1
fi

SHA1=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -v name="\"$IDENTITY\"" 'index($0, name) { print $2; exit }')
if [ -z "${SHA1:-}" ]; then
    echo "❌ No code-signing identity named \"$IDENTITY\"."
    echo "   Run ./Dev/setup-signing.sh once, then re-run this."
    exit 1
fi

REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

echo "Identity:   $IDENTITY"
echo "SHA-1:      $SHA1"
echo "Repository: $REPO"
echo
echo "This overwrites CERT_P12_BASE64 and CERT_PASSWORD, and sets the SIGNING_CERT_SHA1 variable."
if [ "$ASSUME_YES" != true ]; then
    read -r -p "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSWORD="$(uuidgen)"
P12="$WORK/identity.p12"

echo "🔐 Exporting the identity (the Keychain may ask for permission once)…"
if ! security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$PASSWORD" -o "$P12" 2>/dev/null; then
    echo "❌ Export failed."
    echo "   Unlock the login keychain (Keychain Access → login → Unlock) and retry."
    exit 1
fi
if [ ! -s "$P12" ]; then
    echo "❌ Export produced an empty file."
    exit 1
fi

IDENTITY_COUNT=$(security find-identity -v -p codesigning 2>/dev/null | grep -c '^ *[0-9])' || true)
if [ "${IDENTITY_COUNT:-0}" -gt 1 ]; then
    echo "ℹ️  The export contains $IDENTITY_COUNT identities. CI signs by name, so the extra"
    echo "    ones are inert — but they are in the secret. Remove them from the keychain first"
    echo "    if that matters to you."
fi

echo "⬆️  Uploading secrets and the expected certificate hash…"
gh secret set CERT_P12_BASE64 --repo "$REPO" --body "$(base64 -i "$P12" | tr -d '\n')"
gh secret set CERT_PASSWORD --repo "$REPO" --body "$PASSWORD"
gh variable set SIGNING_CERT_SHA1 --repo "$REPO" --body "$SHA1"

echo
echo "✅ CI now signs with this Mac's certificate ($SHA1)."
echo "   Both build workflows verify the imported certificate against SIGNING_CERT_SHA1"
echo "   and fail if a regenerated identity ever drifts from it."
echo "   Verify with: gh variable get SIGNING_CERT_SHA1 --repo $REPO"
