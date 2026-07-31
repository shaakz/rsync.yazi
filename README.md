# rsync.yazi

A [yazi](https://yazi-rs.github.io/) plugin for copying files with rsync, locally or to a remote server.

Select files, press a key, pick a destination — with a live progress bar in the status line.

## Requirements

- yazi 25.x or newer
- rsync (3.2.3+ recommended, for `--mkpath`)
- passwordless SSH authentication if copying to a remote server

## Installation

```sh
ya pkg add shaakz/rsync
```

Add a binding to `~/.config/yazi/keymap.toml` — make sure it isn't already in use:

```toml
[[mgr.prepend_keymap]]
on   = [ "R" ]
run  = "plugin rsync -- --remember"
desc = "Copy files using rsync"
```

## Usage

Select some files (or just hover one) and press the key. You get a menu of your
configured destinations; pick one and it prefills the input, where you can
append a subfolder before confirming.

The destination is always a **folder to copy into** — the selection is placed
inside it, whether that's one file or fifty. The folder doesn't need to exist;
it's created for you.

Press `<Esc>` at the menu to skip it and type a destination that isn't in your
list.

While the transfer runs, a bar appears on the right of the status line:

```
 rsync ████░░░░░░  47% 9.49MB/s 1/3
```

It shows the overall percentage, rate, and files completed, and disappears when
the transfer ends. Quitting yazi mid-transfer cancels it — `--partial` is on, so
re-running resumes rather than starting over.

## Configuration

Set up your destinations in `~/.config/yazi/init.lua`:

```lua
require("rsync"):setup {
	targets = {
		{ on = "l", desc = "loras",       url = "user@server.com:~/models/loras/" },
		{ on = "c", desc = "checkpoints", url = "user@server.com:~/models/checkpoints/" },
		{ on = "n", desc = "local NAS",   url = "/Volumes/nas/incoming/" },
	},
}
```

Each target needs a key (`on`), a label (`desc`), and a destination (`url`).
Keys must be unique. Restart yazi after editing — `init.lua` is only read at
startup.

Pointing a target at a parent folder and typing the subfolder each time works
well, since missing folders are created automatically.

### Options

| Option | Default | Meaning |
| --- | --- | --- |
| `targets` | `{}` | Destination menu entries |
| `mkpath` | `true` | Create the destination folder if it doesn't exist |
| `bar_width` | `10` | Width of the progress bar, in cells |
| `status_order` | `1500` | Where the bar sits among the status line's right-hand items |
| `extra_args` | `{}` | Extra rsync flags, e.g. `{ "--exclude=.DS_Store" }` |

`mkpath` needs rsync 3.2.3+ on both ends. If the far end is older, the plugin
notices and retries without it rather than failing.

### Flags

| Flag | Effect |
| --- | --- |
| `--remember` | Cache the last destination and prefill it next time |
| `--no-pick` | Skip the target menu and go straight to the input |

A positional argument sets the default destination when no target is picked:

```toml
run = "plugin rsync 'user@server.com:~/incoming/'"
```

The `--remember` cache lives in `~/.local/state/yazi/rsync.yazi.last_target`. A
picked target takes precedence over it; the cache is what you get when you press
`<Esc>` at the menu.

## Troubleshooting

Logs are written to `~/.local/state/yazi/yazi.log`.

## Credits

A fork of [GianniBYoung/rsync.yazi](https://github.com/GianniBYoung/rsync.yazi)
by [Gianni B. Young](https://github.com/GianniBYoung), which this builds on.
Original demo art by [chrissabug](https://x.com/chrissabug).

This fork adds the status-line progress bar and the configurable target menu,
and changes the destination to always be a folder rather than a full filename.

## License

See [LICENSE](LICENSE).
