# Building DGen/SDL on macOS

This document provides step-by-step instructions for building DGen/SDL on macOS, specifically tested on Apple Silicon (arm64) machines running macOS Sequoia.

## Prerequisites

### Required Tools

You'll need the following tools installed:

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required build tools and dependencies
brew install autoconf automake libtool pkg-config sdl12-compat
```

### Dependencies Breakdown

- **autoconf, automake, libtool**: GNU Autotools for generating the build system
- **pkg-config**: Tool for managing library compile and link flags
- **sdl12-compat**: SDL 1.2 compatibility layer that uses SDL 2.0 behind the scenes

## Known Issues on Apple Silicon

This project was originally designed for Intel (x86_64) architecture. On Apple Silicon Macs, we need to build using Rosetta 2 (Intel emulation) to work with the available SDL libraries.

## Build Steps

### 1. Generate the Build System

```bash
./autogen.sh
```

This will generate the `configure` script and other autotools files. You may see some warnings about obsolete macros - these are expected and don't affect the build.

### 2. Fix C++11 Compatibility Issues

The source code needs minor fixes for modern C++ compilers. The main issue is with string literal concatenation that requires spaces between literals and macros.

If you encounter compilation errors about "invalid suffix on literal", you'll need to edit `main.cpp`:

- Change `"DGen/SDL v"VER"\n"` to `"DGen/SDL v" VER "\n"`
- Change `"DGen/SDL version "VER"\n"` to `"DGen/SDL version " VER "\n"`

### 3. Configure the Build

Use the following configure command with explicit SDL library configuration:

```bash
SDL_LIBS="-L/usr/local/lib -lSDLmain -lSDL -Wl,-framework,Cocoa" arch -x86_64 ./configure
```

Key points:

- `SDL_LIBS` explicitly specifies the correct SDL libraries and linking order
- `arch -x86_64` forces the configure script to run in Intel emulation mode
- The order `-lSDLmain -lSDL` is important for proper linking

### 4. Build the Binary

```bash
arch -x86_64 make
```

Again, we use `arch -x86_64` to ensure the build process runs in Intel emulation mode to match the SDL library architecture.

## Build Output

The build process will create two binaries:

- **`dgen`**: The main Genesis/MegaDrive emulator (approximately 2.9MB)
- **`dgen_tobin`**: A utility for converting ROM files (approximately 25KB)

## Testing the Build

Test that the main binary works:

```bash
./dgen -v
```

This should display the version information and confirm the build was successful.

## Architecture Notes

The configure script will report the following features as available:

- **Front-end**: Joystick support, Multi-threading, Crap TV filters, hqx filters, scale2x filters
- **CPU cores**: Musashi M68K, MZ80, CZ80
- **Missing features**: OpenGL, Compressed ROMs, Debugger, ASM optimizations (not available on Apple Silicon)

## Troubleshooting

### Common Issues

1. **Architecture mismatch errors**: Ensure you're using `arch -x86_64` for both configure and make
2. **SDL library not found**: Make sure `sdl12-compat` is installed via Homebrew
3. **Missing main symbol**: Ensure `-lSDLmain` comes before `-lSDL` in the SDL_LIBS configuration
4. **C++11 string literal errors**: Apply the string literal fixes mentioned in step 2

### Build Warnings

The following warnings are expected and don't affect functionality:

- Warnings about `abs()` on unsigned integers in the hqx filter code
- Autotools warnings about obsolete macros
- ld warnings about ignoring x86_64 files when architecture mismatches occur

## Alternative Installation

If building from source proves problematic, consider:

- Using a pre-built binary for macOS
- Building in a Docker container with x86_64 emulation
- Using other Genesis/MegaDrive emulators with better Apple Silicon support

## Build Environment

This build process was tested on:

- **OS**: macOS Sequoia (Darwin 24.6.0)
- **Hardware**: Apple Silicon (arm64)
- **Homebrew**: Intel installation at `/usr/local`
- **Compiler**: Clang (Apple clang version based on LLVM)

## Files Created

After a successful build, you'll have:

- `dgen` - Main emulator binary
- `dgen_tobin` - ROM conversion utility
- Various object files and libraries in subdirectories

The binaries are ready to use immediately - no installation step is required.
