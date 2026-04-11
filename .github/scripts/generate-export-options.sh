#!/usr/bin/env bash

set -euo pipefail

OUTPUT_PATH="${1:?Output plist path is required.}"
IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-ad-hoc}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:?APPLE_TEAM_ID is required.}"
PRODUCT_BUNDLE_IDENTIFIER="${PRODUCT_BUNDLE_IDENTIFIER:?PRODUCT_BUNDLE_IDENTIFIER is required.}"
IOS_PROFILE_NAME="${IOS_PROFILE_NAME:?IOS_PROFILE_NAME is required.}"

cat > "$OUTPUT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>${IOS_EXPORT_METHOD}</string>
  <key>signingCertificate</key>
  <string>Apple Distribution</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${PRODUCT_BUNDLE_IDENTIFIER}</key>
    <string>${IOS_PROFILE_NAME}</string>
  </dict>
</dict>
</plist>
EOF
