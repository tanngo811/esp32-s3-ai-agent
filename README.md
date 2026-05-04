# XiaoZhi-ESP32 (Waveshare AMOLED 1.8 build)

Voice-assistant firmware for the **Waveshare ESP32-S3-Touch-AMOLED-1.8**
board. Talks to the XiaoZhi backend over MQTT/UDP or WebSocket and exposes
device controls via the MCP protocol.

## Hardware target

- **Board:** Waveshare ESP32-S3-Touch-AMOLED-1.8
- **SoC:** ESP32-S3 (octal PSRAM, 16 MB flash)
- **Display:** 1.8" AMOLED via SH8601, FT5x06 capacitive touch
- **Audio:** ES8311 codec
- **Power:** AXP2101 PMIC

This tree only builds for that one board. Other targets and boards have
been removed.

## Quickstart

Requires ESP-IDF **>= 5.5.2**.

```bash
. $IDF_PATH/export.sh                  # set up the toolchain
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/ttyUSB0 flash monitor   # adjust port for your OS
```

The board, language, and other defaults are pre-set in `sdkconfig.defaults`
and `sdkconfig.defaults.esp32s3`. Run `idf.py menuconfig` only if you want
to change them.

## Configuration

Exposed in `idf.py menuconfig` under **Xiaozhi Assistant**:

- **Default Language** — UI/audio language (English by default).
- **Default OTA URL** — backend address checked for new firmware.
- **Wake Word Implementation Type** — disabled, AFE wakenet, or custom multinet.
- **Enable Audio Noise Reduction** — AFE-based audio processor (recommended).
- **Enable Server-Side AEC** — server-side echo cancellation (experimental).
- **WiFi Configuration Method** — Hotspot (default), Acoustic, or BluFi.
- **Camera Configuration** — JPEG input, hardware encoder/decoder, image rotation.
- **Enable Audio Debugger** — stream raw audio over UDP for debugging.

## Project layout

```
main/
├── core/         application lifecycle, settings, OTA, MCP server
├── audio/        codec, audio service, codecs/, processors/, wake_words/
├── display/      display, lcd_display, lvgl_display/
├── led/          LED driver variants
├── protocols/    MQTT and WebSocket transport
├── drivers/      peripheral chips (AXP2101 PMIC, button, backlight, …)
├── net/          network helpers (BluFi, AFSK, modem boards)
├── platform/     OS-level utilities (sleep timer, system reset, …)
├── board/        board base classes + amoled-1.8/ board glue
└── assets/       runtime locales and asset packing
```

## Partition table

`partitions/v2/16m.csv` — 16 MB layout with separate `assets` partition.
See `partitions/v2/README.md` for the full map.

## Protocols and integration

- `docs/mcp-protocol.md` — MCP control protocol
- `docs/mcp-usage.md` — building MCP tools
- `docs/websocket.md` — WebSocket transport
- `docs/mqtt-udp.md` — MQTT + UDP transport
- `docs/blufi.md` — BluFi WiFi provisioning

## License

See [LICENSE](LICENSE).
