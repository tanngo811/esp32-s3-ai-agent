#!/usr/bin/env bash
# Re-apply v6.0 compatibility patches to managed_components/ after a fresh
# `idf.py reconfigure` (or after deleting managed_components/).
#
# These patches address upstream bugs that block the ESP-IDF v6.0 build for
# the components pulled in by main/idf_component.yml. They are idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MC="$ROOT/managed_components"

if [[ ! -d "$MC" ]]; then
    echo "managed_components/ not found. Run 'idf.py reconfigure' first." >&2
    exit 1
fi

# 78__uart-uhci: missing esp_driver_dma in REQUIRES, and uses removed v5 GDMA API
patch_uart_uhci() {
    local cmake="$MC/78__uart-uhci/CMakeLists.txt"
    local src="$MC/78__uart-uhci/src/uart_uhci.cc"

    if [[ -f "$cmake" ]] && ! grep -q "esp_driver_dma" "$cmake"; then
        # Insert PRIV_REQUIRES esp_driver_dma before the closing paren
        sed -i.bak 's/        esp_driver_uart$/        esp_driver_uart\
    PRIV_REQUIRES\
        esp_driver_dma/' "$cmake"
        rm -f "$cmake.bak"
        echo "  patched $cmake"
    fi

    if [[ -f "$src" ]] && grep -q "rx_alloc.direction" "$src"; then
        # v6 GDMA: drop .direction; gdma_new_ahb_channel takes (cfg, tx, rx)
        python3 - "$src" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text()
t = re.sub(
    r"gdma_channel_alloc_config_t rx_alloc = \{\};\s*\n"
    r"\s*rx_alloc\.direction = GDMA_CHANNEL_DIRECTION_RX;\s*\n"
    r"\s*ESP_RETURN_ON_ERROR\(gdma_new_ahb_channel\(&rx_alloc, &rx_dma_chan_\),",
    "gdma_channel_alloc_config_t rx_alloc = {};\n"
    "    ESP_RETURN_ON_ERROR(gdma_new_ahb_channel(&rx_alloc, nullptr, &rx_dma_chan_),",
    t,
    count=1,
)
p.write_text(t)
PY
        echo "  patched $src"
    fi
}

# waveshare__esp_lcd_sh8601: macro initialiser uses raw -1 for gpio_num_t field
patch_sh8601() {
    local hdr="$MC/waveshare__esp_lcd_sh8601/include/esp_lcd_sh8601.h"
    if [[ -f "$hdr" ]] && grep -q "\.dc_gpio_num = -1," "$hdr"; then
        sed -i.bak 's/\.dc_gpio_num = -1,/\.dc_gpio_num = GPIO_NUM_NC,/g' "$hdr"
        rm -f "$hdr.bak"
        echo "  patched $hdr"
    fi
}

# espressif__esp_video: linux/ioctl.h redefines _IO/_IOR/_IOW/_IOWR macros that
# PicolibC already defines in <sys/ioctl.h>. Add #ifndef guards.
patch_esp_video_ioctl() {
    local hdr="$MC/espressif__esp_video/include/linux/ioctl.h"
    [[ -f "$hdr" ]] || return 0
    if grep -q "^#define _IO(type,nr)" "$hdr" && ! grep -q "^#ifndef _IO$" "$hdr"; then
        python3 - "$hdr" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text()
old = (
    "#define _IO(type,nr)        _IOC(_IOC_NONE,(type),(nr),0)\n"
    "#define _IOR(type,nr,size)  _IOC(_IOC_READ,(type),(nr),(_IOC_TYPECHECK(size)))\n"
    "#define _IOW(type,nr,size)  _IOC(_IOC_WRITE,(type),(nr),(_IOC_TYPECHECK(size)))\n"
    "#define _IOWR(type,nr,size) _IOC(_IOC_READ|_IOC_WRITE,(type),(nr),(_IOC_TYPECHECK(size)))\n"
)
new = (
    "/* PicolibC (ESP-IDF v6 default libc) also defines _IO/_IOR/_IOW/_IOWR. */\n"
    "#ifndef _IO\n"
    "#define _IO(type,nr)        _IOC(_IOC_NONE,(type),(nr),0)\n"
    "#endif\n"
    "#ifndef _IOR\n"
    "#define _IOR(type,nr,size)  _IOC(_IOC_READ,(type),(nr),(_IOC_TYPECHECK(size)))\n"
    "#endif\n"
    "#ifndef _IOW\n"
    "#define _IOW(type,nr,size)  _IOC(_IOC_WRITE,(type),(nr),(_IOC_TYPECHECK(size)))\n"
    "#endif\n"
    "#ifndef _IOWR\n"
    "#define _IOWR(type,nr,size) _IOC(_IOC_READ|_IOC_WRITE,(type),(nr),(_IOC_TYPECHECK(size)))\n"
    "#endif\n"
)
if old in t:
    p.write_text(t.replace(old, new))
PY
        echo "  patched $hdr"
    fi
}

echo "Applying ESP-IDF v6.0 patches to managed_components/..."
patch_uart_uhci
patch_sh8601
patch_esp_video_ioctl
echo "Done."
