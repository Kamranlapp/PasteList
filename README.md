# Paster

Paster is a lightweight, privacy-focused clipboard manager for macOS. It runs
from the menu bar, keeps clipboard history entirely on your Mac, and provides
fast access through a customizable global shortcut.

## Features

- Clipboard history for text, URLs, RTF, images, files, and folders.
- Search, pinned clips, image previews, and local retention cleanup.
- Global shortcut (default `Shift-Command-V`) and optional automatic paste.
- Number-key quick paste for the 10 most recent visible clips (`1`–`9`, then `0`).
- Bulk paste for text, URLs, and RTF using built-in or custom separators.
- Settings, Launch at Login, restart, and quit actions from the status item.
- No accounts, cloud sync, analytics, or network access.
- Clipboard content marked as concealed or transient is ignored.

## Requirements

- macOS 13.0 or later.
- Xcode with Swift 6 support.

## Build

1. Clone the repository.
2. Open `Paster.xcodeproj` in Xcode.
3. Select the **Paster** scheme and run the project.

Dependencies are resolved automatically through Swift Package Manager.

## Accessibility access during development

The shared Xcode scheme re-signs Debug builds with the first valid Apple
Development identity in the login keychain. This gives the build a stable code
requirement, so macOS keeps Accessibility access after recompilation. If more
than one valid identity exists, set `PASTER_SIGNING_IDENTITY` to the desired
certificate name or SHA-1 hash.

After switching from an older ad-hoc build, reset its stale permission once:

```sh
tccutil reset Accessibility com.kam.paster
```

Then run Paster from Xcode and grant it access in System Settings.

## Launch at Login

Paster uses `SMAppService.mainApp` on macOS 13 and later. Move the built app to
a stable location such as `/Applications/Paster.app` before enabling Launch at
Login. Registration from Xcode's DerivedData folder may be unavailable or stop
working when the build location changes.

## Testing

```sh
xcodebuild test -project Paster.xcodeproj -scheme Paster -destination 'platform=macOS'
```

## Distribution

After building the arm64 Release configuration, create the DMG with the app,
volume, and installer-file icons attached:

```sh
Scripts/package-dmg.sh /path/to/Release/Paster.app
```

## Privacy

All clipboard data is stored locally. Paster does not use iCloud, analytics,
or any external service.
