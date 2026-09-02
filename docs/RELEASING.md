# Releasing Thermal Cam

Releases are built for Apple silicon, signed with a Developer ID Application
certificate, notarized by Apple, stapled, and published as a ZIP with a SHA-256
checksum. The ZIP is created again after stapling so the downloadable app
contains its notarization ticket.

## One-time GitHub setup

Add these Actions secrets to the repository:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `APPSTORE_CONNECT_API_KEY_ID`
- `APPSTORE_CONNECT_API_ISSUER_ID`
- `APPSTORE_CONNECT_API_PRIVATE_KEY`

The certificate must be a Developer ID Application identity. The API key needs
permission to submit software to Apple's notary service.

## Publish a release

Update the version as needed, then push a semantic-version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow builds, signs, notarizes, staples, verifies, packages, and
publishes the app. Normal pushes and pull requests only run tests; they do not
consume signing credentials or submit anything to Apple.

## Local notarized build

Store notarization credentials in the login keychain once:

```sh
xcrun notarytool store-credentials "thermal-cam-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Then run:

```sh
NOTARY_KEYCHAIN_PROFILE=thermal-cam-notary ./scripts/release.sh 0.1.0
```

The final ZIP and checksum are written to `dist/`.
