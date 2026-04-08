#!/usr/bin/env bash
set -euo pipefail

IMAGE_ARM="docker.io/zmkfirmware/zmk-dev-arm:3.5"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$SET_DIR/firmware"
LOG_DIR="$SET_DIR/build-logs"
mkdir -p "$OUT_DIR" "$LOG_DIR"

# Module repos (mounted read-only)
SHIELD_CUSTOM_22="$SET_DIR/zmk-shield-custom-22"
SHIELD_XIAO_DONGLE="$SET_DIR/zmk-shield-xiao-dongle"
BOARD_TRACKBALL="$SET_DIR/zmk-board-efogtech-trackball-0"
ROLLING_COMBOS="$SET_DIR/zmk-feature-rolling-combos"

# Builds: "image board shield artifact_name extra_modules"
# For trackball, we merge its own config with taipo's config overlays
BUILDS=(
    "dongle|seeeduino_xiao_ble|xiao_dongle dongle_display"
    "left|seeeduino_xiao_ble|custom_22"
    "right|seeeduino_xiao_ble|custom_22"
    "trackball|efogtech_trackball_0|"
    "settings_reset|seeeduino_xiao_ble|settings_reset"
)

passed=0
failed=0
errors=""

for entry in "${BUILDS[@]}"; do
    IFS='|' read -r name board shield <<< "$entry"

    echo ""
    echo "=== Building: $name ($board / ${shield:-no shield}) ==="

    if [ "$name" = "trackball" ]; then
        # Trackball: merge board's own config with taipo's overlay/keymap
        docker run --rm \
          -v "$BOARD_TRACKBALL/config":/board-config:ro \
          -v "$SCRIPT_DIR/config":/taipo-config:ro \
          -v "$BOARD_TRACKBALL/boards":/boards:ro \
          -v "$BOARD_TRACKBALL/zephyr":/zephyr-module:ro \
          -v "$OUT_DIR":/firmware \
          "$IMAGE_ARM" \
          bash -c '
mkdir -p /config
cp /board-config/* /config/ 2>/dev/null || true
# Taipo keymap and conf override board defaults
cp /taipo-config/efogtech_trackball_0.keymap /config/
cp /taipo-config/efogtech_trackball_0.conf /config/
cd / && west init -l /config > /dev/null 2>&1
west update --fetch-opt=--filter=tree:0 > /dev/null 2>&1
export ZEPHYR_BASE=/zephyr CMAKE_PREFIX_PATH="/zephyr/share/zephyr-package/cmake"
west build -p always -s /zmk/app -b efogtech_trackball_0 -d /tmp/build -- \
  -DZMK_CONFIG="/config" -DBOARD_ROOT="/boards/.." 2>&1
if [ -f /tmp/build/zephyr/zmk.uf2 ]; then
  cp /tmp/build/zephyr/zmk.uf2 /firmware/trackball.uf2
fi
' > "$LOG_DIR/$name.log" 2>&1
    else
        # Keyboard/dongle/settings_reset: use taipo config with shield modules
        # Only dongle needs the xiao_dongle shield module
        if [ "$name" = "dongle" ]; then
            EXTRA_MODULES="/shield-custom-22;/shield-xiao-dongle;/rolling-combos"
        else
            EXTRA_MODULES="/shield-custom-22;/rolling-combos"
        fi

        # Build volumes — dongle needs xiao_dongle shield
        VOLUMES="-v $SCRIPT_DIR/config:/config:ro -v $SHIELD_CUSTOM_22:/shield-custom-22:ro -v $ROLLING_COMBOS:/rolling-combos:ro -v $OUT_DIR:/firmware"
        if [ "$name" = "dongle" ]; then
            VOLUMES="$VOLUMES -v $SHIELD_XIAO_DONGLE:/shield-xiao-dongle:ro"
        fi

        docker run --rm \
          $VOLUMES \
          "$IMAGE_ARM" \
          bash -c "
cd /
west init -l /config > /dev/null 2>&1
west update --fetch-opt=--filter=tree:0 > /dev/null 2>&1
export ZEPHYR_BASE=/zephyr CMAKE_PREFIX_PATH=\"/zephyr/share/zephyr-package/cmake\"
west build -p always -s /zmk/app -b $board -d /tmp/build -- \
  ${shield:+-DSHIELD=\"$shield\"} \
  -DZMK_CONFIG=\"/config\" \
  -DZMK_EXTRA_MODULES=\"$EXTRA_MODULES\" 2>&1
if [ -f /tmp/build/zephyr/zmk.uf2 ]; then
  cp /tmp/build/zephyr/zmk.uf2 /firmware/$name.uf2
fi
" > "$LOG_DIR/$name.log" 2>&1
    fi

    if [ -f "$OUT_DIR/$name.uf2" ]; then
        echo "PASS: $name ($(ls -lh "$OUT_DIR/$name.uf2" | awk '{print $5}'))"
        passed=$((passed + 1))
    else
        echo "FAIL: $name (see $LOG_DIR/$name.log)"
        failed=$((failed + 1))
        errors="$errors  $name\n"
    fi
done

echo ""
echo "=============================="
echo "Results: $passed passed, $failed failed"
if [ $failed -gt 0 ]; then
    echo -e "Failures:\n$errors"
    exit 1
fi
echo "All builds passed."
