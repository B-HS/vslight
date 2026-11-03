#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER_DIR="$ROOT_DIR/Driver"
VENDOR_DIR="$DRIVER_DIR/vendor/libASPL"
BUILD_DIR="$DRIVER_DIR/build"
OBJ_DIR="$BUILD_DIR/obj"
BUNDLE="$BUILD_DIR/VSLightAudioDriver.driver"
LIBASPL_COMMIT="633e0f70203edd87d320fc5a3cae901e1363aac5"
ARCH="${ARCH:-arm64}"
CXX="${CXX:-clang++}"

if [ ! -d "$VENDOR_DIR/.git" ]; then
  mkdir -p "$(dirname "$VENDOR_DIR")"
  git clone https://github.com/gavv/libASPL.git "$VENDOR_DIR"
  git -C "$VENDOR_DIR" checkout "$LIBASPL_COMMIT"
fi

rm -rf "$OBJ_DIR" "$BUNDLE"
mkdir -p "$OBJ_DIR" "$BUNDLE/Contents/MacOS"

CXXFLAGS=(
  -std=c++17
  -O2
  -fPIC
  -arch "$ARCH"
  -mmacosx-version-min=27.0
  -I"$VENDOR_DIR/include"
)

echo "==> Compiling libASPL"
for source in "$VENDOR_DIR"/src/*.cpp; do
  object="$OBJ_DIR/$(basename "$source" .cpp).o"
  "$CXX" "${CXXFLAGS[@]}" -c "$source" -o "$object"
done

echo "==> Compiling VSLightAudioDriver"
"$CXX" "${CXXFLAGS[@]}" -c "$DRIVER_DIR/VSLightAudioDriver.cpp" -o "$OBJ_DIR/VSLightAudioDriver.o"

echo "==> Linking driver bundle"
"$CXX" -bundle \
  -arch "$ARCH" \
  -mmacosx-version-min=27.0 \
  -o "$BUNDLE/Contents/MacOS/VSLightAudioDriver" \
  "$OBJ_DIR"/*.o \
  -framework CoreFoundation \
  -framework CoreAudio \
  -framework AudioToolbox

cp "$DRIVER_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null

echo "==> Signing driver"
if [ -n "${CODESIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$BUNDLE"
else
  codesign --force --sign - "$BUNDLE"
fi
codesign --verify --strict --verbose=1 "$BUNDLE"

echo "==> Done: $BUNDLE"
file "$BUNDLE/Contents/MacOS/VSLightAudioDriver"
