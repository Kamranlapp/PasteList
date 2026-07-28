# KPaste

KPaste is a local-only macOS clipboard history app. It does not use network
sync, analytics, iCloud, or an App Sandbox.

## Current features

- Menu bar clipboard history for text, URLs, RTF, images, files, and folders.
- Search, pinned clips, image previews, and local retention cleanup.
- Global shortcut (default `Shift-Command-V`) and optional automatic paste.
- Bulk paste for text, URLs, and RTF using built-in or custom separators.
- Settings, Launch at Login, restart, and quit actions from the status item.

## Launch at Login

KPaste uses `SMAppService.mainApp` on macOS 13 and later. Move the built app to
a stable location such as `/Applications/KPaste.app` before enabling Launch at
Login. Registration from Xcode's DerivedData folder may be unavailable or may
stop working when the build location changes.
