# Screenshot Shelf

A small native macOS menu bar app for grabbing recent screenshots.

**Click the menu bar icon to open the shelf, or hold ⌘⇧S → drag a screenshot → release to close.**

The shelf stays visible only while the shortcut is held. Releasing any shortcut key hides it immediately. If you have already started a drag, keep holding the mouse button and finish dropping the file after the shelf disappears. You can also drag directly from the menu bar icon to drag the latest screenshot without opening the shelf.

## Install

Requires **macOS 13 or newer**. Universal downloads support Apple silicon and Intel Macs.

1. Download the DMG from [Releases](https://github.com/KanishkVashisht/screenshot-shelf/releases/latest).
2. Open it and drag **Screenshot Shelf.app** into **Applications**.
3. Launch the app. Click its photo icon in the menu bar to view your recent screenshots.
4. Hold **⌘⇧S** (or your configured shortcut) to view the shelf without using the mouse.

The downloadable build is ad-hoc signed and **not Apple-notarized**. macOS may require explicit approval in **System Settings → Privacy & Security** before opening it. Building locally is also supported.

If macOS asks for Desktop access, allow it to load screenshots, or use **Choose Screenshot Folder…** from the menu bar. Enable **Launch at Login** there if desired. The source installer enables it automatically.

## How it works

- Shows up to 30 screenshots, newest first, from the macOS screenshot save location (Desktop by default), or a folder you choose.
- Left-clicking a thumbnail copies it to the clipboard. Dragging supplies a real file URL and permits copying; the original stays in place.
- Release **S**, **Command**, or **Shift** to close the shelf. **Esc** or clicking outside also dismisses it until the next press.
- Pressing the menu bar icon toggles the shelf open or closed. Moving far enough during the same press starts a drag of the latest screenshot and hides the shelf; right-clicking opens settings, including folder selection, Launch at Login, and Quit.
- Choose **Change Shortcut…** in Settings to configure the global shortcut, or choose **Clear** in the shortcut dialog to disable keyboard activation. The menu-bar icon remains available.
- Arrow keys select screenshots while the shelf is open. Return or double-click opens the selected file. Right-click a thumbnail for additional actions.
- Scans refresh every two seconds while visible. Thumbnails are cached and refreshed when files change.

Screenshots are recognized by macOS metadata or common screenshot filename prefixes. The app reads only the selected folder, without subfolders. Renamed images without screenshot metadata and screenshots saved only to the clipboard are not included.

The configured shortcut belongs to Screenshot Shelf while it runs, superseding app shortcuts using the same keys. If another global shortcut already owns it, the app reports the conflict and offers **Retry Shortcut** in the menu.

## Privacy

Everything runs locally, without accounts, analytics, uploads, or a server. The app does not move or delete screenshots. It uses macOS's registered-hotkey API and briefly checks the current shortcut state only while it is held; it does not record typed text. No Accessibility or Input Monitoring permission is requested by the app. Folder access is required for previews.

## Build and develop

Install [Apple command line tools](https://developer.apple.com/xcode/resources/) or Xcode, then:

```sh
git clone https://github.com/KanishkVashisht/screenshot-shelf.git
cd screenshot-shelf
./test.sh                 # Discovery and hold/release behavior tests
./build.sh                # App for the current Mac architecture
./build.sh --universal    # Apple silicon + Intel app
./install.sh              # Build, install to ~/Applications, launch at login
./package.sh              # Universal DMG, ZIP, and SHA256SUMS.txt in dist/
```

No third-party libraries or package manager are required. The source uses AppKit, Carbon hotkey events, ImageIO, CoreGraphics key state, and ServiceManagement. Build scripts accept `SCREENSHOT_SHELF_SIGN_IDENTITY` to use an available Developer ID certificate; otherwise they ad-hoc sign. Developer ID signing alone does not notarize the app.

`Sources/HoldGesture.swift` controls hold/release behavior. `Sources/ShelfWindow.swift` contains the shelf and drag source. `Sources/ScreenshotStore.swift` handles discovery and thumbnails. `Sources/AppDelegate.swift` wires up the menu, hotkey, and login item.

The tests cover sorting, thumbnail decoding and invalidation, limits, unavailable folders, each key's release, auto-repeat, dismissal, and hiding during a drag. `./test-drag.sh` builds an optional native drag-and-drop fixture; open the resulting app and drag the thumbnail into its target. See [release instructions](docs/RELEASING.md) for packaging and publishing.

## Remove

Disable **Launch at Login**, choose **Quit Screenshot Shelf**, and move the app to the Trash. Your screenshots remain untouched.

## License

[MIT](LICENSE)
