# Clip Kirby

Clip Kirby is a lightweight macOS clipboard history app inspired by the Windows clipboard board. It opens with Command + Shift + V, shows a small floating clipboard history window, and pastes a previously copied text back into the last focused input field.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer
- Accessibility permission enabled for Clip Kirby

## Restart after changes

```bash
make restart
```

## Important paste permission note

Paste uses the clipboard plus a simulated Command + V event sent back to the previously active app.

If clicking or pressing Enter does not paste after rebuilding:

1. Open System Settings.
2. Go to Privacy & Security > Accessibility.
3. Remove Clip Kirby if it already exists.
4. Add Clip Kirby again from `~/Applications/Clip Kirby.app`.
5. Quit and reopen Clip Kirby.

## App icon

Put your app icon here:

```bash
Resources/AppIcon.icns
```

## Menu bar icon

Your current menu bar icon file is supported:

```bash
Resources/StatusIcon.png
```

Recommended image style:

- `.png`
- Transparent background
- 64x64 is supported

After replacing the image, run:

```bash
make restart
```

## Usage

- Command + Shift + V: Open the clipboard board.
- Up Arrow / Down Arrow: Move through clipboard history items.
- Enter: Paste the selected clipboard item into the previously focused input field.
- Mouse click: Paste the clicked clipboard item into the previously focused input field.
- Escape: Close the clipboard board and return focus to the previous app.
- Search field: Filter clipboard history items by text.

## Notes

Clip Kirby runs as a menu-bar style background app and does not open a terminal window when launched from the generated `.app` bundle.

The app keeps clipboard history only while it is running. It does not store clipboard data permanently on disk.
