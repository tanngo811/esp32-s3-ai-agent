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
