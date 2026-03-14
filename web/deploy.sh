#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

info() { printf '\033[1;34m=> %s\033[0m\n' "$*"; }

#──────────────────────────────────────────────
# 1. Build (reuse run.sh but stop before dev server)
#──────────────────────────────────────────────
EMSDK_DIR="$SCRIPT_DIR/.emsdk"

# Source emsdk if available
if [ -d "$EMSDK_DIR" ]; then
    EMSDK_QUIET=1 source "$EMSDK_DIR/emsdk_env.sh"
fi

# Ensure emcc is available
if ! command -v emcc >/dev/null 2>&1; then
    info "emsdk not found — run ./run.sh first to install dependencies"
    exit 1
fi

# Build WASM
BUILD_DIR="$SCRIPT_DIR/build"
if [ ! -f "$BUILD_DIR/Makefile" ]; then
    info "Configuring CMake build …"
    mkdir -p "$BUILD_DIR"
    (cd "$BUILD_DIR" && emcmake cmake ..)
fi
info "Building WASM …"
(cd "$BUILD_DIR" && emmake make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)")

# npm install + webpack production build
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    info "Installing npm dependencies …"
    npm install
fi
info "Building webpack bundle …"
npx webpack --mode production

#──────────────────────────────────────────────
# 2. Deploy to Netlify
#──────────────────────────────────────────────
if ! command -v netlify >/dev/null 2>&1; then
    info "Installing Netlify CLI …"
    npm install -g netlify-cli
fi

info "Deploying docs/ to Netlify …"
netlify deploy --dir=docs --prod
