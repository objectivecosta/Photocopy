#!/bin/bash

# Photocopy Python Bundle Build Script
# This script should be added as a "Run Script" build phase in Xcode

set -e

echo "🐍 Building Photocopy Python ML Bundle..."

# Configuration
PYTHON_VERSION="3.11"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_RESOURCES_DIR="$PROJECT_DIR/Photocopy/Resources/Python"
PYTHON_TARGET_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Python"
BUNDLE_DIR="$PYTHON_TARGET_DIR"

# Python.xcframework paths
PYTHON_FRAMEWORK_DIR="$PROJECT_DIR/Photocopy/Frameworks/Python.xcframework/macos-arm64_x86_64/Python.framework"
PYTHON_FRAMEWORK_BIN="$PYTHON_FRAMEWORK_DIR/bin/python3"

# Use a temporary venv directory that won't be included in the final bundle
VENV_DIR="$PROJECT_DIR/.build_python_venv"

# Debug: Print the paths
echo "🔍 Debug paths:"
echo "  PROJECT_DIR: $PROJECT_DIR"
echo "  TARGET_BUILD_DIR: $TARGET_BUILD_DIR"
echo "  UNLOCALIZED_RESOURCES_FOLDER_PATH: $UNLOCALIZED_RESOURCES_FOLDER_PATH"
echo "  PYTHON_RESOURCES_DIR: $PYTHON_RESOURCES_DIR"
echo "  PYTHON_TARGET_DIR: $PYTHON_TARGET_DIR"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "📦 Creating Python virtual environment using embedded framework..."
    if [ -f "$PYTHON_FRAMEWORK_BIN" ]; then
        "$PYTHON_FRAMEWORK_BIN" -m venv "$VENV_DIR"
    elif command -v python$PYTHON_VERSION &> /dev/null; then
        echo "⚠️ Python.xcframework not found, falling back to system python$PYTHON_VERSION"
        python$PYTHON_VERSION -m venv "$VENV_DIR"
    elif command -v python3 &> /dev/null; then
        echo "⚠️ Python.xcframework not found, falling back to system python3"
        python3 -m venv "$VENV_DIR"
    else
        echo "❌ Python 3.x not found and Python.xcframework not available."
        exit 1
    fi
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "⬆️ Upgrading pip..."
pip install --upgrade pip

# Create target directory and copy resources
echo "📁 Creating target directory..."
mkdir -p "$PYTHON_TARGET_DIR"
echo "📋 Copying Python resources..."
cp -R "$PYTHON_RESOURCES_DIR/"* "$PYTHON_TARGET_DIR/"

# Make executables executable
chmod +x $PYTHON_TARGET_DIR/photocopier.py
chmod +x $PYTHON_TARGET_DIR/photocopier

# Install requirements
echo "📚 Installing Python dependencies..."
if [ -f "$BUNDLE_DIR/requirements.txt" ]; then
    pip install -r "$BUNDLE_DIR/requirements.txt"
else
    echo "⚠️ requirements.txt not found, installing minimal dependencies"
    pip install "transformers>=4.51.1" "torch>=2.7.0" "accelerate>=1.10.0" "Pillow>=11.0.0"
fi

# Create lib directory and copy packages
echo "📋 Bundling Python packages..."
mkdir -p "$BUNDLE_DIR/lib"

echo $VENV_DIR

# Find the actual site-packages directory in the venv
PYTHON_SITE_PACKAGES=$(find "$VENV_DIR/lib" -name "site-packages" -type d | head -1)

if [ -n "$PYTHON_SITE_PACKAGES" ] && [ -d "$PYTHON_SITE_PACKAGES" ]; then
    cp -r "$PYTHON_SITE_PACKAGES/"* "$BUNDLE_DIR/lib/"
else
    echo "❌ Could not find Python site-packages directory in venv"
    exit 1
fi

# No cleanup - keep all packages to avoid dependency issues

# Contents
ls "$BUNDLE_DIR/lib"

# Make the Python script executable
echo "🔒 Making Python script executable..."
if [ -f "$BUNDLE_DIR/photocopier.py" ]; then
    chmod +x "$BUNDLE_DIR/photocopier.py"
else
    echo "⚠️ photocopier.py not found"
fi

if [ -f "$BUNDLE_DIR/photocopier" ]; then
    echo "🔒 Making launcher script executable..."
    chmod +x "$BUNDLE_DIR/photocopier"
else
    echo "⚠️ photocopier not found"
fi

echo "✅ Python bundle build completed!"

# Calculate bundle size
if command -v du &> /dev/null; then
    BUNDLE_SIZE=$(du -sh "$BUNDLE_DIR" | cut -f1)
    echo "📦 Bundle size: $BUNDLE_SIZE"
fi

# Test the bundle if requested
if [ "$1" = "--test" ]; then
    echo ""
    echo "🧪 Testing the bundle..."
    if [ -f "$BUNDLE_DIR/photocopier" ]; then
        if "$BUNDLE_DIR/photocopier" --mode health 2>/dev/null; then
            echo "✅ Bundle test successful!"
        else
            echo "⚠️ Bundle test failed - this is expected if PyTorch/MPS is not available in build environment"
        fi
    else
        echo "❌ Launcher script not found"
    fi
fi

# Clean up temporary venv
echo "🧹 Cleaning up temporary venv..."
rm -rf "$VENV_DIR"

echo ""
echo "📋 Bundle contents:"
ls -la "$BUNDLE_DIR" 2>/dev/null || echo "Could not list contents"
echo ""
echo "📋 Python bundle ready for Xcode build phase!"
