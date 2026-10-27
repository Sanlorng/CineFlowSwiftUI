#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Local ad-hoc signing still embeds the sandbox entitlements. Disabling signing
# would launch against ~/Library instead of the existing application container.
xcodebuild -project CineFlow.xcodeproj -scheme CineFlow \
  -configuration Debug -destination 'platform=macOS' \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
