# ChaosDrive Web

A fork of [wasm-genplus](https://github.com/h1romas4/wasm-genplus) customized to apply Chaos Drive hacks to the Genesis-Plus-GX emulator.

## About This Fork

This is a customized version of the wasm-genplus WebAssembly port of Genesis-Plus-GX, enhanced with Chaos Drive hacks for enhanced gameplay and compatibility.

## Quick Start

### Run Locally

```bash
./run.sh
```

This will:
1. Set up your environment (Emscripten SDK if needed)
2. Build the project
3. Start a local development server

Then open http://localhost:9000 in your browser.

### Deploy to Netlify

```bash
./deploy.sh
```

This script handles the full build and deployment process to Netlify.

## Manual Build

See [README-original.md](README-original.md) for detailed build instructions from the original wasm-genplus project.

### Requirements

- [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)
- Node.js and npm

### Build Steps

```bash
# Emscripten compilation
mkdir build && cd build
emcmake cmake ..
emmake make

# Webpack bundling
cd ..
npm install
npm run start
```

## Configuration

Set ROM path and port in `.env`:

```
ROM_PATH="rom/sonic2.bin"
PORT=9000
```

## Credits

- Original project: [wasm-genplus](https://github.com/h1romas4/wasm-genplus) by h1romas4
- Emulator: [Genesis-Plus-GX](https://github.com/ekeeke/Genesis-Plus-GX)
- Chaos Drive hacks customization

## License

[Genesis-Plus-GX](https://github.com/ekeeke/Genesis-Plus-GX/blob/master/LICENSE.txt) License
