#!/bin/bash
# Builds projectservice-xmp for iOS device + iOS Simulator (arm64 + x86_64)
# and packages them as artifacts/XMPToolkit.xcframework, which is checked
# into the repo and consumed by Package.swift via .binaryTarget.
#
# Run this whenever rust-xmp/ changes.

set -euo pipefail

cd "$(dirname "$0")/.."

CRATE_DIR="rust-xmp"
ARTIFACT_NAME="XMPToolkit"
OUT_DIR="artifacts"
LIB_NAME="libprojectservice_xmp.a"
CARGO="${CARGO:-$HOME/.cargo/bin/cargo}"

echo "==> Building for iOS device (aarch64-apple-ios)"
(cd "$CRATE_DIR" && "$CARGO" build --release --target aarch64-apple-ios)

echo "==> Building for iOS Simulator (aarch64-apple-ios-sim)"
(cd "$CRATE_DIR" && "$CARGO" build --release --target aarch64-apple-ios-sim)

echo "==> Building for iOS Simulator (x86_64-apple-ios)"
(cd "$CRATE_DIR" && "$CARGO" build --release --target x86_64-apple-ios)

DEVICE_LIB="$CRATE_DIR/target/aarch64-apple-ios/release/$LIB_NAME"
SIM_ARM64_LIB="$CRATE_DIR/target/aarch64-apple-ios-sim/release/$LIB_NAME"
SIM_X86_64_LIB="$CRATE_DIR/target/x86_64-apple-ios/release/$LIB_NAME"

FAT_SIM_DIR="$CRATE_DIR/target/sim-fat"
mkdir -p "$FAT_SIM_DIR"
FAT_SIM_LIB="$FAT_SIM_DIR/$LIB_NAME"

echo "==> Combining simulator slices into a fat library"
lipo -create "$SIM_ARM64_LIB" "$SIM_X86_64_LIB" -output "$FAT_SIM_LIB"

echo "==> Packaging XCFramework"
rm -rf "$OUT_DIR/$ARTIFACT_NAME.xcframework"
mkdir -p "$OUT_DIR"
xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" -headers "$CRATE_DIR/include" \
  -library "$FAT_SIM_LIB" -headers "$CRATE_DIR/include" \
  -output "$OUT_DIR/$ARTIFACT_NAME.xcframework"

echo "==> Done."
echo "    Artifact: $OUT_DIR/$ARTIFACT_NAME.xcframework"
