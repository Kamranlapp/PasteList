# PasteList

PasteList is a lightweight, privacy-focused clipboard manager for macOS. It runs
from the menu bar, keeps clipboard history entirely on your Mac, and provides
fast access through a customizable global shortcut.

## Features

- Clipboard history for text, URLs, RTF, images, files, and folders.
- Search, pinned clips, image previews, and local retention cleanup.
- Global shortcut (default `Shift-Command-V`) and optional Assistive Paste for a mouse-only workflow.
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
2. Open `PasteList.xcodeproj` in Xcode.
3. Select the **PasteList** scheme and run the project.

Dependencies are resolved automatically through Swift Package Manager.

## Accessibility access during development

Debug builds run as `PasteDebug` with the separate bundle identifier
`com.kam.pastelist.debug`. This keeps their Accessibility permission, app data,
and reset commands isolated from an installed App Store or TestFlight build.

For Accessibility testing, build and launch the single stable Debug bundle:

```sh
Scripts/run-stable-debug.sh
```

The script installs the current build at `/Applications/PasteDebug.app`, keeps
its Apple Development identity stable, and unregisters temporary DerivedData
copies from LaunchServices without deleting build artifacts or resetting TCC.
Grant this canonical app access on the first onboarding page. The app follows
The app requests PostEvent access and leaves opening the Accessibility pane to
the system permission dialog's explicit button. It polls the Accessibility trust state shown by that pane once per second
while the permission UI is visible.

The Debug status menu has two separate reset actions:

- **Reset Accessibility** removes only the Debug app's Accessibility decision,
  resets onboarding/tips, and relaunches the same canonical app. Clipboard
  history and other settings are preserved.
- **Reset to First Launch** additionally removes Debug preferences, clipboard
  history, blobs, and Launch at Login registration.

Because macOS retains authorization decisions even after an app is uninstalled,
both actions open a short-lived, visible Terminal command that resets the Debug
app's `Accessibility` and `PostEvent` TCC records with `tccutil`. Local data is
changed only after both commands succeed and relaunch the canonical app. If
macOS rejects either reset, the app is reopened without deleting local data.

To prepare the Mac for a complete installation-from-scratch recording, reset
both the Debug and App Store identities with:

```sh
Scripts/reset-clean-install.sh
```

The script stops both app variants, resets every TCC record associated with
their bundle identifiers, unregisters installed copies, and moves their
preferences, clipboard database, blobs, caches, and installed bundles into one
timestamped folder in the Trash. It deliberately preserves the repository,
Xcode Archives, and DerivedData. Preview the exact actions without changing
anything with `Scripts/reset-clean-install.sh --dry-run`.

The same reset is available as two Finder-launchable files in `Scripts`:

- **Reset PasteList - Full.command** removes the installed PasteList and
  PasteDebug apps together with all of their data.
- **Reset PasteList - Data Only.command** keeps both installed apps while
  removing all saved data and every TCC decision associated with their bundle
  identifiers.

Both launchers start their selected reset immediately, unregister PasteList's
own Launch at Login item, and keep a recoverable copy of removed files in the
Trash. They do not reset another app's permissions or login items. Use
`reset-clean-install.sh --dry-run` to preview the actions without changing data.

## Launch at Login

PasteList uses `SMAppService.mainApp` on macOS 13 and later. Move the built app to
a stable location such as `/Applications/PasteList.app` before enabling Launch at
Login. Registration from Xcode's DerivedData folder may be unavailable or stop
working when the build location changes.

## Testing

```sh
xcodebuild test -project PasteList.xcodeproj -scheme PasteList -destination 'platform=macOS'
```

## Distribution

After building the arm64 Release configuration, create the DMG with the app,
volume, and installer-file icons attached:

```sh
Scripts/package-dmg.sh /path/to/Release/PasteList.app
```

## Updates

The first installation remains the existing PasteList DMG. Regular direct
updates use Sparkle and the signed ZIP assets listed in
[`appcast.xml`](appcast.xml). Release builds embed this feed URL:

```text
https://raw.githubusercontent.com/Kamranlapp/PasteList/main/appcast.xml
```

Prepare version 1.4 (or set `PASTELIST_VERSION`) with a Developer ID
Application identity and a Sparkle Ed25519 key available in the local keychain:

```sh
Scripts/build-update.sh
```

The script creates `dist/updates/PasteList-1.4.zip`, signs its appcast entry
using the Sparkle keychain item, and copies the resulting `appcast.xml` to the
repository root. It obtains the public key from `SPARKLE_PUBLIC_ED_KEY` or, if
that is unset, reads the existing key from the keychain; it never writes a
private key to the repository. Upload the ZIP to GitHub Release `v1.4` before
committing or publishing `appcast.xml` to `main`. ZIP files remain ignored by
Git.

To validate the signing/key setup without building anything:

```sh
Scripts/build-update.sh --dry-run
```

`PASTELIST_DEVELOPER_IDENTITY` may select a specific Developer ID Application
certificate. `PASTELIST_SPARKLE_KEYCHAIN_ACCOUNT` selects the Sparkle keychain
account (default: `ed25519`).

## Privacy

All clipboard data is stored locally. PasteList does not use iCloud, analytics,
or any external service.
