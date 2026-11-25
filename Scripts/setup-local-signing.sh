#!/usr/bin/env bash
# Copyright (c) 2026 Dhruv Chawla · SPDX-License-Identifier: MIT
#
# One-time setup: creates a local code-signing identity, "Friday Local Signing",
# in its own keychain (~/Library/Keychains/friday-signing.keychain-db).
#
# Why: ad-hoc signed builds get a new identity on every rebuild, so macOS
# forgets Screen Recording (and other) permissions after each build, even
# though System Settings still shows them as on. Signing every build with the
# same certificate keeps permissions across rebuilds.
#
# The certificate is self-signed, can only sign code, stays on this Mac, and
# is not trusted for anything else. Run it yourself; it never asks for your
# login password. Safe to run again: it does nothing if the identity exists.
set -euo pipefail

NAME="Friday Local Signing"
KC="$HOME/Library/Keychains/friday-signing.keychain-db"
PASSFILE="$HOME/.config/friday/signing-keychain-password"

if [ -f "$KC" ] && security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  echo "✔ \"$NAME\" already exists in $KC"
  exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<'CNF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Friday Local Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
P12PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout "pass:$P12PASS" -out "$TMP/id.p12" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -passout "pass:$P12PASS" -out "$TMP/id.p12"

mkdir -p "$(dirname "$PASSFILE")"
( umask 077; openssl rand -hex 24 > "$PASSFILE" )
KCPASS=$(cat "$PASSFILE")
[ -f "$KC" ] && security delete-keychain "$KC"
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock timeout
security unlock-keychain -p "$KCPASS" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null

# Add to the search list (keeping existing keychains) so codesign finds it.
existing=$(security list-keychains -d user | tr -d '"' | xargs)
case " $existing " in *" $KC "*) ;; *) security list-keychains -d user -s $existing "$KC" ;; esac

echo "✔ Created \"$NAME\" in $KC"
echo "  Next: make install   (builds, signs with it, installs /Applications/Friday.app)"
