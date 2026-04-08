# zmk-taipo

Taipo input method firmware configuration for:
- **Custom 22** split keyboard (2 halves, 11 keys each)
- **Endgame trackball** (dual PAW3395 sensors, 8 buttons, 2 encoders)
- **XIAO BLE dongle** (central hub with SSD1306 OLED display)

## Architecture

This repo assembles firmware from independent hardware modules:

| Module | What it is |
|--------|-----------|
| `zmk-shield-custom-22` | Single keyboard half (11 GPIO keys) |
| `zmk-shield-xiao-dongle` | Generic XIAO BLE dongle (OLED, mock kscan) |
| `zmk-board-efogtech-trackball-0` | Trackball board (dual PAW3395, split peripheral) |
| `zmk-feature-rolling-combos` | Rolling combos for overlapping combo detection |
| `zmk-dongle-display` | OLED display module with battery/WPM/layer widgets |

Hardware repos know nothing about each other. All combination knowledge lives here:
- Combined 34-position transform (keyboard 0-21, trackball 22-33)
- Left/right col-offset overlays
- Trackball position offset overlay
- Input-split proxy on dongle for trackball pointing
- Taipo combo definitions
- Button/encoder bindings for trackball
- Trackball layer switching (scroll mode, snipe mode)

## Build

```bash
./build-docker.sh
```

Outputs 5 firmware files to `../firmware/`:
- `dongle.uf2` — central (XIAO BLE + OLED + dongle_display)
- `left.uf2` — left keyboard half
- `right.uf2` — right keyboard half
- `trackball.uf2` — trackball peripheral
- `settings_reset.uf2` — BLE bond reset utility

## Trackball Layers

The trackball has 5 layers, activated by holding buttons:

| Layer | Activation | Trackball behavior |
|-------|-----------|-------------------|
| Default | — | Normal pointer movement |
| Extras | Hold MB4 (pos 28) | Copy/paste shortcuts on buttons |
| Scroll | Hold ESC button (pos 23) or cdch hold (pos 25) | Trackball becomes scroll wheel |
| Snipe | Hold ENTER button (pos 22) | Slow precision pointer |
| User | Hold MB5 (pos 29) | Customizable |

## Adjusting Pointer and Scroll Sensitivity

### Pointer sensitivity

The pointer speed is controlled by two mechanisms:

1. **CPI (Counts Per Inch)** — hardware sensor resolution, set in the trackball board's `pointer.dtsi`:
   ```
   cpi = <2400>;
   ```
   Higher = more sensitive. Range: 50-26000 in steps of 50.

2. **Acceleration curve** — applied in `custom_22.keymap` via the `trackball_listener` input processors:
   ```
   input-processors = <&zip_scroll_scaler TWIST_MULTIPLIER TWIST_DIVISOR>,
                      <&zip_pointer_accel>, ...
   ```
   The `zip_pointer_accel` node applies the default acceleration curve from the `zmk-acceleration-curves` module.

### Scroll sensitivity

When in scroll mode (hold ESC button), the trackball input is scaled and converted to scroll events:

```
scroll {
    layers = <LAYER_SCROLL>;
    input-processors = <&zip_xy_scaler SCROLL_MULTIPLIER SCROLL_DIVISOR>, ...
};
```

Adjust `SCROLL_MULTIPLIER` and `SCROLL_DIVISOR` at the top of `custom_22.keymap`:
```c
#define SCROLL_MULTIPLIER  1   // numerator
#define SCROLL_DIVISOR     3   // denominator — higher = slower scroll
```

### Snipe (precision) sensitivity

When in snipe mode (hold ENTER button):

```c
#define SNIPE_MULTIPLIER   1   // numerator
#define SNIPE_DIVISOR      4   // denominator — higher = slower/more precise
```

### Twist compensation

Dual-sensor twist (rotation) produces unwanted cursor movement. The compensation scaler:
```c
#define TWIST_MULTIPLIER   1
#define TWIST_DIVISOR      10  // higher = more twist suppression
```

### Sensor tuning (advanced)

Fine-grained sensor behavior is configured in `config/efogtech_trackball_0.conf`:

| Setting | Default | Description |
|---------|---------|-------------|
| `CONFIG_POINTER_2S_MIXER_EMA_ALPHA` | 10 | Smoothing (higher = less smoothing) |
| `CONFIG_POINTER_2S_MIXER_STEADY_THRES` | 4 | Steady-state detection threshold |
| `CONFIG_POINTER_2S_MIXER_STEADY_COOLDOWN` | 150 | Cooldown after steady detection (ms) |
| `CONFIG_PAW3395_REPORT_INTERVAL_MIN` | 0 | Minimum report interval (0 = fastest) |
| `CONFIG_PAW3395_INIT_POWER_UP_EXTRA_DELAY_MS` | 850 | Sensor power-up delay (ms) |

## USB Logging (Debugging)

### Dongle

Add the `zmk-usb-logging` snippet to the dongle build:
```bash
west build ... -S zmk-usb-logging
```
Then connect to the USB serial port (e.g., `minicom -D /dev/ttyACM0`).

### Trackball

The trackball can also expose USB serial for logging despite being a BLE peripheral. USB logging uses CDC ACM (serial), not USB HID, so it doesn't conflict with the split peripheral role.

To enable, build with the snippet:
```bash
west build -b efogtech_trackball_0 -S zmk-usb-logging -- -DZMK_CONFIG=...
```
Or in `build.yaml`:
```yaml
  - board: efogtech_trackball_0
    snippet: zmk-usb-logging
```

Note: USB logging increases power consumption. Only enable for debugging.

### Keyboard halves

Keyboard halves can also use `zmk-usb-logging` when connected via USB for debugging.

## BLE Topology

```
         ┌─────────┐
         │  Dongle  │ ← USB to host
         │ (central)│
         └────┬────┘
              │ BLE
    ┌─────────┼─────────┐
    │         │         │
┌───┴───┐ ┌──┴────┐ ┌──┴──────┐
│ Left  │ │ Right │ │Trackball│
│ (peri)│ │ (peri)│ │ (peri)  │
└───────┘ └───────┘ └─────────┘
```

3 peripherals, 4 BLE connections (3 + host).
