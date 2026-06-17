# Clip Kirby

Clip Kirby is a lightweight macOS clipboard history app inspired by the Windows clipboard board. It opens with Command + Shift + V, shows a small floating clipboard history window, and lets you paste a previously copied text back into the last focused input field.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer
- Accessibility permission enabled for the app

## App icon

The app icon is the image shown in Finder, Applications, Spotlight, and macOS app info screens.

Put your app icon here:

```bash
Resources/AppIcon.icns
```

The file must be named exactly:

```bash
AppIcon.icns
```

Recommended format:

- `.icns`
- Square image
- 1024x1024 source image converted to macOS `.icns`

After adding or replacing the app icon, run:

```bash
make restart
```

## Menu bar icon

The menu bar icon is the small image shown in the top macOS bar.

Clip Kirby now supports these filenames inside the `Resources` folder:

```bash
Resources/StatusIconTemplate.png
Resources/StatusIcon.png
Resources/MenuBarIcon.png
```

Use only one of them if possible.

Recommended option for macOS menu bar:

```bash
Resources/StatusIconTemplate.png
```

Recommended image style for `StatusIconTemplate.png`:

- `.png`
- Transparent background
- Simple one-color black icon
- 18x18, 36x36, or 64x64 pixels

`StatusIconTemplate.png` is treated as a macOS template icon. macOS automatically changes its color for light mode and dark mode.

If you want to use a colored image instead, use:

```bash
Resources/StatusIcon.png
```

or:

```bash
Resources/MenuBarIcon.png
```

Colored icons may not always look perfect in the macOS menu bar, so a simple template icon is usually better.

After adding or replacing the menu bar icon, run:

```bash
make restart
```

If the top bar icon still does not change, make sure the currently running Clip Kirby app is closed and reopened. The `make restart` command rebuilds, reinstalls, quits the old running app, and opens the new installed app.

If no menu bar icon file exists, Clip Kirby falls back to the text icon:

```text
⌘V
```

## Build the macOS app

```bash
make app
```

This creates a clickable macOS app bundle at:

```bash
build/Clip Kirby.app
```

## Install as a normal app

```bash
make install
```

This installs the app to:

```bash
~/Applications/Clip Kirby.app
```

## Restart after changes

```bash
make restart
```

Use this after changing icons, app metadata, or source code.

## Open the app manually

```bash
open "$HOME/Applications/Clip Kirby.app"
```

## Start automatically when your Mac opens

```bash
make enable-login
```

This creates a user LaunchAgent so Clip Kirby starts automatically when you log in to macOS.

## Disable automatic startup

```bash
make disable-login
```

## Accessibility permission

On the first launch, macOS may ask for Accessibility permission. Enable it from:

System Settings > Privacy & Security > Accessibility

Allow Clip Kirby. If you previously ran it from Terminal, you may also need to allow your terminal app.

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
