# BoltLauncher

**BoltLauncher is a native macOS menu bar app that opens, switches, or hides apps with global keyboard shortcuts.** Work Scenes launch a group of apps plus optional websites, files, and folders with one hotkey.

[Download BoltLauncher on the Mac App Store](https://apps.apple.com/us/app/boltlauncher/id6792410406?mt=12) · [Privacy policy](PRIVACY.md) · [Support](https://github.com/YarnBall-CC/boltlauncher/issues)

Requires macOS 13 or later. BoltLauncher is a one-time purchase with no account, analytics, advertising, or subscription.

![BoltLauncher settings showing global hotkeys for Mac apps](docs/images/screenshot-settings.png)

## What BoltLauncher does

- Assign a memorable global hotkey to any Mac app you choose.
- Press the hotkey from anywhere to launch or activate the app.
- Press the same hotkey again when the app is frontmost to hide it.
- Create Work Scenes that open multiple apps, websites, files, and folders together.
- Keep BoltLauncher ready in the menu bar and optionally start it at login.
- Store shortcuts, permissions, scenes, and launch counts locally on your Mac.

## How to launch a Mac app with a keyboard shortcut

1. Open BoltLauncher from the menu bar and choose **Settings**.
2. Select **Add App**, then choose a macOS application.
3. Record a shortcut using Command, Option, or Control. Function keys can be used alone.
4. Press the shortcut from any app to open, switch to, or hide the selected application.

Configurations created before App Sandbox support may show **Grant Access** once for each saved application.

## Work Scenes

A Work Scene groups the tools for a repeated task under one keyboard shortcut. A coding scene can open a terminal, editor, browser page, project file, and folder together; a meeting scene can open the communication and note-taking apps you use.

Create a scene in Settings, select its applications, add any websites, files, or folders, and record a hotkey. Press the scene hotkey or choose the scene in the menu bar to open it. Press the hotkey again to hide the selected apps. Files and websites open once per BoltLauncher session to avoid duplicate windows and tabs; hiding a scene does not close them.

## BoltLauncher FAQ

### How is BoltLauncher different from Spotlight?

Spotlight searches for an app after you open its search field and type. BoltLauncher gives a specific app or Work Scene a reusable global hotkey, so repeated tools open directly without another search.

### Does BoltLauncher work offline?

App shortcuts, Work Scene configuration, and local launch counts work offline. A Work Scene needs a network connection only when it opens a website in your default browser.

### What data does BoltLauncher collect?

BoltLauncher does not collect or transmit personal data. It has no account system, analytics, advertising, or third-party tracking SDKs. Selected apps, permissions, shortcuts, scenes, and launch counts stay on your Mac.

### Where can I get BoltLauncher?

The signed release is available on the [Mac App Store](https://apps.apple.com/us/app/boltlauncher/id6792410406?mt=12). Older GitHub release builds are unsigned and not notarized, so macOS Gatekeeper may block their first launch.

## Build from source

Requirements:

- macOS 13 or later
- Xcode 26 or later

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
