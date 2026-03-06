#!/bin/bash
set -euo pipefail

REPO="ympkg/yummy"

# Detect OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"
IS_WINDOWS=false

case "$OS" in
  Linux)                TARGET_OS="unknown-linux-gnu" ;;
  Darwin)               TARGET_OS="apple-darwin" ;;
  MINGW*|MSYS*|CYGWIN*) TARGET_OS="pc-windows-msvc"; IS_WINDOWS=true ;;
  *)                    echo "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64) TARGET_ARCH="x86_64" ;;
  aarch64|arm64) TARGET_ARCH="aarch64" ;;
  *)             echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

TARGET="${TARGET_ARCH}-${TARGET_OS}"

# Install directory: use Windows-friendly path on Git Bash
if [ -n "${YM_INSTALL_DIR:-}" ]; then
  INSTALL_DIR="$YM_INSTALL_DIR"
elif [ "$IS_WINDOWS" = true ]; then
  INSTALL_DIR="${USERPROFILE:-$HOME}/.ym/bin"
else
  INSTALL_DIR="$HOME/.ym/bin"
fi

# Get latest version from GitHub API
echo "Fetching latest release..."
RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
VERSION=$(curl -fsSL "$RELEASE_URL" 2>/dev/null | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/' || true)

if [ -z "$VERSION" ]; then
  echo "No stable release found. Trying latest pre-release..."
  RELEASE_URL="https://api.github.com/repos/${REPO}/releases"
  VERSION=$(curl -fsSL "$RELEASE_URL" | grep '"tag_name"' | head -1 | sed 's/.*"v\(.*\)".*/\1/')
fi

if [ -z "$VERSION" ]; then
  echo "Error: Could not determine version to install."
  exit 1
fi

echo "Installing ym v${VERSION} for ${TARGET}..."

# Determine archive format
if [ "$IS_WINDOWS" = true ]; then
  ARCHIVE="ym-${VERSION}-${TARGET}.zip"
else
  ARCHIVE="ym-${VERSION}-${TARGET}.tar.gz"
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ARCHIVE}"

# Download
TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'ym-install')
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading ${DOWNLOAD_URL}..."
curl -fsSL "$DOWNLOAD_URL" -o "${TMPDIR}/${ARCHIVE}"

mkdir -p "$INSTALL_DIR"

EXTRACTED="${TMPDIR}/ym-${VERSION}-${TARGET}"

if [ "$IS_WINDOWS" = true ]; then
  # Extract zip: try unzip, fallback to powershell, fallback to tar
  if command -v unzip &>/dev/null; then
    unzip -qo "${TMPDIR}/${ARCHIVE}" -d "$TMPDIR"
  elif command -v powershell &>/dev/null; then
    powershell -NoProfile -Command "Expand-Archive -Path '$(cygpath -w "${TMPDIR}/${ARCHIVE}")' -DestinationPath '$(cygpath -w "$TMPDIR")' -Force"
  elif tar --help 2>&1 | grep -q 'bsdtar'; then
    tar xf "${TMPDIR}/${ARCHIVE}" -C "$TMPDIR"
  else
    echo "Error: No unzip tool found. Install unzip or use PowerShell install script."
    exit 1
  fi

  cp "${EXTRACTED}/ym.exe" "$INSTALL_DIR/"
  cp "${EXTRACTED}/ym.exe" "$INSTALL_DIR/ymc.exe"
  [ -f "${EXTRACTED}/ym-agent.jar" ] && cp "${EXTRACTED}/ym-agent.jar" "$INSTALL_DIR/"
else
  tar xzf "${TMPDIR}/${ARCHIVE}" -C "$TMPDIR"
  cp "${EXTRACTED}/ym" "$INSTALL_DIR/"
  cp "${EXTRACTED}/ym" "$INSTALL_DIR/ymc"
  chmod +x "$INSTALL_DIR/ym" "$INSTALL_DIR/ymc"
  [ -f "${EXTRACTED}/ym-agent.jar" ] && cp "${EXTRACTED}/ym-agent.jar" "$INSTALL_DIR/"
fi

echo ""
echo "✓ Installed ym v${VERSION} to ${INSTALL_DIR}"
echo ""

# PATH guidance
if [ "$IS_WINDOWS" = true ]; then
  WIN_PATH=$(cygpath -w "$INSTALL_DIR" 2>/dev/null || echo "$INSTALL_DIR")
  case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
      echo "Add to PATH (run in PowerShell as admin):"
      echo ""
      echo "  [Environment]::SetEnvironmentVariable('PATH', \"${WIN_PATH};\" + [Environment]::GetEnvironmentVariable('PATH', 'User'), 'User')"
      echo ""
      echo "Or add to your ~/.bashrc for Git Bash:"
      echo ""
      echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
      echo ""
      ;;
  esac
else
  case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
      echo "Add to your shell profile:"
      echo ""
      echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
      echo ""
      ;;
  esac
fi

echo "Run 'ym --version' to verify."
