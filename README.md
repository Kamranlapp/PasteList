#Paster

Paster is a local-only macOS clipboard history app. It does not use network
sync, analytics, iCloud, or an App Sandbox.
Paster is a lightweight, privacy-focused clipboard manager for macOS. It runs from the menu bar, keeps clipboard history entirely on your Mac, and provides fast access through a customizable global shortcut.

## Current features
## Features

- Menu bar clipboard history for text, URLs, RTF, images, files, and folders.
- Search, pinned clips, image previews, and local retention cleanup.
- Global shortcut (default `Shift-Command-V`) and optional automatic paste.
- Bulk paste for text, URLs, and RTF using built-in or custom separators.
- Settings, Launch at Login, restart, and quit actions from the status item.
- Supports text, URLs, rich text, images, files, and folders
- Searchable history with pinned items and image previews
- Bulk paste with built-in or custom separators
- Optional automatic paste and Launch at Login
- Automatic cleanup of older, unpinned entries
- No accounts, cloud sync, analytics, or network access
- Ignores clipboard content marked as concealed or transient

## Launch at Login
## Requirements

Paster uses `SMAppService.mainApp` on macOS 13 and later. Move the built app to
a stable location such as `/Applications/Paster.app` before enabling Launch at
Login. Registration from Xcode's DerivedData folder may be unavailable or may
stop working when the build location changes.
- macOS 13.0 or later
- Xcode with Swift 6 support

## Build

## Accessibility access during development
1. Clone the repository.
2. Open `Paster.xcodeproj` in Xcode.
3. Select the **Paster** scheme and run the project.

The shared Xcode scheme re-signs Debug builds with the first valid Apple
Development identity in the login keychain. This gives the build a stable code
requirement, so macOS keeps Accessibility access after recompilation. If more
than one valid identity exists, set `Paster_SIGNING_IDENTITY` in the scheme to
the desired certificate name or SHA-1 hash.
Dependencies are resolved automatically through Swift Package Manager. Grant Accessibility access when prompted to enable automatic pasting. For Launch at Login, move the built app to `/Applications` first.

After switching from an older ad-hoc build, reset its stale permission once:
## Testing

```sh
tccutil reset Accessibility com.kam.Paster
xcodebuild test -project Paster.xcodeproj -scheme Paster -destination 'platform=macOS'
```

Then run Paster from Xcode and grant it access in System Settings. Subsequent
Debug builds signed with the same identity keep that permission.
## Privacy

All clipboard data is stored locally. Paster does not use iCloud, analytics, or any external service.
