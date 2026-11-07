#!/usr/bin/env bash
# scripts/bootstrap-toolchain.sh
# Reproducible bootstrap script for the NIGHTLINE: LAST TRAIN Luau & Rojo toolchain.
# Installs official Linux x86_64 binaries for:
# - Luau CLI VM & Analyzer (0.746)
# - Luau Language Server (1.70.1) + Roblox globalTypes.d.luau
# - Rojo (7.7.1)
# - StyLua (2.6.0)
# - Selene (0.32.0) + generated roblox.yml in the isolated toolchain directory

set -euo pipefail

TOOLS_DIR="${NIGHTLINE_TOOLCHAIN_DIR:-/tmp/roblox-tools}"
mkdir -p "$TOOLS_DIR"

LUAU_VERSION="0.746"
LUAU_LSP_VERSION="1.70.1"
ROJO_VERSION="7.7.1"
STYLUA_VERSION="2.6.0"
SELENE_VERSION="0.32.0"

download_and_unzip() {
  local url="$1"
  local zip_path="$2"
  local target_dir="$3"
  curl -fsSL "$url" -o "$zip_path"
  unzip -qo "$zip_path" -d "$target_dir"
  rm -f "$zip_path"
}

if [ ! -x "$TOOLS_DIR/luau" ]; then
  echo "[bootstrap-toolchain] Installing official Luau CLI VM v${LUAU_VERSION}..."
  download_and_unzip \
    "https://github.com/luau-lang/luau/releases/download/${LUAU_VERSION}/luau-ubuntu.zip" \
    "$TOOLS_DIR/luau.zip" \
    "$TOOLS_DIR"
  chmod +x "$TOOLS_DIR/luau" "$TOOLS_DIR/luau-analyze"
fi

if [ ! -x "$TOOLS_DIR/luau-lsp" ]; then
  echo "[bootstrap-toolchain] Installing Luau Language Server v${LUAU_LSP_VERSION}..."
  download_and_unzip \
    "https://github.com/JohnnyMorganz/luau-lsp/releases/download/${LUAU_LSP_VERSION}/luau-lsp-linux-x86_64.zip" \
    "$TOOLS_DIR/luau-lsp.zip" \
    "$TOOLS_DIR"
  chmod +x "$TOOLS_DIR/luau-lsp"
fi

if [ ! -s "$TOOLS_DIR/globalTypes.d.luau" ]; then
  echo "[bootstrap-toolchain] Downloading official Roblox globalTypes.d.luau..."
  curl -fsSL "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau" \
    -o "$TOOLS_DIR/globalTypes.d.luau"
fi

if [ ! -x "$TOOLS_DIR/rojo" ]; then
  echo "[bootstrap-toolchain] Installing Rojo v${ROJO_VERSION}..."
  download_and_unzip \
    "https://github.com/rojo-rbx/rojo/releases/download/v${ROJO_VERSION}/rojo-${ROJO_VERSION}-linux-x86_64.zip" \
    "$TOOLS_DIR/rojo.zip" \
    "$TOOLS_DIR"
  chmod +x "$TOOLS_DIR/rojo"
fi

if [ ! -x "$TOOLS_DIR/stylua" ]; then
  echo "[bootstrap-toolchain] Installing StyLua v${STYLUA_VERSION}..."
  download_and_unzip \
    "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-x86_64.zip" \
    "$TOOLS_DIR/stylua.zip" \
    "$TOOLS_DIR"
  chmod +x "$TOOLS_DIR/stylua"
fi

if [ ! -x "$TOOLS_DIR/selene" ]; then
  echo "[bootstrap-toolchain] Installing Selene v${SELENE_VERSION}..."
  download_and_unzip \
    "https://github.com/Kampfkarren/selene/releases/download/${SELENE_VERSION}/selene-${SELENE_VERSION}-linux.zip" \
    "$TOOLS_DIR/selene.zip" \
    "$TOOLS_DIR"
  chmod +x "$TOOLS_DIR/selene"
fi

if [ ! -s "$TOOLS_DIR/roblox.yml" ]; then
  echo "[bootstrap-toolchain] Generating Selene roblox.yml standard library in $TOOLS_DIR..."
  (cd "$TOOLS_DIR" && "$TOOLS_DIR/selene" generate-roblox-std)
fi

echo "[bootstrap-toolchain] Toolchain ready in $TOOLS_DIR:"
echo "  - luau:     $(ls -1 "$TOOLS_DIR/luau")"
echo "  - luau-lsp: $("$TOOLS_DIR/luau-lsp" --version)"
echo "  - rojo:     $("$TOOLS_DIR/rojo" --version)"
echo "  - stylua:   $("$TOOLS_DIR/stylua" --version)"
echo "  - selene:   $("$TOOLS_DIR/selene" --version)"
