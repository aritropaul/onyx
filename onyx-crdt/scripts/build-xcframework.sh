#!/bin/bash
set -euo pipefail

# Build script for OnyxCRDTFFI.xcframework
# Produces a universal macOS framework with Swift bindings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$(dirname "$PROJECT_DIR")"

# Output directories
BUILD_DIR="$PROJECT_DIR/build"
GENERATED_DIR="$PROJECT_DIR/generated"
FRAMEWORK_NAME="OnyxCRDTFFI"
XCFRAMEWORK_DIR="$PROJECT_DIR/$FRAMEWORK_NAME.xcframework"

echo "==> Cleaning previous build artifacts..."
rm -rf "$BUILD_DIR"
rm -rf "$GENERATED_DIR"
rm -rf "$XCFRAMEWORK_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$GENERATED_DIR"

# Step 1: Build for both macOS architectures
echo "==> Building for aarch64-apple-darwin..."
cargo build --release --target aarch64-apple-darwin -p onyx-crdt --manifest-path "$WORKSPACE_DIR/Cargo.toml"

echo "==> Building for x86_64-apple-darwin..."
cargo build --release --target x86_64-apple-darwin -p onyx-crdt --manifest-path "$WORKSPACE_DIR/Cargo.toml"

# Step 2: Create universal binary with lipo
echo "==> Creating universal binary with lipo..."
AARCH64_LIB="$WORKSPACE_DIR/target/aarch64-apple-darwin/release/libonyx_crdt.a"
X86_64_LIB="$WORKSPACE_DIR/target/x86_64-apple-darwin/release/libonyx_crdt.a"
UNIVERSAL_LIB="$BUILD_DIR/libonyx_crdt.a"

lipo -create "$AARCH64_LIB" "$X86_64_LIB" -output "$UNIVERSAL_LIB"

echo "==> Universal binary created at $UNIVERSAL_LIB"
lipo -info "$UNIVERSAL_LIB"

# Step 3: Generate Swift bindings with uniffi-bindgen
echo "==> Generating Swift bindings..."
cargo run --release --bin uniffi-bindgen -p onyx-crdt --manifest-path "$WORKSPACE_DIR/Cargo.toml" -- \
    generate "$PROJECT_DIR/uniffi/onyx_crdt.udl" \
    --language swift \
    --out-dir "$GENERATED_DIR"

# Step 4: Create xcframework directory structure
echo "==> Packaging into $FRAMEWORK_NAME.xcframework..."

MACOS_DIR="$XCFRAMEWORK_DIR/macos-arm64_x86_64"
HEADERS_DIR="$MACOS_DIR/Headers"
MODULES_DIR="$MACOS_DIR/Modules"

mkdir -p "$HEADERS_DIR"
mkdir -p "$MODULES_DIR"

# Copy the universal static library
cp "$UNIVERSAL_LIB" "$MACOS_DIR/libonyx_crdt.a"

# Copy the generated C header
cp "$GENERATED_DIR/onyx_crdtFFI.h" "$HEADERS_DIR/"

# Create module.modulemap
cat > "$MODULES_DIR/module.modulemap" << 'MODULEMAP'
module OnyxCRDTFFI {
    header "../Headers/onyx_crdtFFI.h"
    export *
}
MODULEMAP

# Create Info.plist for the xcframework
cat > "$XCFRAMEWORK_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>LibraryIdentifier</key>
            <string>macos-arm64_x86_64</string>
            <key>LibraryPath</key>
            <string>libonyx_crdt.a</string>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>x86_64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>macos</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

echo ""
echo "==> Build complete!"
echo "    XCFramework: $XCFRAMEWORK_DIR"
echo "    Swift file:  $GENERATED_DIR/onyx_crdt.swift"
echo ""
echo "To use in your Swift project:"
echo "  1. Add $XCFRAMEWORK_DIR to your Xcode project (Frameworks, Libraries, and Embedded Content)"
echo "  2. Add $GENERATED_DIR/onyx_crdt.swift to your Swift sources"
