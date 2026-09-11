#!/usr/bin/env bash
#
# setup.sh - bootstrap for running epterm on a freshly flashed Raspberry Pi.
#
# Idempotent: safe to run again and again. Run as a normal user (sudo is
# used internally and will prompt for a password when needed).
#
#   Usage: bash setup.sh
#
# Installs system packages, enables SPI, adds the user to the gpio/spi/input
# groups, installs the Python libraries and the Waveshare e-Paper driver,
# copies epterm to ~/bin, and registers the epterm keyboard-terminal systemd
# user service (autostart via linger).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_NAME="${USER:-$(id -un)}"
HOME_DIR="${HOME:-$(eval echo "~$USER_NAME")}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
note()  { printf "${GREEN}[setup]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn ]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[error]${NC} %s\n" "$*" >&2; exit 1; }

# --- sanity checks ---------------------------------------------------------
[ "$(id -u)" -eq 0 ] && fail "run as a normal user (sudo is used internally)"
grep -qi raspberry /proc/cpuinfo || fail "this does not look like a Raspberry Pi"
command -v sudo >/dev/null || fail "sudo is not available"

# --- user manager / linger (needed for systemctl --user, esp. over SSH) ----
note "enabling linger for user '$USER_NAME'"
sudo loginctl enable-linger "$USER_NAME" || warn "could not enable linger"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# --- system packages -------------------------------------------------------
note "updating apt and installing system packages"
sudo apt-get update -y
sudo apt-get install -y \
    python3 python3-pip python3-pil python3-numpy python3-gpiozero git
# bookworm ships python3-spidev as an apt package; trixie installs via pip
sudo apt-get install -y python3-spidev || true

# --- SPI -------------------------------------------------------------------
REBOOT=0
SPI_CFG=""
for f in /boot/firmware/config.txt /boot/config.txt; do
    [ -f "$f" ] && SPI_CFG="$f" && break
done
[ -z "$SPI_CFG" ] && fail "cannot find /boot config.txt"

if grep -q '^dtparam=spi=on' "$SPI_CFG"; then
    note "SPI already enabled in $SPI_CFG"
else
    note "enabling SPI in $SPI_CFG"
    echo 'dtparam=spi=on' | sudo tee -a "$SPI_CFG" >/dev/null
    REBOOT=1
fi
if [ -e /dev/spidev0.0 ]; then
    note "SPI device already active"
    REBOOT=0
fi

# --- groups ----------------------------------------------------------------
GROUP_CHANGED=0
for g in gpio spi input; do
    if ! id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx "$g"; then
        note "adding user to group '$g'"
        sudo usermod -aG "$g" "$USER_NAME"
        GROUP_CHANGED=1
    fi
done
[ "$GROUP_CHANGED" = 1 ] && REBOOT=1

# --- python libraries (user install) ---------------------------------------
note "installing python libraries (evdev, pyte, spidev)"
if ! python3 -m pip install --user evdev pyte spidev >/dev/null 2>&1; then
    note "plain pip install failed; retrying with --break-system-packages (PEP 668)"
    python3 -m pip install --user --break-system-packages evdev pyte spidev
fi

# --- waveshare e-Paper library ---------------------------------------------
WS_DIR="$HOME_DIR/e-Paper"
if [ -d "$WS_DIR/.git" ]; then
    note "updating waveshare e-Paper library"
    git -C "$WS_DIR" pull --quiet || warn "could not update $WS_DIR"
elif [ -d "$WS_DIR" ]; then
    warn "$WS_DIR exists but is not a git repo; leaving it as-is"
else
    note "cloning waveshare e-Paper library"
    git clone --depth 1 https://github.com/waveshare/e-Paper.git "$WS_DIR"
fi

# --- install epterm --------------------------------------------------------
note "installing epterm to ~/bin"
install -D -m 0755 "$SCRIPT_DIR/epterm" "$HOME_DIR/bin/epterm"

if ! grep -qs 'HOME/bin' "$HOME_DIR/.bashrc" 2>/dev/null; then
    printf '\n# epterm\nexport PATH="$HOME/bin:$PATH"\n' >> "$HOME_DIR/.bashrc"
    note "added ~/bin to PATH in ~/.bashrc"
fi

# --- systemd user service --------------------------------------------------
SERVICE_DIR="$HOME_DIR/.config/systemd/user"
note "installing epterm systemd user service"
install -D -m 0644 "$SCRIPT_DIR/epterm.service" "$SERVICE_DIR/epterm.service"

if ! systemctl --user daemon-reload 2>/dev/null; then
    warn "user manager not ready; retrying after a short wait"
    sleep 3
    systemctl --user daemon-reload
fi

if [ "$REBOOT" = 1 ]; then
    note "enabling epterm service (starts after reboot)"
    systemctl --user enable epterm
else
    note "starting epterm service"
    systemctl --user enable --now epterm
fi

# --- summary ---------------------------------------------------------------
if [ "$REBOOT" = 1 ]; then
    printf "\n${YELLOW}SPI and/or group changes need a reboot to take effect:${NC}\n"
    printf "    sudo reboot\n"
    printf "After reboot, epterm starts automatically as a keyboard terminal.\n"
else
    printf "\n${GREEN}epterm is running.${NC} Verify with:\n"
    printf "    systemctl --user status epterm\n"
    printf "Logs: journalctl --user -u epterm\n"
fi