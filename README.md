# Rsync.yazi

A [yazi](https://yazi-rs.github.io/) plugin for simple rsync copying locally and up to remote servers.

![Demo](assets/demo.gif)
Thanks to [chrissabug](https://x.com/chrissabug) for creating lovely art!

## Features

- Copy the selected (or hovered) files to any local or remote destination
- A live progress bar in the status line while the transfer runs
- Preconfigured targets, offered as a one-keypress menu
- Creates the destination folder if it doesn't exist yet

## Pre-Reqs

1. yazi latest version preferred
2. rsync
3. passwordless authentication if copying to a remote server

## Installation

```sh
ya pkg add GianniBYoung/rsync
```

## Usage

Add the bind to your `~/.config/yazi/keymap.toml`

**WARNING:** Make sure the chosen binding isn't already in use!!

```toml
[[mgr.prepend_keymap]]
on   = [ "R" ]
run  = "plugin rsync"
desc = "Copy files using rsync"
```

The destination you type is always a **folder to copy into** — the selection is
placed inside it. This holds whether you have one file selected or fifty, so you
never have to retype a filename.

### Preconfigured Targets

Set up the places you copy to most often in `~/.config/yazi/init.lua`, and they
are offered as a menu when the plugin runs:

```lua
require("rsync"):setup {
	targets = {
		{ on = "l", desc = "loras",       url = "user@server.com:~/models/loras/" },
		{ on = "c", desc = "checkpoints", url = "user@server.com:~/models/checkpoints/" },
		{ on = "n", desc = "local NAS",   url = "/Volumes/nas/incoming/" },
	},
}
```

Picking one prefills the input with its `url`, so you can still append a
subfolder before confirming. Press `<Esc>` at the menu to skip it and type a
destination that isn't in the list.

### Options

All are optional:

| Option | Default | Meaning |
| --- | --- | --- |
| `targets` | `{}` | Target menu entries: `on` (key), `desc` (label), `url` (destination) |
| `mkpath` | `true` | Create the destination folder if it doesn't exist |
| `bar_width` | `10` | Width of the status-line progress bar, in cells |
| `status_order` | `1500` | Where the bar sits among the status line's right-hand items |
| `extra_args` | `{}` | Extra rsync flags, e.g. `{ "--exclude=.DS_Store" }` |

`mkpath` needs rsync 3.2.3+ on both ends. If the far end is older, the plugin
notices and retries without it rather than failing.

### Progress

While a transfer runs, a bar appears on the right of the status line with the
overall percentage, transfer rate, and how many files are done:

```
 rsync ████░░░░░░  47% 9.49MB/s 1/3
```

It is added when the transfer starts and removed when it ends, so it doesn't
take up room the rest of the time. Quitting yazi mid-transfer cancels it —
`--partial` is on, so re-running resumes rather than starting over.

### Specify Default Remote Server

A positional argument is used as the default destination when no target is
picked:

```toml
[[mgr.prepend_keymap]]
on   = [ "R" ]
run  = "plugin rsync 'user@server.com:~/incoming/'"
desc = "Copy files using rsync to default location"
```

### Remember Last Target

Use `--remember` to cache the last used target. On next invocation, the input
field will be pre-filled with the cached target.

```toml
[[mgr.prepend_keymap]]
on   = [ "R" ]
run  = "plugin rsync -- --remember"
desc = "Copy files using rsync (remember target)"
```

**Note:** The target is stored in `~/.local/state/yazi/rsync.yazi.last_target`.
A picked target takes precedence over the cached one; the cache is what you get
when you press `<Esc>` at the target menu.

### Skip The Target Menu

`--no-pick` goes straight to the input, even when targets are configured:

```toml
run = "plugin rsync -- --no-pick --remember"
```

## Upgrading from earlier versions

- **The destination is now always treated as a folder.** Previously, selecting a
  single file prefilled the full destination *filename*. It now prefills the
  folder, matching the multi-file behaviour.
- **The `--remember` cache moved** from `~/.config/yazi/plugins/rsync.yazi/.last_target`
  to `~/.local/state/yazi/rsync.yazi.last_target`, so it survives `ya pkg upgrade`.
  The old location is still read once as a fallback.

## Troubleshooting

Basic logging information is sent to `~/.local/state/yazi/yazi.log`

*Note: This plugin has only been tested on Linux and macOS

## Contributing

Run into a bug or want a certain feature added? Submit an issue!

- Give it a star if you like it ⭐!
- PRs welcome :)
