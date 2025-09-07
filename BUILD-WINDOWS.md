# Windows Build Instructions for Megablaster/DGen

This directory contains automated build scripts for compiling Megablaster/DGen on Windows without modifying any source files or Makefiles.

## Quick Start

### Option 1: PowerShell Script (Recommended)
```powershell
# Run as Administrator for first-time setup
.\build-windows.ps1
```

### Option 2: Bash Script (for Git Bash/MSYS2 users)
```bash
# Run in Git Bash or MSYS2
./build-windows.sh
```

## Prerequisites

The scripts will automatically install prerequisites, but you need:

1. **Windows 10/11**
2. **Chocolatey** (for PowerShell script): https://chocolatey.org/install
3. **Administrator rights** (for first-time setup only)

## Script Options

### PowerShell Script (`build-windows.ps1`)
```powershell
# Full build with prerequisite installation (requires admin)
.\build-windows.ps1

# Skip prerequisite installation (if MSYS2 already installed)
.\build-windows.ps1 -SkipPrerequisites

# Clean build (removes previous build artifacts)
.\build-windows.ps1 -CleanBuild

# Both options together
.\build-windows.ps1 -SkipPrerequisites -CleanBuild
```

### Bash Script (`build-windows.sh`)
```bash
# Full build with prerequisite installation
./build-windows.sh

# Skip prerequisite installation
./build-windows.sh --skip-prereqs

# Clean build
./build-windows.sh --clean

# Show help
./build-windows.sh --help
```

## What the Scripts Do

1. **Install MSYS2** (if not already present)
2. **Install required packages**:
   - MinGW-w64 toolchain (GCC, make, etc.)
   - SDL 1.2 development libraries
   - pkg-config
   - autotools (autoconf, automake, libtool)
3. **Configure the project** using autotools with proper SDL paths
4. **Build the project** using make
5. **Copy required DLLs** to the project directory
6. **Test the executable** to ensure it works

## Output

After successful compilation, you'll have:
- `dgen.exe` - The main emulator executable
- `dgen_tobin.exe` - ROM conversion utility
- `SDL.dll` and other required DLLs

## Usage

```bash
# Run the emulator with a ROM file
./dgen.exe path/to/your/rom.md

# Show help and options
./dgen.exe --help

# Show version information
./dgen.exe --version
```

## Troubleshooting

### "Access Denied" or Permission Errors
- Run PowerShell as Administrator for first-time setup
- Or use `-SkipPrerequisites` if MSYS2 is already installed

### "MSYS2 not found"
- Ensure chocolatey is installed: https://chocolatey.org/install
- Run the script as Administrator to install MSYS2

### "Build failed"
- Try running with `-CleanBuild` option
- Check that all prerequisites are installed correctly
- Ensure you have internet connection for package downloads

### "SDL.dll not found" when running dgen.exe
- The build script should copy SDL.dll automatically
- If missing, manually copy from `C:\tools\msys64\mingw64\bin\SDL.dll`

## Architecture Notes

These scripts use the **MSYS2 MinGW64** environment, which provides:
- 64-bit GCC compiler
- 64-bit SDL 1.2 libraries
- Proper Windows compatibility
- All required development tools

The scripts do **NOT** modify any source files or Makefiles, ensuring cross-platform compatibility is maintained.

## Advanced Usage

### Custom MSYS2 Installation Path
Edit the scripts and change the `MSYS2_ROOT` variable if you have MSYS2 installed in a different location.

### Development Builds
For development, you can use the bash script in an MSYS2 terminal for faster incremental builds:
```bash
# In MSYS2 MinGW64 terminal
export PATH="/mingw64/bin:/usr/bin:$PATH"
./configure --disable-dependency-tracking --disable-threads
make
```

## Dependencies Installed

The scripts install these MSYS2 packages:
- `mingw-w64-x86_64-toolchain` - Complete GCC toolchain
- `mingw-w64-x86_64-SDL` - SDL 1.2 library
- `mingw-w64-x86_64-pkg-config` - Package configuration tool
- `autotools` - autoconf, automake, libtool
- `make` - GNU Make

All packages are installed in the MSYS2 environment and don't interfere with other Windows software.
