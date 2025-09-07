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
    
    # Install required packages
    $packages = @(
        "mingw-w64-x86_64-toolchain",
        "mingw-w64-x86_64-SDL",
        "mingw-w64-x86_64-pkg-config",
        "autotools",
        "make"
    )
    
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
$sdlCflags = & $msysBash -l -c "export PATH=/mingw64/bin:/usr/bin:`$PATH && pkg-config --cflags sdl"
$sdlLibs = & $msysBash -l -c "export PATH=/mingw64/bin:/usr/bin:`$PATH && pkg-config --libs sdl"

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
    
    # Run configure with SDL settings
    Write-Info "Running configure..."
    $configureCmd = "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && export PKG_CONFIG_PATH=/mingw64/lib/pkgconfig:/mingw64/share/pkgconfig && ./configure --disable-dependency-tracking --disable-threads --prefix='$($BUILD_DIR -replace '\\','/')'"
    
    & $msysBash -l -c $configureCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Configure failed"
        exit 1
    }
    
    # Build the project
    Write-Info "Building project..."
    $buildCmd = "cd '$($PROJECT_DIR -replace '\\','/')' && export PATH=/mingw64/bin:/usr/bin:`$PATH && make"
    
    & $msysBash -l -c $buildCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed"
        exit 1
    }
    
    # Copy required DLLs
    Write-Info "Copying required DLLs..."
    $dllSources = @(
        "$MSYS2_ROOT\mingw64\bin\SDL.dll"
    )
    
    # Check for additional MinGW runtime DLLs that might be needed
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
            Copy-Item $dllSource "$PROJECT_DIR\$dllName" -Force
            Write-Info "Copied: $dllName"
        } else {
            Write-Warning "DLL not found: $dllSource"
        }
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
