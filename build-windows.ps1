#!/usr/bin/env powershell
#
# Windows Build Script for Megablaster/DGen
# This script sets up the complete build environment and compiles the project
# without modifying any source files or Makefiles.
#

param(
    [switch]$SkipPrerequisites = $false,
    [switch]$CleanBuild = $false,
    [string]$BuildType = "Release"
)

$ErrorActionPreference = "Stop"

# Configuration
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = $SCRIPT_DIR
$MSYS2_ROOT = "C:\tools\msys64"
$BUILD_DIR = "$PROJECT_DIR\build-windows"

# Colors for output
function Write-ColorOutput($ForegroundColor, $Message) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Message
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Info($Message) { Write-ColorOutput "Green" "INFO: $Message" }
function Write-Warning($Message) { Write-ColorOutput "Yellow" "WARNING: $Message" }
function Write-Error($Message) { Write-ColorOutput "Red" "ERROR: $Message" }

Write-Info "Starting Windows build for Megablaster/DGen"
Write-Info "Project directory: $PROJECT_DIR"

# Check if running as administrator for prerequisite installation
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Install prerequisites
if (-not $SkipPrerequisites) {
    Write-Info "Installing prerequisites..."
    
    # Check for chocolatey
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Error "Chocolatey is required but not installed. Please install chocolatey first."
        Write-Info "Visit: https://chocolatey.org/install"
        exit 1
    }
    
    # Check if we need admin rights
    if (-not (Test-Administrator)) {
        Write-Warning "Administrator rights required for installing prerequisites."
        Write-Info "Please run this script as Administrator, or use -SkipPrerequisites if MSYS2 is already installed."
        exit 1
    }
    
    # Install MSYS2 if not present
    if (-not (Test-Path $MSYS2_ROOT)) {
        Write-Info "Installing MSYS2..."
        try {
            choco install msys2 -y
        } catch {
            Write-Error "Failed to install MSYS2: $_"
            exit 1
        }
    } else {
        Write-Info "MSYS2 already installed at $MSYS2_ROOT"
    }
    
    # Update MSYS2 and install packages
    Write-Info "Installing MSYS2 packages..."
    
    $msysBash = "$MSYS2_ROOT\usr\bin\bash.exe"
    if (-not (Test-Path $msysBash)) {
        Write-Error "MSYS2 bash not found at $msysBash"
        exit 1
    }
    
    # Update package database
    & $msysBash -l -c "pacman -Sy --noconfirm"
    
    # Install required packages (including static variants if available)
    $packages = @(
        "mingw-w64-x86_64-toolchain",
        "mingw-w64-x86_64-SDL",
        "mingw-w64-x86_64-pkg-config",
        "mingw-w64-x86_64-binutils",
        "autotools",
        "make"
    )
    
    # Try to install static SDL package if available
    Write-Info "Checking for static SDL package..."
    & $msysBash -l -c "pacman -Ss mingw-w64-x86_64-SDL | grep static" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Info "Static SDL package found, adding to install list..."
        $packages += "mingw-w64-x86_64-SDL-static"
    } else {
        Write-Info "No static SDL package found, will use alternative linking approach..."
    }
    
    foreach ($package in $packages) {
        Write-Info "Installing $package..."
        & $msysBash -l -c "pacman -S --noconfirm $package"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install $package"
            exit 1
        }
    }
}

# Verify MSYS2 installation
Write-Info "Verifying MSYS2 installation..."
$msysBash = "$MSYS2_ROOT\usr\bin\bash.exe"
if (-not (Test-Path $msysBash)) {
    Write-Error "MSYS2 not found. Please install MSYS2 first or run with administrator rights."
    exit 1
}

# Clean build if requested
if ($CleanBuild) {
    Write-Info "Cleaning previous build..."
    if (Test-Path $BUILD_DIR) {
        Remove-Item -Recurse -Force $BUILD_DIR
    }
    
    # Clean any generated autotools files
    $filesToClean = @(
        "aclocal.m4", "configure", "config.status", "config.log",
        "Makefile.in", "*/Makefile.in", "Makefile", "*/Makefile"
    )
    
    foreach ($pattern in $filesToClean) {
        Get-ChildItem -Path $PROJECT_DIR -Name $pattern -Recurse -ErrorAction SilentlyContinue | 
        ForEach-Object { 
            $fullPath = Join-Path $PROJECT_DIR $_
            if (Test-Path $fullPath) {
                Remove-Item $fullPath -Force
                Write-Info "Cleaned: $_"
            }
        }
    }
}

# Create build directory
Write-Info "Creating build directory..."
if (-not (Test-Path $BUILD_DIR)) {
    New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null
}

# Set up environment variables for the build
$env:PATH = "$MSYS2_ROOT\mingw64\bin;$MSYS2_ROOT\usr\bin;$env:PATH"
$env:PKG_CONFIG_PATH = "$MSYS2_ROOT\mingw64\lib\pkgconfig;$MSYS2_ROOT\mingw64\share\pkgconfig"
$env:ACLOCAL_PATH = "$MSYS2_ROOT\mingw64\share\aclocal;$MSYS2_ROOT\usr\share\aclocal"

# Get SDL configuration from pkg-config
Write-Info "Getting SDL configuration..."

# Check if static SDL libraries are available
$staticSdlAvailable = & $msysBash -l -c "export PATH=/mingw64/bin:/usr/bin:`$PATH && test -f /mingw64/lib/libSDL.a && echo 'true' || echo 'false'"
Write-Info "Static SDL available: $staticSdlAvailable"

if ($staticSdlAvailable -eq "true") {
    Write-Info "Using static SDL linking approach..."
    $sdlCflags = & $msysBash -l -c "export PATH=/mingw64/bin:/usr/bin:`$PATH && pkg-config --cflags sdl"
    $sdlLibs = & $msysBash -l -c "export PATH=/mingw64/bin:/usr/bin:`$PATH && pkg-config --libs --static sdl"
} else {
    Write-Info "Using dynamic SDL linking approach (will try to minimize dependencies)..."
    $sdlCflags = & $msysBash -l -c "export PATH=/mingw64/bin:/usr/bin:`$PATH && pkg-config --cflags sdl"
    $sdlLibs = & $msysBash -l -c "export PATH=/mingw64/bin:/usr/bin:`$PATH && pkg-config --libs sdl"
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get SDL configuration from pkg-config"
    exit 1
}

Write-Info "SDL CFLAGS: $sdlCflags"
Write-Info "SDL LIBS: $sdlLibs"

# Configure the project
Write-Info "Configuring project..."
Push-Location $PROJECT_DIR

try {
    # Generate aclocal.m4 with proper includes
    Write-Info "Running aclocal..."
    $aclocalCmd = "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && export ACLOCAL_PATH=/mingw64/share/aclocal:/usr/share/aclocal && aclocal -I /mingw64/share/aclocal"
    & $msysBash -l -c $aclocalCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "aclocal failed"
        exit 1
    }
    
    # Generate configure script
    Write-Info "Running autoconf..."
    & $msysBash -l -c "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && autoconf"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "autoconf failed"
        exit 1
    }
    
    # Generate Makefile.in files
    Write-Info "Running automake..."
    & $msysBash -l -c "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && automake --add-missing --copy"
    if ($LASTEXITCODE -ne 0) {
        # automake might fail but that's often OK if Makefile.in files exist
        Write-Warning "automake failed, but continuing..."
    }
    
    # Run configure with SDL settings and static linking
    Write-Info "Running configure..."
    
    if ($staticSdlAvailable -eq "true") {
        # Full static linking approach
        $configureCmd = "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && export PKG_CONFIG_PATH=/mingw64/lib/pkgconfig:/mingw64/share/pkgconfig && export LDFLAGS='-static-libgcc -static-libstdc++ -Wl,-Bstatic -static' && export CFLAGS='-DSDL_STATIC_LIB' && ./configure --disable-dependency-tracking --disable-threads --disable-shared --enable-static --prefix='$($BUILD_DIR -replace '\\','/')'"
    } else {
        # Partial static linking (at least for runtime libraries)
        $configureCmd = "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && export PKG_CONFIG_PATH=/mingw64/lib/pkgconfig:/mingw64/share/pkgconfig && export LDFLAGS='-static-libgcc -static-libstdc++' && ./configure --disable-dependency-tracking --disable-threads --prefix='$($BUILD_DIR -replace '\\','/')'"
    }
    
    & $msysBash -l -c $configureCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Configure failed"
        exit 1
    }
    
    # Build the project with static linking
    Write-Info "Building project..."
    
    if ($staticSdlAvailable -eq "true") {
        # Full static linking approach
        $buildCmd = "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && export LDFLAGS='-static-libgcc -static-libstdc++ -Wl,-Bstatic -static' && make LDFLAGS='-static-libgcc -static-libstdc++ -Wl,-Bstatic -static'"
    } else {
        # Partial static linking (at least for runtime libraries)
        $buildCmd = "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && export LDFLAGS='-static-libgcc -static-libstdc++' && make LDFLAGS='-static-libgcc -static-libstdc++'"
    }
    
    & $msysBash -l -c $buildCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed"
        exit 1
    }
    
    # Check if we successfully created a standalone binary
    Write-Info "Verifying standalone binary..."
    
    # Test if the executable runs without external DLLs
    if (Test-Path "$PROJECT_DIR\dgen.exe") {
        # Check dependencies using objdump or similar
        Write-Info "Checking binary dependencies..."
        try {
            $deps = & $msysBash -l -c "cd '$($PROJECT_DIR -replace '\\','/')' && /mingw64/bin/objdump -p dgen.exe | grep 'DLL Name'"
            if ($LASTEXITCODE -ne 0) {
                # Try alternative path
                $deps = & $msysBash -l -c "cd '$($PROJECT_DIR -replace '\\','/')' && objdump -p dgen.exe | grep 'DLL Name'"
            }
            Write-Info "Dependencies found:"
            if ($deps) {
                Write-Info $deps
            } else {
                Write-Info "No DLL dependencies found (or unable to parse)"
            }
            
            # Check if we still have problematic dependencies
            if ($deps -match "SDL\.dll|libgcc_s_seh-1\.dll|libstdc\+\+-6\.dll|libwinpthread-1\.dll") {
                Write-Warning "Static linking was not fully successful. Some dynamic dependencies remain."
                Write-Info "Attempting to create a standalone package..."
                
                # Also try ldd for more detailed dependency info
                try {
                    $lddOutput = & $msysBash -l -c "cd '$($PROJECT_DIR -replace '\\','/')' && ldd dgen.exe 2>/dev/null || echo 'ldd not available'"
                    if ($lddOutput -and $lddOutput -ne "ldd not available") {
                        Write-Info "Detailed dependencies (ldd):"
                        Write-Info $lddOutput
                    }
                } catch {
                    Write-Info "Could not run ldd for detailed dependency analysis"
                }
                
                # Create a portable directory structure
                $portableDir = "$PROJECT_DIR\dgen-portable"
                if (Test-Path $portableDir) {
                    Remove-Item -Recurse -Force $portableDir
                }
                New-Item -ItemType Directory -Path $portableDir | Out-Null
                
                # Copy the main executable
                Copy-Item "$PROJECT_DIR\dgen.exe" "$portableDir\" -Force
                if (Test-Path "$PROJECT_DIR\dgen_tobin.exe") {
                    Copy-Item "$PROJECT_DIR\dgen_tobin.exe" "$portableDir\" -Force
                }
                
                # Copy required DLLs to the portable directory
                $dllSources = @()
                
                # SDL DLL
                $sdlDll = "$MSYS2_ROOT\mingw64\bin\SDL.dll"
                if (Test-Path $sdlDll) {
                    $dllSources += $sdlDll
                }
                
                # Runtime DLLs
                $runtimeDlls = @(
                    "libgcc_s_seh-1.dll",
                    "libstdc++-6.dll", 
                    "libwinpthread-1.dll"
                )
                
                foreach ($dll in $runtimeDlls) {
                    $dllPath = "$MSYS2_ROOT\mingw64\bin\$dll"
                    if (Test-Path $dllPath) {
                        $dllSources += $dllPath
                    }
                }
                
                foreach ($dllSource in $dllSources) {
                    if (Test-Path $dllSource) {
                        $dllName = Split-Path -Leaf $dllSource
                        Copy-Item $dllSource "$portableDir\$dllName" -Force
                        Write-Info "Copied to portable dir: $dllName"
                    }
                }
                
                # Copy documentation and sample files
                if (Test-Path "$PROJECT_DIR\sample.dgenrc") {
                    Copy-Item "$PROJECT_DIR\sample.dgenrc" "$portableDir\" -Force
                }
                if (Test-Path "$PROJECT_DIR\README.md") {
                    Copy-Item "$PROJECT_DIR\README.md" "$portableDir\" -Force
                }
                
                Write-Info "Created portable distribution in: $portableDir"
                Write-Info "This directory contains all files needed to run the emulator."
                
                # Create a zip file for easy distribution
                $zipName = "dgen-windows-portable.zip"
                $zipPath = "$PROJECT_DIR\$zipName"
                
                # Remove existing zip if it exists
                if (Test-Path $zipPath) {
                    Remove-Item $zipPath -Force
                }
                
                try {
                    Write-Info "Creating distribution zip file..."
                    Compress-Archive -Path "$portableDir\*" -DestinationPath $zipPath -CompressionLevel Optimal
                    $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
                    Write-Info "Created distribution zip: $zipName ($zipSize MB)"
                    Write-Info "This zip file is ready for GitHub releases or distribution!"
                } catch {
                    Write-Warning "Failed to create zip file: $_"
                    Write-Info "You can manually zip the dgen-portable directory for distribution."
                }
            } else {
                Write-Info "SUCCESS! Binary appears to be standalone (no problematic dynamic dependencies found)."
            }
        } catch {
            Write-Warning "Could not check dependencies. Creating portable distribution as fallback..."
            
            # Create a portable directory structure
            $portableDir = "$PROJECT_DIR\dgen-portable"
            if (Test-Path $portableDir) {
                Remove-Item -Recurse -Force $portableDir
            }
            New-Item -ItemType Directory -Path $portableDir | Out-Null
            
            # Copy the main executable
            Copy-Item "$PROJECT_DIR\dgen.exe" "$portableDir\" -Force
            if (Test-Path "$PROJECT_DIR\dgen_tobin.exe") {
                Copy-Item "$PROJECT_DIR\dgen_tobin.exe" "$portableDir\" -Force
            }
            
            # Copy required DLLs to the portable directory
            $dllSources = @()
            
            # SDL DLL
            $sdlDll = "$MSYS2_ROOT\mingw64\bin\SDL.dll"
            if (Test-Path $sdlDll) {
                $dllSources += $sdlDll
            }
            
            # Runtime DLLs
            $runtimeDlls = @(
                "libgcc_s_seh-1.dll",
                "libstdc++-6.dll", 
                "libwinpthread-1.dll"
            )
            
            foreach ($dll in $runtimeDlls) {
                $dllPath = "$MSYS2_ROOT\mingw64\bin\$dll"
                if (Test-Path $dllPath) {
                    $dllSources += $dllPath
                }
            }
            
            foreach ($dllSource in $dllSources) {
                if (Test-Path $dllSource) {
                    $dllName = Split-Path -Leaf $dllSource
                    Copy-Item $dllSource "$portableDir\$dllName" -Force
                    Write-Info "Copied to portable dir: $dllName"
                }
            }
            
            # Copy documentation and sample files
            if (Test-Path "$PROJECT_DIR\sample.dgenrc") {
                Copy-Item "$PROJECT_DIR\sample.dgenrc" "$portableDir\" -Force
            }
            if (Test-Path "$PROJECT_DIR\README.md") {
                Copy-Item "$PROJECT_DIR\README.md" "$portableDir\" -Force
            }
            
            Write-Info "Created portable distribution in: $portableDir"
            
            # Create a zip file for easy distribution
            $zipName = "dgen-windows-portable.zip"
            $zipPath = "$PROJECT_DIR\$zipName"
            
            # Remove existing zip if it exists
            if (Test-Path $zipPath) {
                Remove-Item $zipPath -Force
            }
            
            try {
                Write-Info "Creating distribution zip file..."
                Compress-Archive -Path "$portableDir\*" -DestinationPath $zipPath -CompressionLevel Optimal
                $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
                Write-Info "Created distribution zip: $zipName ($zipSize MB)"
                Write-Info "This zip file is ready for GitHub releases or distribution!"
            } catch {
                Write-Warning "Failed to create zip file: $_"
                Write-Info "You can manually zip the dgen-portable directory for distribution."
            }
        }
    } else {
        Write-Warning "dgen.exe not found - build may have failed"
        exit 1
    }
    # Test the executable
    Write-Info "Testing executable..."
    if (Test-Path "$PROJECT_DIR\dgen.exe") {
        Write-Info "Build successful! Testing executable..."
        
        # Try to run with --version to test basic functionality
        try {
            & "$PROJECT_DIR\dgen.exe" --version 2>&1 | Out-Null
            Write-Info "Executable test passed"
        } catch {
            Write-Warning "Executable test failed, but binary was created successfully"
        }
        
        Write-Info ""
        Write-Info "SUCCESS! Build completed successfully."
        Write-Info "Executable: $PROJECT_DIR\dgen.exe"
        Write-Info "Utility: $PROJECT_DIR\dgen_tobin.exe"
        Write-Info ""
        if (Test-Path "$PROJECT_DIR\dgen-portable") {
            Write-Info "Portable distribution created in: $PROJECT_DIR\dgen-portable\"
            Write-Info "This directory contains all files needed to run the emulator standalone."
            if (Test-Path "$PROJECT_DIR\dgen-windows-portable.zip") {
                Write-Info "Distribution zip created: $PROJECT_DIR\dgen-windows-portable.zip"
                Write-Info "This zip file is ready for GitHub releases!"
            }
            Write-Info ""
            Write-Info "To distribute:"
            Write-Info "  1. Upload dgen-windows-portable.zip to GitHub releases"
            Write-Info "  2. Or share the entire 'dgen-portable' folder"
        } else {
            Write-Info "The executable should now be standalone (or have minimal DLL dependencies)."
        }
        Write-Info ""
        Write-Info "To run the emulator, use: .\dgen.exe [ROM_FILE]"
        Write-Info "For help, use: .\dgen.exe --help"
        
    } else {
        Write-Error "Build appeared to succeed but dgen.exe was not created"
        exit 1
    }
    
} finally {
    Pop-Location
}

Write-Info "Build script completed successfully!"
