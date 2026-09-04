#!/bin/sh
set -eu

REPO="${MIHU_REPO:-mihu-ai/mihu-cli-releases}"
BIN="mihu"
PKG="mihu-cli"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "'$1' is required but not installed"; }

need curl
need tar

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin|linux) ;;
  mingw*|msys*|cygwin*) err "on Windows run in PowerShell: irm https://mihu.ai/install.ps1 | iex" ;;
  *) err "unsupported OS: $OS" ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) err "unsupported architecture: $ARCH" ;;
esac

if [ -n "${MIHU_VERSION:-}" ]; then
  VERSION="$MIHU_VERSION"
else
  VERSION="$(curl -sSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" | sed 's#.*/tag/##')"
  [ -n "$VERSION" ] || err "could not determine latest version"
fi
VERSION_NUM="${VERSION#v}"

ASSET="${PKG}_${VERSION_NUM}_${OS}_${ARCH}.tar.gz"
BASE="https://github.com/$REPO/releases/download/$VERSION"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "Downloading $BIN $VERSION ($OS/$ARCH)"
curl -sSfL "$BASE/$ASSET" -o "$TMP/$ASSET" || err "download failed: $BASE/$ASSET"
curl -sSfL "$BASE/checksums.txt" -o "$TMP/checksums.txt" || err "download failed: checksums.txt"

log "Verifying checksum"
EXPECTED="$(grep " $ASSET\$" "$TMP/checksums.txt" | awk '{print $1}')"
[ -n "$EXPECTED" ] || err "no checksum entry for $ASSET"
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{print $1}')"
else
  ACTUAL="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
fi
[ "$EXPECTED" = "$ACTUAL" ] || err "checksum mismatch (expected $EXPECTED, got $ACTUAL)"

tar -xzf "$TMP/$ASSET" -C "$TMP"
[ -f "$TMP/$BIN" ] || err "archive did not contain '$BIN'"

if [ -n "${MIHU_INSTALL_DIR:-}" ]; then
  INSTALL_DIR="$MIHU_INSTALL_DIR"
elif [ -w /usr/local/bin ]; then
  INSTALL_DIR="/usr/local/bin"
elif command -v sudo >/dev/null 2>&1 && [ -t 0 ]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
fi
mkdir -p "$INSTALL_DIR" 2>/dev/null || true

log "Installing to $INSTALL_DIR/$BIN"
if [ -w "$INSTALL_DIR" ]; then
  install -m 755 "$TMP/$BIN" "$INSTALL_DIR/$BIN"
else
  sudo install -m 755 "$TMP/$BIN" "$INSTALL_DIR/$BIN"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    printf '\n\033[1;33mnote:\033[0m %s is not in your PATH. Add this to your shell profile:\n' "$INSTALL_DIR"
    printf '    export PATH="%s:$PATH"\n\n' "$INSTALL_DIR"
    ;;
esac

log "Installed: $("$INSTALL_DIR/$BIN" version 2>/dev/null || echo "$BIN $VERSION")"
printf '\nGet started:\n    mihu login\n\n'
