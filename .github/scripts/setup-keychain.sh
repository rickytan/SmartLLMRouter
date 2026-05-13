#!/usr/bin/env bash
# setup-keychain.sh
# Imports Apple Developer ID certificate into a temporary keychain for CI code signing.
# Required secrets:
#   BUILD_CERTIFICATE_BASE64 — .p12 certificate, base64 encoded
#   P12_PASSWORD            — password for the .p12 file
#   KEYCHAIN_PASSWORD       — password for the temporary keychain

set -euo pipefail

CERT_PATH="$RUNNER_TEMP/build_certificate.p12"
KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"

echo "▸ Creating temporary keychain..."
security create-keychain -p "${KEYCHAIN_PASSWORD}" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "$KEYCHAIN_PATH"

echo "▸ Importing certificate..."
echo "${BUILD_CERTIFICATE_BASE64}" | base64 --decode > "$CERT_PATH"
security import "$CERT_PATH" \
  -P "${P12_PASSWORD}" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"

echo "▸ Setting keychain as default..."
security list-keychain -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "${KEYCHAIN_PASSWORD}" "$KEYCHAIN_PATH"

echo "▸ Keychain setup complete."
