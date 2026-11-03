#!/usr/bin/env bash
set -euo pipefail

PROJECT_FILE="${1:-project.yml}"
VERSION="$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$PROJECT_FILE" | head -1 | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([0-9.]+)"?.*/\1/')"
BUILD="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' "$PROJECT_FILE" | head -1 | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9.]+)"?.*/\1/')"

case "$VERSION" in
  "")
    echo "버전을 찾지 못했습니다: $PROJECT_FILE" >&2
    exit 1
    ;;
  *4*)
    echo "금지된 숫자 4가 버전에 포함되어 있습니다: $VERSION" >&2
    exit 1
    ;;
esac

case "$BUILD" in
  *4*)
    echo "금지된 숫자 4가 빌드 번호에 포함되어 있습니다: $BUILD" >&2
    exit 1
    ;;
esac

echo "버전 검사 통과: $VERSION ($BUILD)"
