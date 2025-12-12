# polyglotreader (for Mac)

A text reader with smart encoding detection, library management, and customizable display.

## Features

- Smart encoding detection (UTF-8, GB18030, GBK, Shift_JIS, EUC-JP, Big5, etc.)
- Library management with drag & drop support
- Pagination with keyboard navigation (← →)
- Customizable font and font size
- Dark mode support with system appearance sync
- Config persistence

## Usage

- **Open File**: Click "Open" or Cmd+O
- **Open Folder**: Click "Open Folder" or Cmd+Shift+O (adds all text files from folder)
- **Navigate Pages**: Click Prev/Next buttons or use ← → arrow keys
- **Change Encoding**: Use the Encoding dropdown if auto-detection is wrong
- **Change Font**: Use the Font dropdown
- **Adjust Font Size**: Click +/- buttons
- **Toggle Dark Mode**: Click the 🌙 Dark / ☀ Light button
- **Remove from Library**: Select items and click "Remove"
- **Drag & Drop**: Drag files or folders onto the library panel

## Dark Mode

The app follows your Mac's system appearance by default. When your Mac switches to dark mode, the reader automatically switches too.

You can also manually toggle dark/light mode using the button in the toolbar. Manual toggle will disable the "Follow System Appearance" option until you re-enable it from View menu.

To re-enable system sync: **View → Follow System Appearance**

## Config Files

Stored in `~/.polyglot_reader/`:
- `config.json` - Font settings, window size, lines per page, appearance settings
- `library.json` - List of files in library

## Supported File Extensions

txt, text, md, log, csv, json, xml, html, py, js, c, h, cpp, java, rb, go, rs, swift, kt, sh, bat, ini, cfg, yaml, yml, toml
