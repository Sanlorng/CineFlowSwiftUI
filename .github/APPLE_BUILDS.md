# GitHub Actions Apple Builds

This repository now includes a dedicated GitHub Actions workflow at `.github/workflows/apple-artifacts.yml` for packaging Apple artifacts.

## Triggers

- Manual trigger: `Actions -> Build Apple Artifacts -> Run workflow`
- Tag trigger: push a tag matching `v*`

## Artifacts

- `CineFlow-macOS-app.zip`
- `CineFlow-macOS.dmg`
- `CineFlow-iOS.ipa`

## Required secrets for iOS IPA

- `APPLE_TEAM_ID`: Apple Developer team identifier.
- `IOS_CERTIFICATE_P12_BASE64`: base64-encoded `Apple Distribution` certificate.
- `IOS_CERTIFICATE_PASSWORD`: password for that `.p12`.
- `IOS_PROVISIONING_PROFILE_BASE64`: base64-encoded iOS provisioning profile for `com.sanlorng.CineFlow`.

## Optional secrets for signed macOS output

- `APPLE_TEAM_ID`: still required if you want the macOS archive to be signed.
- `MACOS_CERTIFICATE_P12_BASE64`: base64-encoded `Developer ID Application` certificate.
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`.
- `MACOS_PROVISIONING_PROFILE_BASE64`: macOS provisioning profile, only if your signing setup requires one.
- `BUILD_KEYCHAIN_PASSWORD`: custom password for the temporary CI keychain. If omitted, the workflow uses an internal default.

If the macOS signing secrets are missing, the workflow still produces an unsigned `.app` zip and `.dmg`.

## Export method

The manual workflow trigger exposes an `ios_export_method` input. Supported values:

- `ad-hoc`
- `app-store`
- `development`
- `enterprise`

Tag-triggered runs default to `ad-hoc`.

## Encoding helper

Use the following commands locally before adding secrets to GitHub:

```bash
base64 -i ios-distribution.p12 | pbcopy
base64 -i CineFlow.mobileprovision | pbcopy
base64 -i developer-id-application.p12 | pbcopy
```
