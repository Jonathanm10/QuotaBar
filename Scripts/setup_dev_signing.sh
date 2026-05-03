#!/usr/bin/env bash
# Set up stable development code signing to reduce repeated Keychain prompts.
set -euo pipefail

CERT_NAME="QuotaBar Development"

echo "Setting up stable development code signing for QuotaBar."
echo "This creates a self-signed code-signing certificate that stays stable across rebuilds."
echo

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "Certificate '$CERT_NAME' already exists."
  echo
  echo "Use it with:"
  echo "  export APP_IDENTITY='$CERT_NAME'"
  exit 0
fi

TEMP_CONFIG="$(mktemp)"
trap 'rm -f "$TEMP_CONFIG" /tmp/quotabar-dev.key /tmp/quotabar-dev.crt /tmp/quotabar-dev.p12' EXIT

cat > "$TEMP_CONFIG" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = $CERT_NAME
O = QuotaBar Development
C = US

[ v3_req ]
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
  -nodes -keyout /tmp/quotabar-dev.key -out /tmp/quotabar-dev.crt \
  -config "$TEMP_CONFIG" 2>/dev/null

openssl pkcs12 -export -out /tmp/quotabar-dev.p12 \
  -inkey /tmp/quotabar-dev.key -in /tmp/quotabar-dev.crt \
  -passout pass: 2>/dev/null

security import /tmp/quotabar-dev.p12 \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

echo
echo "Certificate '$CERT_NAME' created."
echo
echo "Trust it for code signing:"
echo "1. Open Keychain Access.app."
echo "2. Find '$CERT_NAME' in the login keychain."
echo "3. Open it, expand Trust, and set Code Signing to Always Trust."
echo "4. Close the window and enter your password."
echo
echo "Then add this to your shell profile and rebuild:"
echo "  export APP_IDENTITY='$CERT_NAME'"
