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

## Accessibility access during development

The shared Xcode scheme re-signs Debug builds with the first valid Apple
Development identity in the login keychain. This gives the build a stable code
requirement, so macOS keeps Accessibility access after recompilation. If more
than one valid identity exists, set `KPASTE_SIGNING_IDENTITY` in the scheme to
the desired certificate name or SHA-1 hash.

After switching from an older ad-hoc build, reset its stale permission once:

```sh
tccutil reset Accessibility com.kam.kpaste
```

Then run KPaste from Xcode and grant it access in System Settings. Subsequent
Debug builds signed with the same identity keep that permission.
