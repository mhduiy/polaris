// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QtGlobal>

#include <dlfcn.h>

#include <optional>

/**
 * @brief The graphics card's power draw, through NVML.
 *
 * NVML is opened at runtime rather than linked: the driver library is optional,
 * and neither a machine without an NVIDIA card nor a build without the driver
 * headers should care that this exists. A single call costs microseconds, so it
 * can ride along with the other readings every interval.
 *
 * No privileges are needed — the same query works as a normal user, which is why
 * this lives in the applet rather than in the helper service.
 */
namespace polaris {

struct GpuPower
{
    QString name;
    qreal watts = 0;
};

inline std::optional<GpuPower> readGpuPower()
{
    using InitFn = int (*)();
    using ShutdownFn = int (*)();
    using CountFn = int (*)(unsigned int *);
    using HandleFn = int (*)(unsigned int, void **);
    using NameFn = int (*)(void *, char *, unsigned int);
    using PowerFn = int (*)(void *, unsigned int *);

    // Opened once: the library is either there for the life of the process or it
    // is not, and a failed open must not be retried every two seconds.
    static void *library = ::dlopen("libnvidia-ml.so.1", RTLD_LAZY | RTLD_LOCAL);
    if (!library)
        return std::nullopt;

    static auto init = reinterpret_cast<InitFn>(::dlsym(library, "nvmlInit_v2"));
    static auto handleAt = reinterpret_cast<HandleFn>(::dlsym(library, "nvmlDeviceGetHandleByIndex_v2"));
    static auto nameOf = reinterpret_cast<NameFn>(::dlsym(library, "nvmlDeviceGetName"));
    static auto powerOf = reinterpret_cast<PowerFn>(::dlsym(library, "nvmlDeviceGetPowerUsage"));
    if (!init || !handleAt || !nameOf || !powerOf)
        return std::nullopt;

    static const bool initialised = [] {
        return init() == 0; // NVML_SUCCESS
    }();
    if (!initialised)
        return std::nullopt;

    void *device = nullptr;
    if (handleAt(0, &device) != 0 || !device)
        return std::nullopt;

    unsigned int milliwatts = 0;
    if (powerOf(device, &milliwatts) != 0)
        return std::nullopt;

    char buffer[96] = {};
    GpuPower power;
    power.watts = qreal(milliwatts) / 1000.0;
    power.name = nameOf(device, buffer, sizeof(buffer)) == 0 ? QString::fromUtf8(buffer) : QString();
    return power;
}

} // namespace polaris
