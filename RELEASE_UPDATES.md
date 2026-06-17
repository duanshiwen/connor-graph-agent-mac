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

If `SUPublicEDKey` is still a placeholder, Connor does not start Sparkle and disables the update button. This keeps local development safe until real release signing is configured.

## Required Info.plist keys

The Xcode target uses generated Info.plist keys:

```text
SUFeedURL = https://duanshiwen.github.io/connor-updates/stable/appcast.xml
SUPublicEDKey = REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY
SUEnableAutomaticChecks = YES
```

Before publishing, replace `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY` with the value produced by Sparkle's `generate_keys` tool.

## Enable a real release channel

1. Generate Sparkle EdDSA keys.
2. Put the public key into the app target's generated Info.plist setting `INFOPLIST_KEY_SUPublicEDKey`.
3. Archive the app with Developer ID signing.
4. Notarize and staple the app/dmg.
5. Generate a Sparkle appcast with `generate_appcast`.
6. Publish the appcast to the static feed URL.
7. Publish the release artifact to GitHub Releases or another static artifact host.

Connor does not implement its own binary patcher or app installer.
