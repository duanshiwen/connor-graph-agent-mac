# Release & Update Surface

Connor uses a no-backend macOS update path:

- Sparkle 2 owns app binary update checking, download, signature verification, installation, and relaunch.
- Connor owns the settings/menu entry, current version display, release policy language, and diagnostics.
- GitHub Pages or an equivalent static host serves the Sparkle appcast.
- GitHub Releases or an equivalent static artifact host serves signed/notarized release archives.

## Runtime behavior

The app reads the current version from the app bundle:

- `CFBundleShortVersionString`
- `CFBundleVersion`
- `CFBundleIdentifier`

Users can trigger update checks from:

- App menu: `Check for Updates…`
- Settings → 应用 → 关于与更新 → `检查更新`

When the Sparkle feed URL and public EdDSA key are present, Connor starts `SPUStandardUpdaterController`. Sparkle then owns the executable update flow: appcast lookup, update presentation, download, EdDSA verification, installation, and relaunch.

## Configured Info.plist keys

The Xcode target uses generated Info.plist keys:

```text
SUFeedURL = https://duanshiwen.github.io/connor-updates/stable/appcast.xml
SUPublicEDKey = sWf8ogcYVvHBiWsjfWCodO263YAXcCD4EmzbNvMiMHc=
SUEnableAutomaticChecks = YES
```

The matching private key was generated with Sparkle `generate_keys --account com.shiwen.connor-graph-agent-mac` and is stored in the local macOS Keychain. Do not commit or print the private key.

## Local release command

```bash
scripts/release-macos-sparkle.sh
```

Useful environment variables:

```bash
SCHEME=ConnorGraphAgentMacApp
SPARKLE_ACCOUNT=com.shiwen.connor-graph-agent-mac
DOWNLOAD_URL_PREFIX=https://github.com/duanshiwen/connor-graph-agent-mac/releases/download/v1.0.0
NOTARY_PROFILE=connor-notary-profile
```

Alternatively provide Apple notary credentials directly:

```bash
APPLE_ID=...
APPLE_TEAM_ID=...
APPLE_APP_SPECIFIC_PASSWORD=...
```

## GitHub Actions release

Workflow:

```text
.github/workflows/release-macos-sparkle.yml
```

Required GitHub Secrets:

```text
SPARKLE_PRIVATE_KEY
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64
DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
KEYCHAIN_PASSWORD
```

`SPARKLE_PRIVATE_KEY` should be the exported Sparkle private key content from:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.shiwen.connor-graph-agent-mac \
  -x /tmp/connor-sparkle-private-key.txt
```

Then copy the file content into the secret and delete the exported file immediately.

## Release sequence

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
2. Push a tag, for example `v1.0.0`.
3. GitHub Actions builds the app target using the shared `ConnorGraphAgentMacApp` scheme.
4. The workflow imports the Developer ID Application certificate.
5. The release script archives, exports, zips, notarizes, staples, and re-zips the app.
6. Sparkle `generate_appcast` signs the appcast using `SPARKLE_PRIVATE_KEY`.
7. The zip and appcast are uploaded to the GitHub Release.
8. Publish or sync `appcast.xml` to the stable feed URL:

```text
https://duanshiwen.github.io/connor-updates/stable/appcast.xml
```

Connor does not implement its own binary patcher, remote update backend, or app installer.
