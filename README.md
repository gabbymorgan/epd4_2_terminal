# terminal-epd

Print a terminal to a 4.2" Waveshare e-Paper from a Raspberry Pi. Includes a
USB-keyboard-driven interactive bash shell, plus pipe/fifo/tmux mirror modes.

## Hardware

- Raspberry Pi (any 40-pin model) with SPI enabled
- 4.2" Waveshare e-Paper module (**V2** recommended - supports flicker-free
  partial refresh), wired per the [Waveshare wiki](https://www.waveshare.com/wiki/4.2inch_e-Paper_Module_Manual)
- Optional: a USB keyboard for the interactive shell

## Quick start (freshly flashed Pi)

```sh
# from this repo, on the Pi:
bash setup.sh
sudo reboot        # only if the script asks
```

`setup.sh` is idempotent - it installs packages, enables SPI, adds the user
to `gpio`/`spi`/`input`, installs the Python libraries and the Waveshare
driver, and registers a systemd user service that starts epterm at boot as a
keyboard terminal. Run it as many times as you like.

After reboot, plug in a keyboard and type - the e-paper shows a bash shell.

## Manual install

```sh
sudo apt-get install -y python3-pip python3-pil python3-numpy python3-gpiozero git
python3 -m pip install --user --break-system-packages evdev pyte spidev
git clone --depth 1 https://github.com/waveshare/e-Paper.git ~/e-Paper
install -D -m 0755 epterm ~/bin/epterm
install -D -m 0644 epterm.service ~/.config/systemd/user/epterm.service
sudo loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now epterm
```

## Usage

The systemd service runs `epterm --shell --grab` (keyboard terminal).

Run manually for other modes:

| Command | What it does |
|---|---|
| `epterm --shell` | Interactive bash driven by a USB keyboard (auto-detected) |
| `epterm --shell /dev/input/eventN` | Same, with an explicit keyboard device |
| `some_command \| epterm` | Show the last screenful of a command's output |
| `epterm --pipe` | Listen on a named pipe; `echo hi > /tmp/epterm` |
| `epterm --tmux [SECS]` | Mirror the active tmux pane every SECS seconds |

Key options: `--size`, `--rows`, `--cols`, `--interval`, `--full-every`,
`--full-clear`, `--idle`, `--exec CMD`, `--grab`, `--clear-only`.

## How it works

- The shell runs on a pseudo-terminal sized to the panel (54x16) and is
  rendered through a VT100 emulator (`pyte`) - prompts, line editing and
  command output display correctly.
- Refresh strategy for the V2 panel: full refresh on the first frame, on
  wake-from-idle, on large changes, and periodically (every 5 partials);
  flicker-free partial refresh in between using correct old/new RAM buffers.
- The panel sleeps when idle and is blanked on shutdown (`--clear-only` is
  wired as `ExecStopPost` so even a SIGKILLed process leaves a blank panel).

## Files

- `epterm` - the program (Python 3, no install needed)
- `setup.sh` - idempotent Raspberry Pi bootstrap
- `epterm.service` - systemd user unit (uses `%h`, any username)

## Notes / limitations

- US QWERTY keyboard layout (easy to customize in `epterm`).
- E-paper refresh is slow (~1s minimum between frames, ~5s full refresh);
  full-screen apps like `vim`/`top` work but are not comfortable.
- A hard power cut leaves the last image on the panel (inherent to e-paper).