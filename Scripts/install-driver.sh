#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT_DIR/Driver/build/VSLightAudioDriver.driver"
DESTINATION="/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver"
USER_DESTINATION="$HOME/Library/Audio/Plug-Ins/HAL/VSLightAudioDriver.driver"

if [ "${1:-}" = "--uninstall" ]; then
  sudo rm -rf "$DESTINATION"
  rm -rf "$USER_DESTINATION"
  sudo killall coreaudiod 2>/dev/null || true
  sleep 1

  if [ -e "$DESTINATION" ] || [ -e "$USER_DESTINATION" ]; then
    echo "Driver files are still present. Check permissions and try again." >&2
    exit 1
  fi

  echo "Uninstalled VSLightAudioDriver.driver"
  exit 0
fi

if [ ! -d "$SOURCE" ]; then
  echo "Driver bundle not found: $SOURCE" >&2
  echo "Run ./Scripts/build-driver.sh first." >&2
  exit 1
fi

sudo mkdir -p "$(dirname "$DESTINATION")"
sudo rm -rf "$DESTINATION"
sudo cp -R "$SOURCE" "$DESTINATION"
sudo killall coreaudiod 2>/dev/null || true

echo "Installed $DESTINATION"
echo "Wait a few seconds, then check System Settings > Sound."
