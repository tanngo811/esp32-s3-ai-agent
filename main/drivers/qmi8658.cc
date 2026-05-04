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
    WriteReg(REG_CTRL2, 0x95); // accel ±2g, 250 Hz ODR
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
