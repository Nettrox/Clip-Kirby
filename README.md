# Clip Kirby

Clip Kirby is a small macOS clipboard history app. It opens with Command + Shift + V, shows your recent copied text in a Kirby pink clipboard board, and pastes the selected item into the last focused input field.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer

## Install

```bash
make install
```

This builds the app and installs it to:

```bash
~/Applications/Clip Kirby.app
```

## Run

```bash
open "$HOME/Applications/Clip Kirby.app"
```

## Start automatically on login

```bash
make enable-login
```

## Stop automatic login start

```bash
make disable-login
```

## Rebuild and reopen after changes

```bash
make restart
```

## Usage

- Command + Shift + V: Open Clip Kirby.
- Up Arrow / Down Arrow: Select an item.
- Enter: Paste the selected item.
- Mouse click: Paste the clicked item.
- Escape: Close Clip Kirby.
