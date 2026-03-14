#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

EMSDK_DIR="$SCRIPT_DIR/.emsdk"

#──────────────────────────────────────────────
# Helpers
#──────────────────────────────────────────────
info()  { printf '\033[1;34m=> %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

install_package() {
    local pkg="$1"
    info "Installing $pkg …"
    if [[ "$(uname)" == "Darwin" ]]; then
        if ! command_exists brew; then
            info "Homebrew not found – installing …"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install "$pkg"
    elif command_exists apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
    else
        err "Unsupported platform – install $pkg manually."
    fi
}

#──────────────────────────────────────────────
# 1. System dependencies (cmake, node/npm, git, python3)
#──────────────────────────────────────────────
for dep in cmake node git python3; do
    if ! command_exists "$dep"; then
        case "$dep" in
            node) install_package node ;;    # brew: node, apt: nodejs
            *)    install_package "$dep" ;;
        esac
    fi
done

# On Debian/Ubuntu, npm may not come with nodejs
if ! command_exists npm; then
    if [[ "$(uname)" != "Darwin" ]] && command_exists apt-get; then
        install_package npm
    fi
fi

#──────────────────────────────────────────────
# 2. Emscripten SDK
#──────────────────────────────────────────────
if [ ! -d "$EMSDK_DIR" ]; then
    info "Cloning Emscripten SDK into $EMSDK_DIR …"
    git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
fi

if ! command_exists emcc; then
    info "Installing & activating latest Emscripten toolchain …"
    "$EMSDK_DIR/emsdk" install latest
    "$EMSDK_DIR/emsdk" activate latest
fi

# Source emsdk environment into this shell
# shellcheck disable=SC1091
EMSDK_QUIET=1 source "$EMSDK_DIR/emsdk_env.sh"

#──────────────────────────────────────────────
# 3. Build WASM (emcmake / emmake)
#──────────────────────────────────────────────
BUILD_DIR="$SCRIPT_DIR/build"
if [ ! -f "$BUILD_DIR/Makefile" ]; then
    info "Configuring CMake build …"
    mkdir -p "$BUILD_DIR"
    (cd "$BUILD_DIR" && emcmake cmake ..)
fi

info "Building WASM …"
(cd "$BUILD_DIR" && emmake make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)")

#──────────────────────────────────────────────
# 4. npm install
#──────────────────────────────────────────────
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    info "Installing npm dependencies …"
    npm install
fi

#──────────────────────────────────────────────
# 5. Create .env if missing
#──────────────────────────────────────────────
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    info "Creating default .env …"
    cat > "$SCRIPT_DIR/.env" <<'EOF'
ROM_PATH="rom/sonic2.bin"
PORT=9000
EOF
fi

#──────────────────────────────────────────────
# 6. Start dev server
#──────────────────────────────────────────────
info "Starting webpack-dev-server on http://localhost:$(grep PORT "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d '"') …"
npm run start
