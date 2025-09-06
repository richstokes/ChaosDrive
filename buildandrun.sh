#!/bin/bash

# buildandrun.sh - Build and optionally run DGen/SDL on macOS
# This script automates the build process for DGen/SDL on Apple Silicon Macs

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check and install dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check for Homebrew
    if ! command_exists brew; then
        print_error "Homebrew not found. Please install Homebrew first:"
        echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
    
    # Check for required tools
    local missing_deps=()
    for dep in autoconf automake libtool pkg-config; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    # Check for SDL12-compat
    if ! pkg-config --exists sdl; then
        missing_deps+=("sdl12-compat")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        print_status "Installing missing dependencies..."
        brew install "${missing_deps[@]}"
    else
        print_success "All dependencies are installed"
    fi
}

# Function to apply source code fixes
apply_source_fixes() {
    print_status "Checking for required source code fixes..."
    
    if grep -q '"DGen/SDL v"VER"' main.cpp 2>/dev/null; then
        print_status "Applying C++11 string literal fixes to main.cpp..."
        
        # Fix first occurrence
        sed -i '' 's/"DGen\/SDL v"VER"/"DGen\/SDL v" VER "/g' main.cpp
        
        # Fix second occurrence
        sed -i '' 's/"DGen\/SDL version "VER"/"DGen\/SDL version " VER "/g' main.cpp
        
        print_success "Source code fixes applied"
    else
        print_status "Source code fixes already applied or not needed"
    fi
}

# Function to generate build system
generate_build_system() {
    print_status "Generating build system with autogen.sh..."
    
    if [ ! -f "./autogen.sh" ]; then
        print_error "autogen.sh not found. Are you in the correct directory?"
        exit 1
    fi
    
    ./autogen.sh
    print_success "Build system generated"
}

# Function to configure the build
configure_build() {
    print_status "Configuring build for Apple Silicon with SDL compatibility..."
    
    # Use x86_64 architecture for compatibility with SDL libraries
    SDL_LIBS="-L/usr/local/lib -lSDLmain -lSDL -Wl,-framework,Cocoa" arch -x86_64 ./configure
    
    print_success "Build configured successfully"
}

# Function to build the project
build_project() {
    print_status "Building DGen/SDL..."
    print_warning "Building with x86_64 architecture for SDL compatibility..."
    
    # Clean any previous build
    if [ -f "Makefile" ]; then
        make clean >/dev/null 2>&1 || true
    fi
    
    # Build with x86_64 architecture
    arch -x86_64 make
    
    print_success "Build completed successfully!"
}

# Function to verify build
verify_build() {
    print_status "Verifying build..."
    
    if [ -f "./dgen" ] && [ -x "./dgen" ]; then
        print_success "Main binary 'dgen' created successfully"
        
        # Get file size
        local size=$(ls -lh ./dgen | awk '{print $5}')
        print_status "Binary size: $size"
        
        # Test version
        print_status "Testing binary..."
        if ./dgen -v >/dev/null 2>&1; then
            print_success "Binary is functional"
        else
            print_warning "Binary created but version test failed"
        fi
    else
        print_error "Main binary 'dgen' not found or not executable"
        exit 1
    fi
    
    if [ -f "./dgen_tobin" ] && [ -x "./dgen_tobin" ]; then
        print_success "Utility binary 'dgen_tobin' created successfully"
    else
        print_warning "Utility binary 'dgen_tobin' not found"
    fi
}

# Function to run the emulator
run_emulator() {
    local rom_file="$1"
    
    if [ -n "$rom_file" ]; then
        if [ ! -f "$rom_file" ]; then
            print_error "ROM file not found: $rom_file"
            exit 1
        fi
        
        print_status "Running DGen/SDL with ROM: $rom_file"
        ./dgen "$rom_file"
    else
        print_status "Running DGen/SDL without ROM (will show help/config)"
        ./dgen
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [ROM_FILE]"
    echo ""
    echo "Build and optionally run DGen/SDL on macOS"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help              Show this help message"
    echo "  -b, --build-only        Only build, don't run"
    echo "  -r, --run-only          Only run (skip build), requires existing binary"
    echo "  -f, --force-rebuild     Force complete rebuild (clean first)"
    echo "  -c, --check-deps        Only check and install dependencies"
    echo "  -v, --verbose           Verbose output"
    echo ""
    echo "ROM_FILE:"
    echo "  Optional path to a Genesis/MegaDrive ROM file to run"
    echo ""
    echo "Examples:"
    echo "  $0                      # Build and run without ROM"
    echo "  $0 game.md              # Build and run with ROM file"
    echo "  $0 -b                   # Build only"
    echo "  $0 -r game.md           # Run only with ROM"
    echo "  $0 -f                   # Force complete rebuild"
}

# Main script logic
main() {
    local build_only=false
    local run_only=false
    local force_rebuild=false
    local check_deps_only=false
    local verbose=false
    local rom_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -b|--build-only)
                build_only=true
                shift
                ;;
            -r|--run-only)
                run_only=true
                shift
                ;;
            -f|--force-rebuild)
                force_rebuild=true
                shift
                ;;
            -c|--check-deps)
                check_deps_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                set -x  # Enable verbose mode
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                rom_file="$1"
                shift
                ;;
        esac
    done
    
    print_status "DGen/SDL Build and Run Script for macOS"
    print_status "========================================"
    
    # Check dependencies
    check_dependencies
    
    if [ "$check_deps_only" = true ]; then
        print_success "Dependency check completed"
        exit 0
    fi
    
    # If run-only mode, skip build process
    if [ "$run_only" = true ]; then
        if [ ! -f "./dgen" ]; then
            print_error "No existing binary found. Build first or remove --run-only flag."
            exit 1
        fi
        run_emulator "$rom_file"
        exit 0
    fi
    
    # Build process
    apply_source_fixes
    generate_build_system
    configure_build
    
    if [ "$force_rebuild" = true ]; then
        print_status "Force rebuild requested, cleaning previous build..."
        make clean >/dev/null 2>&1 || true
    fi
    
    build_project
    verify_build
    
    print_success "Build process completed successfully!"
    
    # Run if not build-only mode
    if [ "$build_only" = false ]; then
        echo ""
        run_emulator "$rom_file"
    else
        print_status "Build-only mode completed. Use './dgen [ROM_FILE]' to run."
    fi
}

# Check if we're in the right directory
if [ ! -f "main.cpp" ] || [ ! -f "autogen.sh" ]; then
    print_error "This script must be run from the DGen/SDL source directory"
    print_error "Make sure you're in the directory containing main.cpp and autogen.sh"
    exit 1
fi

# Run main function with all arguments
main "$@"
