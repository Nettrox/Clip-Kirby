# Clip Poppy [Mac Clipboard Board]

A lightweight macOS clipboard history app inspired by the Windows clipboard board. It opens with Command + Shift + V, shows a small floating clipboard history window, and lets you paste a previous copied text back into the last focused input field.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer
- Accessibility permission enabled for the app or the terminal running it

## Run

```bash
swift run
```

On the first launch, macOS may ask for Accessibility permission. Enable it from:

System Settings > Privacy & Security > Accessibility

Allow your terminal app or the compiled Mac Clipboard Board app.

## Usage

- Command + Shift + V: Open the clipboard board.
- Up Arrow / Down Arrow: Move through clipboard history items.
- Enter: Paste the selected clipboard item into the previously focused input field.
- Mouse click: Paste the clicked clipboard item into the previously focused input field.
- Escape: Close the clipboard board and return focus to the previous app.
- Search field: Filter clipboard history items by text.

## Notes

The app keeps clipboard history only while it is running. It does not store clipboard data permanently on disk.
