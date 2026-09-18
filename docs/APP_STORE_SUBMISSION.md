# Mac App Store Submission Guide

The repository is configured for a sandboxed Mac App Store build. Uploading still requires access to the Apple Developer Program and App Store Connect.

## External prerequisites

1. Accept the latest agreements in Apple Developer and App Store Connect.
2. Register the explicit bundle ID `io.github.chengzi0103.boltlauncher` in the correct Apple Developer team.
3. Create a macOS app record in App Store Connect using the same bundle ID.
4. In Xcode, select the `MacAppLauncher` target and choose the correct Team under Signing & Capabilities.
5. Confirm that the app name `BoltLauncher` is available in App Store Connect.

Do not commit a personal Team ID or signing certificate to this public repository.

## Local validation

Run:

```bash
./scripts/validate_app_store.sh
```

The script validates the property lists and produces an unsigned Release archive. A real upload must use the Apple Distribution signing identity and provisioning profile managed by Xcode.

## Versioning

- Marketing version: `1.1.0`
- Build number: `4`

Increase `CURRENT_PROJECT_VERSION` for every uploaded build. Mac build numbers must always increase, even when the marketing version changes.

## Archive and upload

1. Open `MacAppLauncher.xcodeproj` in the current Xcode release.
2. Select the `MacAppLauncher` scheme and `Any Mac` destination.
3. Choose Product > Archive.
4. In Organizer, select the archive and choose Distribute App > App Store Connect > Upload.
5. Resolve every validation warning before selecting the build in App Store Connect.

## App Store Connect declarations

- Primary category: Utilities
- Data collection: No, this app does not collect data
- Tracking: No
- Export compliance: The app does not use non-exempt encryption
- Privacy policy URL: `https://github.com/YarnBall-CC/boltlauncher/blob/main/PRIVACY.md`
- Support URL: `https://github.com/YarnBall-CC/boltlauncher/issues`

Review the answers in App Store Connect rather than copying them blindly if the app later adds networking, analytics, crash reporting, advertising, accounts, or third-party SDKs.

## Review notes

Suggested review notes:

> BoltLauncher is a menu bar utility and intentionally has no Dock icon. Open the menu bar bolt icon, choose Settings, add an application, and assign a global hotkey. To try Work Scenes, add a scene, select one or more apps, and optionally add a website or file. The scene hotkey opens them together; pressing it again hides the scene's apps. The app uses App Sandbox and requests access only to applications and files explicitly selected by the user. Launch at login is optional and uses SMAppService. The app has no account, analytics, or in-app purchases. Scene websites open in the user's default browser.

## Required product assets

- App icon: included in `Assets.xcassets/AppIcon.appiconset`
- Screenshots: provide 1–10 real screenshots at an accepted 16:10 Mac size, preferably `2880 x 1800`, with no alpha channel
- Description and keywords: draft in `docs/app-store/metadata-en-US.md`

The existing `docs/images/screenshot-*.png` files are concept placeholders at `2800 x 1800`; do not upload them to App Store Connect. Capture the final sandboxed UI after signing is configured.
