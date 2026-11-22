#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT

swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos27.0" \
  -o "$OUTPUT_DIR/verify-volume-card" \
  "$ROOT/Scripts/verify-volume-card.swift" \
  "$ROOT/Sources/Features/Volume/VolumeCardView.swift" \
  "$ROOT/Sources/Core/Audio/VolumeFormatter.swift"

"$OUTPUT_DIR/verify-volume-card"
