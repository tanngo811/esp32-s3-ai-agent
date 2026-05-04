# Silent-default volume + 4-way auto-rotate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the device silent on first boot (volume default 0, persistable to 0) and add 4-way display auto-rotation driven by the on-board QMI8658 IMU.

**Architecture:** Two independent changes living in one branch. (1) Drop the codec's volume default + clamp so 0 is a real value. (2) Add a minimal QMI8658 I²C driver, then a 10 Hz orientation poller on the board class that calls `lv_display_set_rotation` with hysteresis. Software LVGL rotation (`sw_rotate=1`) handles both framebuffer and touch transform.

**Tech Stack:** ESP-IDF (≥6.0 per `idf_component.yml`), C++17, LVGL 9.5, `esp_lvgl_port` 2.7, FreeRTOS `esp_timer`. Board target: Waveshare ESP32-S3-Touch-AMOLED-1.8 (the only board this firmware builds for).

**Spec:** `docs/superpowers/specs/2026-05-04-silent-default-and-auto-rotate-design.md`

**Working dir for all commands:** `/Users/tanngo/Development/esp32_s3/xiaozhi-esp32`

**Test framework:** none (firmware, no host-side tests). Verification per task is `idf.py build` and — where the task changes runtime behavior — `idf.py -p /dev/cu.usbmodem* flash monitor` with the serial log inspection cues called out per task. The first build will pull managed components and take several minutes; later incremental builds are fast.

**Pre-task setup (run once per shell):**

```bash
. ~/esp/esp-idf-v5.3.2/export.sh
cd /Users/tanngo/Development/esp32_s3/xiaozhi-esp32
```

---

## Task 1: Volume defaults to 0 and persists at 0

**Files:**
- Modify: `main/audio/audio_codec.h:54`
- Modify: `main/audio/audio_codec.cc:29-38`

- [ ] **Step 1: Drop the in-class default to 0**

Open `main/audio/audio_codec.h`. Line 54 currently reads:

```cpp
    int output_volume_ = 70;
```

Change to:

```cpp
    int output_volume_ = 0;
```

- [ ] **Step 2: Remove the `<= 0` clamp in `Start()`**

Open `main/audio/audio_codec.cc`. Replace the entire `Start()` body (lines 29–38):

```cpp
void AudioCodec::Start() {
    Settings settings("audio", false);
    output_volume_ = settings.GetInt("output_volume", output_volume_);

    ESP_LOGI(TAG, "Audio codec started");
}
```

with:

```cpp
void AudioCodec::Start() {
    Settings settings("audio", false);
    output_volume_ = settings.GetInt("output_volume", output_volume_);

    ESP_LOGI(TAG, "Audio codec started (volume=%d)", output_volume_);
}
```

(The `if (output_volume_ <= 0) { … = 10; }` block is removed; the log line gains the value for diagnosability.)

- [ ] **Step 3: Build**

Run: `idf.py build`
Expected: succeeds. Last lines look like `Project build complete. To flash, run …`.

- [ ] **Step 4: Commit**

```bash
git add main/audio/audio_codec.h main/audio/audio_codec.cc
git commit -m "feat(audio): default volume to 0 and allow 0 as a persisted value"
```

---

## Task 2: Add QMI8658 driver (header + source + CMake)

**Files:**
- Create: `main/drivers/qmi8658.h`
- Create: `main/drivers/qmi8658.cc`
- Modify: `main/CMakeLists.txt:48-54`

- [ ] **Step 1: Create the header**

Write `main/drivers/qmi8658.h` exactly:

```cpp
#ifndef __QMI8658_H__
#define __QMI8658_H__

#include "i2c_device.h"

// Minimal QMI8658 driver: accel-only, polled. Aborts on I2C failure
// (matches the existing I2cDevice convention used by Axp2101).
class Qmi8658 : public I2cDevice {
public:
    Qmi8658(i2c_master_bus_handle_t i2c_bus, uint8_t addr);

    // Read accel in g.
    void ReadAccel(float& x, float& y, float& z);
};

#endif // __QMI8658_H__
```

- [ ] **Step 2: Create the source**

Write `main/drivers/qmi8658.cc` exactly:

```cpp
#include "qmi8658.h"

#include <esp_log.h>

#define TAG "Qmi8658"

namespace {
    constexpr uint8_t REG_CTRL1 = 0x02;  // address auto-increment, SPI/I2C select
    constexpr uint8_t REG_CTRL2 = 0x03;  // accel range + ODR
    constexpr uint8_t REG_CTRL5 = 0x06;  // accel low-pass filter
    constexpr uint8_t REG_CTRL7 = 0x08;  // sensor enable
    constexpr uint8_t REG_AX_L  = 0x35;  // accel data start (X_L..Z_H)

    constexpr float kLsbPerG_2G = 16384.0f;
}

Qmi8658::Qmi8658(i2c_master_bus_handle_t i2c_bus, uint8_t addr)
    : I2cDevice(i2c_bus, addr) {
    WriteReg(REG_CTRL1, 0x40); // address auto-increment; I2C interface
    WriteReg(REG_CTRL2, 0x05); // accel ±2g, 250 Hz ODR
    WriteReg(REG_CTRL5, 0x00); // disable on-chip LPF (we use software hysteresis)
    WriteReg(REG_CTRL7, 0x01); // enable accel only

    ESP_LOGI(TAG, "QMI8658 initialised at 0x%02X", addr);
}

void Qmi8658::ReadAccel(float& x, float& y, float& z) {
    uint8_t buf[6];
    ReadRegs(REG_AX_L, buf, sizeof(buf));

    int16_t raw_x = static_cast<int16_t>((buf[1] << 8) | buf[0]);
    int16_t raw_y = static_cast<int16_t>((buf[3] << 8) | buf[2]);
    int16_t raw_z = static_cast<int16_t>((buf[5] << 8) | buf[4]);

    x = raw_x / kLsbPerG_2G;
    y = raw_y / kLsbPerG_2G;
    z = raw_z / kLsbPerG_2G;
}
```

- [ ] **Step 3: Add to CMake source list**

Open `main/CMakeLists.txt`. The explicit `list(APPEND SOURCES …)` block is at lines 45–60 and currently lists drivers like `drivers/axp2101.cc` and `drivers/i2c_device.cc`. Insert `"drivers/qmi8658.cc"` so the block reads:

```cmake
list(APPEND SOURCES
    "board/board.cc"
    "board/wifi_board.cc"
    "drivers/adc_battery_monitor.cc"
    "drivers/axp2101.cc"
    "drivers/backlight.cc"
    "drivers/button.cc"
    "drivers/i2c_device.cc"
    "drivers/knob.cc"
    "drivers/qmi8658.cc"
    "drivers/sy6970.cc"
    "net/afsk_demod.cc"
    "platform/power_save_timer.cc"
    "platform/press_to_talk_mcp_tool.cc"
    "platform/sleep_timer.cc"
    "platform/system_reset.cc"
)
```

- [ ] **Step 4: Build**

Run: `idf.py build`
Expected: succeeds. The new driver compiles cleanly. (No call sites yet — this is just confirming the source compiles in the project's include / `-Wall` regime.)

- [ ] **Step 5: Commit**

```bash
git add main/drivers/qmi8658.h main/drivers/qmi8658.cc main/CMakeLists.txt
git commit -m "feat(drivers): add minimal QMI8658 accel driver"
```

---

## Task 3: Initialize IMU on the board and log accel — sanity check

This is a temporary diagnostic step: confirm the chip responds and the axes look sane before wiring rotation logic. The `esp_timer` here is replaced wholesale in Task 5.

**Files:**
- Modify: `main/board/amoled-1.8/config.h` (append constant)
- Modify: `main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc` (include, member, init, temp logger)

- [ ] **Step 1: Add the I²C address constant**

Open `main/board/amoled-1.8/config.h`. Insert one line above the closing `#endif`:

```c
#define QMI8658_I2C_ADDR 0x6B   // alt 0x6A per ADDR pin
```

So the tail of the file becomes:

```c
#define DISPLAY_BACKLIGHT_PIN GPIO_NUM_NC
#define DISPLAY_BACKLIGHT_OUTPUT_INVERT false

#define QMI8658_I2C_ADDR 0x6B   // alt 0x6A per ADDR pin
#endif // _BOARD_CONFIG_H_
```

- [ ] **Step 2: Include the driver header in the board file**

Open `main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc`. After line 12 (`#include "axp2101.h"`), add:

```cpp
#include "qmi8658.h"
```

- [ ] **Step 3: Add IMU + diagnostic-timer members**

In the `private:` section of `class WaveshareEsp32s3TouchAMOLED1inch8` (currently lines 120–128), append after `bool screen_off_ = false;`:

```cpp
    Qmi8658* imu_ = nullptr;
    esp_timer_handle_t orientation_timer_ = nullptr;
```

- [ ] **Step 4: Add `InitializeImu()` and `InitializeOrientationTimer()` methods**

Insert these private methods after `InitializeAxp2101()` (around line 184) and before `InitializeSpi()`:

```cpp
    void InitializeImu() {
        ESP_LOGI(TAG, "Init QMI8658");
        imu_ = new Qmi8658(codec_i2c_bus_, QMI8658_I2C_ADDR);
    }

    static void OrientationTimerThunk(void* arg) {
        static_cast<WaveshareEsp32s3TouchAMOLED1inch8*>(arg)->OnOrientationTick();
    }

    void OnOrientationTick() {
        if (screen_off_) return;
        float x, y, z;
        imu_->ReadAccel(x, y, z);
        ESP_LOGI(TAG, "accel x=%+.2f y=%+.2f z=%+.2f", x, y, z);
    }

    void InitializeOrientationTimer() {
        const esp_timer_create_args_t args = {
            .callback = &OrientationTimerThunk,
            .arg = this,
            .dispatch_method = ESP_TIMER_TASK,
            .name = "orientation",
            .skip_unhandled_events = true,
        };
        ESP_ERROR_CHECK(esp_timer_create(&args, &orientation_timer_));
        ESP_ERROR_CHECK(esp_timer_start_periodic(orientation_timer_, 1000 * 1000)); // 1 Hz for sanity
    }
```

- [ ] **Step 5: Wire the inits into the constructor**

In the `WaveshareEsp32s3TouchAMOLED1inch8()` constructor body (currently lines 322–333), insert `InitializeImu();` and `InitializeOrientationTimer();` so it reads:

```cpp
    WaveshareEsp32s3TouchAMOLED1inch8() :
        boot_button_(BOOT_BUTTON_GPIO) {
        InitializePowerSaveTimer();
        InitializeCodecI2c();
        InitializeTca9554();
        InitializeAxp2101();
        InitializeImu();
        InitializeSpi();
        InitializeSH8601Display();
        InitializeOrientationTimer();
        InitializeTouch();
        InitializeButtons();
        InitializeTools();
    }
```

(IMU init happens after `InitializeCodecI2c()` because the codec creates the shared I²C bus the IMU rides on. Orientation timer comes after the display so future tasks that touch LVGL don't fight initialization order.)

- [ ] **Step 6: Build**

Run: `idf.py build`
Expected: succeeds.

- [ ] **Step 7: Flash and monitor — confirm chip responds and axes are sensible**

Run: `idf.py -p /dev/cu.usbmodem* flash monitor`

Expected serial output (within ~5 s of boot):
- `I (...) WaveshareEsp32s3TouchAMOLED1inch8: Init QMI8658`
- `I (...) Qmi8658: QMI8658 initialised at 0x6B`
- `I (...) WaveshareEsp32s3TouchAMOLED1inch8: accel x=+0.00 y=+1.00 z=+0.00` (or similar, with one axis ≈ ±1 g and the other two ≈ 0 when the board is held still in portrait)

Tilt the board 90° and confirm the dominant axis swaps from Y to X (or Y to Y inverted, etc). If you see `ESP_ERROR_CHECK failed: 0x107 (ESP_ERR_TIMEOUT)` with `i2c_master_transmit_receive`, the address is wrong — try `0x6A` in `config.h` and rebuild.

Exit monitor with `Ctrl-]`. **Do not commit yet** — record which axis maps to which physical orientation in your notes; you need it for Task 5.

- [ ] **Step 8: Commit**

```bash
git add main/board/amoled-1.8/config.h main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc
git commit -m "feat(board): initialize QMI8658 IMU and log accel readings"
```

---

## Task 4: Enable software rotation and make status bar reflow

**Files:**
- Modify: `main/display/lcd_display.cc:147-160` (SpiLcdDisplay's `display_cfg.flags`)
- Modify: `main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc:90-97` (`CustomLcdDisplay::SetupUI`)

- [ ] **Step 1: Set `sw_rotate = 1` for the SPI display**

Open `main/display/lcd_display.cc`. In the `SpiLcdDisplay` constructor, the `display_cfg` literal currently has:

```cpp
        .flags = {
            .buff_dma = 1,
            .buff_spiram = 0,
            .sw_rotate = 0,
            .swap_bytes = 1,
            .full_refresh = 0,
            .direct_mode = 0,
        },
```

Change `.sw_rotate = 0,` to `.sw_rotate = 1,`. Leave all other flags untouched. (`RgbLcdDisplay` and `MipiLcdDisplay` are not used by this board — do not modify them.)

- [ ] **Step 2: Make the status-bar padding reflow on rotation**

Open `main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc`. Replace the body of `CustomLcdDisplay::SetupUI()` (lines 90–97):

```cpp
    virtual void SetupUI() override {
        // Call parent SetupUI() first to create all lvgl objects
        SpiLcdDisplay::SetupUI();

        DisplayLockGuard lock(this);
        lv_obj_set_style_pad_left(status_bar_, LV_HOR_RES * 0.1, 0);
        lv_obj_set_style_pad_right(status_bar_, LV_HOR_RES * 0.1, 0);
    }
```

with:

```cpp
    virtual void SetupUI() override {
        // Call parent SetupUI() first to create all lvgl objects
        SpiLcdDisplay::SetupUI();

        DisplayLockGuard lock(this);
        int hor = lv_display_get_horizontal_resolution(lv_display_get_default());
        lv_obj_set_style_pad_left(status_bar_, hor * 0.1, 0);
        lv_obj_set_style_pad_right(status_bar_, hor * 0.1, 0);
    }
```

(`LV_HOR_RES` is the compile-time native resolution and never updates after rotation; `lv_display_get_horizontal_resolution` returns the live width.)

- [ ] **Step 3: Build**

Run: `idf.py build`
Expected: succeeds.

- [ ] **Step 4: Flash and monitor — confirm display still works**

Run: `idf.py -p /dev/cu.usbmodem* flash monitor`

Expected:
- Display lights up normally in portrait (USB-C down).
- The chat / emoji UI renders with status bar padded ~37 px on each side (10% of 368).
- Touching a button on screen still triggers the action (the FT5x06 → LVGL touch transform should be unchanged since we have not yet called `lv_display_set_rotation`).
- The `accel x=… y=… z=…` log from Task 3 is still printing once per second.

If the display is blank or scrambled, software rotation may not be cooperating with the partial-buffer mode used here — revert this task's `sw_rotate` change and consult the spec's "Open questions" section (MADCTL fallback) before continuing.

Exit monitor with `Ctrl-]`.

- [ ] **Step 5: Commit**

```bash
git add main/display/lcd_display.cc main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc
git commit -m "feat(display): enable LVGL software rotation on SPI panel"
```

---

## Task 5: Replace the diagnostic logger with the real auto-rotate engine

**Files:**
- Modify: `main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc` (members + `OnOrientationTick` + `InitializeOrientationTimer`)

- [ ] **Step 1: Add lvgl include for rotation enums and member fields**

In the include block at the top of `main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc`, ensure `<lvgl.h>` is present (it already is, line 24). No new include needed.

In the `private:` member block (added in Task 3), append three more lines so it reads:

```cpp
    Qmi8658* imu_ = nullptr;
    esp_timer_handle_t orientation_timer_ = nullptr;
    lv_display_rotation_t current_rotation_ = LV_DISPLAY_ROTATION_0;
    lv_display_rotation_t pending_rotation_ = LV_DISPLAY_ROTATION_0;
    int pending_count_ = 0;
```

- [ ] **Step 2: Replace `OnOrientationTick` with the real classifier + hysteresis**

Replace the entire body of `OnOrientationTick` (added in Task 3) with:

```cpp
    void OnOrientationTick() {
        if (screen_off_) return;

        float x, y, z;
        imu_->ReadAccel(x, y, z);

        const float ax = std::fabs(x);
        const float ay = std::fabs(y);
        const float az = std::fabs(z);

        // Need a clear gravity direction. Reject if the largest axis is weak
        // (board being shaken, free-falling, or held at ~45°).
        const float dominant = std::max(ax, std::max(ay, az));
        if (dominant < 0.6f) return;

        // Z dominant => face up / face down. Hold current orientation.
        if (az >= ax && az >= ay) return;

        // Map dominant horizontal axis + sign to one of four LVGL rotations.
        // NOTE: confirm this mapping against your Task 3 readings. If the
        // physical orientation does not match, swap the four cases below.
        lv_display_rotation_t candidate;
        if (ay >= ax) {
            candidate = (y > 0) ? LV_DISPLAY_ROTATION_0    // USB-C down
                                : LV_DISPLAY_ROTATION_180; // USB-C up
        } else {
            candidate = (x > 0) ? LV_DISPLAY_ROTATION_270  // USB-C right
                                : LV_DISPLAY_ROTATION_90;  // USB-C left
        }

        if (candidate == current_rotation_) {
            pending_count_ = 0;
            return;
        }
        if (candidate == pending_rotation_) {
            ++pending_count_;
        } else {
            pending_rotation_ = candidate;
            pending_count_ = 1;
        }

        if (pending_count_ >= 3) { // ~300 ms hold at 10 Hz
            DisplayLockGuard lock(GetDisplay());
            lv_display_set_rotation(lv_display_get_default(), pending_rotation_);
            current_rotation_ = pending_rotation_;
            pending_count_ = 0;
            ESP_LOGI(TAG, "rotation -> %d", static_cast<int>(current_rotation_));
        }
    }
```

Add `#include <cmath>` and `#include <algorithm>` near the top of the file if not already present (search for `#include <esp_log.h>`; if `<cmath>` is missing, add both immediately after).

- [ ] **Step 3: Bump the timer to 10 Hz and seed the rotation state**

Replace the `InitializeOrientationTimer()` body added in Task 3 with:

```cpp
    void InitializeOrientationTimer() {
        // Seed from whatever the display reports right now so the first tick
        // doesn't fight the boot orientation.
        current_rotation_ = lv_display_get_rotation(lv_display_get_default());
        pending_rotation_ = current_rotation_;
        pending_count_ = 0;

        const esp_timer_create_args_t args = {
            .callback = &OrientationTimerThunk,
            .arg = this,
            .dispatch_method = ESP_TIMER_TASK,
            .name = "orientation",
            .skip_unhandled_events = true,
        };
        ESP_ERROR_CHECK(esp_timer_create(&args, &orientation_timer_));
        ESP_ERROR_CHECK(esp_timer_start_periodic(orientation_timer_, 100 * 1000)); // 10 Hz
    }
```

- [ ] **Step 4: Build**

Run: `idf.py build`
Expected: succeeds. If `std::fabs` / `std::max` complain, the includes from Step 2 are missing — add `<cmath>` and `<algorithm>`.

- [ ] **Step 5: Flash and monitor — verify auto-rotate**

Run: `idf.py -p /dev/cu.usbmodem* flash monitor`

Expected behavior:
- On boot the display comes up in its native portrait. No `accel x=…` log spam (we removed it).
- Hold the board in portrait (USB-C down): no rotation log, display stays in 0°.
- Rotate 90° clockwise so USB-C points left: within ~300 ms a single line `WaveshareEsp32s3TouchAMOLED1inch8: rotation -> 1` (LV_DISPLAY_ROTATION_90 = 1) prints and the UI rotates to landscape. Touch a UI element to confirm input lands on the right widget.
- Rotate 180° (USB-C up): `rotation -> 2` and inverted portrait. Touch still accurate.
- Rotate 270° (USB-C right): `rotation -> 3` and the other landscape. Touch still accurate.
- Lay the board face-up flat on the table: no further `rotation ->` lines (Z dominant → hold).
- Wave the board around quickly: rotation does not flicker (hysteresis holds).

If the rotations come out swapped (e.g. tilting one way produces the wrong orientation), edit the four `candidate = …` cases in `OnOrientationTick` accordingly, rebuild, reflash. This is the only step the spec calls "hardware-empirical".

If touch coordinates are wrong after rotation, re-check that Task 4's `sw_rotate = 1` change is in place — `esp_lvgl_port` only does the touch transform when software rotation is enabled.

Exit monitor with `Ctrl-]`.

- [ ] **Step 6: Commit**

```bash
git add main/board/amoled-1.8/esp32-s3-touch-amoled-1.8.cc
git commit -m "feat(board): add 4-way auto-rotate driven by QMI8658 accel"
```

---

## Task 6: Final hardware verification

No code changes. This task is the spec's verification plan, run end-to-end on a single flash.

- [ ] **Step 1: Erase NVS so the volume default actually takes effect**

The persisted volume from any previous testing is in NVS; we need to confirm a fresh device truly comes up silent. Run:

```bash
idf.py -p /dev/cu.usbmodem* erase-flash
idf.py -p /dev/cu.usbmodem* flash monitor
```

- [ ] **Step 2: Verify silent boot**

In the serial log look for: `Audio codec started (volume=0)`.
Listen / confirm the device emits no audio prompts at boot. Do not touch any volume control yet.

- [ ] **Step 3: Verify volume 0 persists**

Use whatever in-firmware path normally sets volume (for this board it's exposed via the chat / settings UI or MCP tools — the codec's `SetOutputVolume(0)` is what gets called). Set volume to 0 explicitly, exit monitor, replug, reflash with `idf.py -p /dev/cu.usbmodem* monitor` (no flash this time), and confirm the boot log still shows `volume=0`.

- [ ] **Step 4: Verify auto-rotate end-to-end**

Hold the board still in each of the four orientations in turn (portrait normal, landscape left, portrait inverted, landscape right) and confirm:
- Rotation occurs within ~300 ms of holding the new orientation.
- Touch input remains accurate in every orientation.
- Status bar padding still looks right (≈10% of the now-effective horizontal resolution on each side).
- Lying flat: orientation does not change.
- Power save: double-click BOOT to turn the screen off (per the existing `boot_button_.OnDoubleClick` handler), tilt the board around, confirm display stays off (no wake, no log spam).

- [ ] **Step 5: No commit needed**

If anything in steps 2–4 fails, do not patch around it here — go back to the relevant task, fix and commit there.

---

## Self-review

Done by the plan author after writing:

**Spec coverage:**
- §1 Volume default → Task 1 ✓
- §2 QMI8658 driver → Task 2 ✓
- §3a Polling + classifier + hysteresis → Tasks 3 (scaffold) + 5 (real engine) ✓
- §3b `sw_rotate=1` → Task 4 ✓
- §3c Status-bar padding fix → Task 4 ✓
- §4 Board wiring → Tasks 3 + 5 ✓
- §5 CMake → Task 2 ✓
- §6 Power-save interaction → covered by `if (screen_off_) return;` introduced in Task 3 and preserved in Task 5; verified in Task 6 step 4 ✓
- Verification plan items → Task 6 ✓

**Placeholder scan:** none.

**Type / signature consistency:** `Qmi8658::ReadAccel(float&, float&, float&)` — defined in Task 2, called in Tasks 3 and 5 with matching signature. `OrientationTimerThunk` static signature matches `esp_timer_cb_t`. `lv_display_rotation_t` enum used consistently in Task 5.

The "axis-to-rotation mapping" caveat is intentional and called out in Task 3 step 7 (record observations), Task 5 step 2 (note in code), and Task 5 step 5 (re-verify on hardware) — not a placeholder, it's the one piece of board physics you can only confirm with the device in hand.
