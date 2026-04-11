#!/usr/bin/env bash

set -euo pipefail

KEYCHAIN_PATH="${RUNNER_TEMP}/build.keychain-db"
KEYCHAIN_PASSWORD="${BUILD_KEYCHAIN_PASSWORD:-github-actions-keychain-password}"
PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
KEYCHAIN_READY=0

mkdir -p "$PROFILES_DIR"

decode_base64() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

ensure_keychain() {
  if [[ "$KEYCHAIN_READY" -eq 1 ]]; then
    return
  fi

  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security default-keychain -d user -s "$KEYCHAIN_PATH"
  security list-keychains -d user -s "$KEYCHAIN_PATH"

  KEYCHAIN_READY=1
}

import_certificate() {
  local label="$1"
  local base64_value="$2"
  local password="$3"

  if [[ -z "$base64_value" ]]; then
    return
  fi

  ensure_keychain

  local cert_path="${RUNNER_TEMP}/${label}.p12"
  printf '%s' "$base64_value" | decode_base64 > "$cert_path"
  security import "$cert_path" -P "$password" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
}

install_profile() {
  local label="$1"
  local base64_value="$2"
  local export_prefix="$3"

  if [[ -z "$base64_value" ]]; then
    return
  fi

  local profile_path="${RUNNER_TEMP}/${label}.mobileprovision"
  local plist_path="${RUNNER_TEMP}/${label}.plist"
  local uuid
  local name

  printf '%s' "$base64_value" | decode_base64 > "$profile_path"
  security cms -D -i "$profile_path" > "$plist_path"

  uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$plist_path")"
  name="$(/usr/libexec/PlistBuddy -c 'Print Name' "$plist_path")"

  cp "$profile_path" "$PROFILES_DIR/${uuid}.mobileprovision"

  {
    echo "${export_prefix}_PROFILE_UUID=${uuid}"
    echo "${export_prefix}_PROFILE_NAME=${name}"
  } >> "$GITHUB_ENV"
}

import_certificate "ios-certificate" "${IOS_CERTIFICATE_P12_BASE64:-}" "${IOS_CERTIFICATE_PASSWORD:-}"
import_certificate "macos-certificate" "${MACOS_CERTIFICATE_P12_BASE64:-}" "${MACOS_CERTIFICATE_PASSWORD:-}"

if [[ "$KEYCHAIN_READY" -eq 1 ]]; then
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  echo "KEYCHAIN_PATH=${KEYCHAIN_PATH}" >> "$GITHUB_ENV"
fi

install_profile "ios-profile" "${IOS_PROVISIONING_PROFILE_BASE64:-}" "IOS"
install_profile "macos-profile" "${MACOS_PROVISIONING_PROFILE_BASE64:-}" "MACOS"
