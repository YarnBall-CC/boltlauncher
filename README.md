# BoltLauncher

A small macOS menu bar app launcher with global hotkeys.

- Add any application you choose
- Record a global hotkey for it
- Press the hotkey, or click the menu bar item, to toggle the app
  - If the app is frontmost, hide it
  - Otherwise, launch or activate it
- Optionally launch BoltLauncher at login
- Keep launch counts locally on your Mac
- Save work scenes with apps, websites, and files or folders under one hotkey

BoltLauncher's app shortcuts work offline; scene websites open in your default browser. BoltLauncher does not collect or transmit data. See the [privacy policy](PRIVACY.md).

## Mac App Store status

The project is configured for App Sandbox, security-scoped application bookmarks, a privacy manifest, a complete macOS AppIcon set, and App Store version metadata.

The remaining external steps require an Apple Developer Program team, signing certificates, an App Store Connect app record, and final real screenshots. See [Mac App Store Submission Guide](docs/APP_STORE_SUBMISSION.md).

## Current GitHub releases

Existing GitHub release builds are unsigned and not notarized. macOS Gatekeeper may block their first launch. These builds are separate from the planned Mac App Store distribution.

## Usage

1. Click the BoltLauncher icon in the menu bar.
2. Open Settings.
3. Choose **Add App...** and select an application.
4. Record a global hotkey using Command, Option, or Control. Function keys may be used alone.
5. Optionally enable **Launch at login**.

To make a work scene, add its applications in Settings, choose **Add Scene**, select the applications, then add any websites or files and record a hotkey. Press the scene hotkey or choose its menu bar item to open it. Press it again to hide the selected applications. Files and websites open once per BoltLauncher session to avoid duplicate windows and tabs; hiding a scene does not close them.

Existing configurations created before App Sandbox was enabled show **Grant Access...** once for each saved application.

## Build from source

Requirements:

- macOS 13 or later
- Xcode 26 or later for current App Store preparation

Build without signing:

```bash
xcodebuild -project MacAppLauncher.xcodeproj \
  -scheme MacAppLauncher \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Validate an unsigned App Store archive:

```bash
./scripts/validate_app_store.sh
```

## Data storage

The sandboxed app stores its SQLite database in its macOS container:

`~/Library/Containers/io.github.chengzi0103.boltlauncher/Data/Library/Application Support/BoltLauncher/launcher.sqlite`

Older builds distributed outside the Mac App Store used:

`~/Library/Application Support/BoltLauncher/launcher.sqlite`

## License

MIT
