// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "applet.h"
#include "dsglobal.h"
#include "systemreader.h"

#include <QElapsedTimer>
#include <QHash>
#include <QTimer>
#include <QVariantList>

namespace Dtk {
namespace Core {
class DConfig;
}
} // namespace Dtk::Core

DS_BEGIN_NAMESPACE

/**
 * @brief Dock applet showing live CPU / memory / swap / CPU-temperature /
 * network throughput, and the running processes behind a click.
 *
 * All values are read from /proc and /sys, so the plugin needs no daemon and
 * no privileges. Which metrics are shown and how often they refresh comes from
 * the DConfig schema shared with the control centre plugin.
 */
class PolarisApplet : public DApplet
{
    Q_OBJECT
    // 0.0 - 1.0
    Q_PROPERTY(qreal cpuUsage READ cpuUsage NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal memoryUsage READ memoryUsage NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal swapUsage READ swapUsage NOTIFY dataChanged FINAL)
    // Degrees Celsius, -1 when no sensor is available.
    Q_PROPERTY(qreal cpuTemperature READ cpuTemperature NOTIFY dataChanged FINAL)
    // Bytes per second across the physical interfaces.
    Q_PROPERTY(qreal netDownloadRate READ netDownloadRate NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal netUploadRate READ netUploadRate NOTIFY dataChanged FINAL)
    // Human readable "used / total GiB" pairs for the tooltip.
    Q_PROPERTY(QString memoryText READ memoryText NOTIFY dataChanged FINAL)
    Q_PROPERTY(QString swapText READ swapText NOTIFY dataChanged FINAL)

    // Which metrics the dock item shows, from the control centre settings.
    Q_PROPERTY(bool showCpu READ showCpu NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool showTemperature READ showTemperature NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool showMemory READ showMemory NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool showSwap READ showSwap NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool showNetwork READ showNetwork NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool showPower READ showPower NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool showFan READ showFan NOTIFY settingsChanged FINAL)
    // How the dock item draws its metrics: "off", "both" or "line". The history
    // it draws comes from the same per-metric switches as the numbers.
    Q_PROPERTY(QString dockChartMode READ dockChartMode NOTIFY settingsChanged FINAL)

    // The detail panel behind a click: where the cpu time went, what the memory
    // is spent on, how the machine is doing, and the recent history the charts
    // draw. All of it is filled by the same one sample per interval.
    Q_PROPERTY(qreal cpuUserPercent READ cpuUserPercent NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal cpuSystemPercent READ cpuSystemPercent NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal cpuIowaitPercent READ cpuIowaitPercent NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal cpuIdlePercent READ cpuIdlePercent NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList cpuCores READ cpuCores NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList cpuHistory READ cpuHistory NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList temperatureHistory READ temperatureHistory NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal memoryUsedKiB READ memoryUsedKiB NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal memoryCacheKiB READ memoryCacheKiB NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal memoryTotalKiB READ memoryTotalKiB NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal swapUsedKiB READ swapUsedKiB NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal swapTotalKiB READ swapTotalKiB NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList memoryHistory READ memoryHistory NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList swapHistory READ swapHistory NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList downloadHistory READ downloadHistory NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList uploadHistory READ uploadHistory NOTIFY dataChanged FINAL)
    // Bytes since boot, and how long the machine has been up.
    Q_PROPERTY(qreal netDownloadTotal READ netDownloadTotal NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal netUploadTotal READ netUploadTotal NOTIFY dataChanged FINAL)
    Q_PROPERTY(qreal uptimeSeconds READ uptimeSeconds NOTIFY dataChanged FINAL)
    // Watts the package draws, -1 when the kernel does not expose it to us, and
    // the fans hwmon reports with the highest of them for the dock line.
    Q_PROPERTY(qreal powerWatts READ powerWatts NOTIFY dataChanged FINAL)
    Q_PROPERTY(QString powerSource READ powerSource NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList fans READ fans NOTIFY dataChanged FINAL)
    Q_PROPERTY(int fanMaximum READ fanMaximum NOTIFY dataChanged FINAL)
    // The ceiling for the fan gauges: what the chips report, or the setting.
    Q_PROPERTY(int fanCeiling READ fanCeiling NOTIFY dataChanged FINAL)
    Q_PROPERTY(int fanScaleRpm READ fanScaleRpm NOTIFY settingsChanged FINAL)
    // Every power source that answered, the first one being what the dock line
    // shows: [{ source, watts }].
    Q_PROPERTY(QVariantList powerReadings READ powerReadings NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList powerHistory READ powerHistory NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList fanHistory READ fanHistory NOTIFY dataChanged FINAL)
    Q_PROPERTY(QVariantList loadAverage READ loadAverage NOTIFY dataChanged FINAL)
    Q_PROPERTY(int cpuCoreCount READ cpuCoreCount NOTIFY dataChanged FINAL)

    // The busiest processes, cpu in percent of the whole machine and memory in
    // bytes, sorted by whichever figure the settings ask for.
    Q_PROPERTY(QVariantList processes READ processes NOTIFY processesChanged FINAL)
    Q_PROPERTY(QString processSort READ processSort NOTIFY settingsChanged FINAL)

public:
    explicit PolarisApplet(QObject *parent = nullptr);
    ~PolarisApplet() override;

    bool load() override;
    bool init() override;

    qreal cpuUsage() const { return m_cpuUsage; }
    qreal memoryUsage() const { return m_memoryUsage; }
    qreal swapUsage() const { return m_swapUsage; }
    qreal cpuTemperature() const { return m_cpuTemperature; }
    qreal netDownloadRate() const { return m_netDownloadRate; }
    qreal netUploadRate() const { return m_netUploadRate; }
    QString memoryText() const { return m_memoryText; }
    QString swapText() const { return m_swapText; }

    bool showCpu() const { return m_showCpu; }
    bool showTemperature() const { return m_showTemperature; }
    bool showMemory() const { return m_showMemory; }
    bool showSwap() const { return m_showSwap; }
    bool showNetwork() const { return m_showNetwork; }
    bool showPower() const { return m_showPower; }
    bool showFan() const { return m_showFan; }
    QVariantList processes() const { return m_processes; }
    QString processSort() const { return m_processSort; }

    qreal cpuUserPercent() const { return m_cpuBreakdown.user; }
    qreal cpuSystemPercent() const { return m_cpuBreakdown.system; }
    qreal cpuIowaitPercent() const { return m_cpuBreakdown.iowait; }
    qreal cpuIdlePercent() const { return m_cpuBreakdown.idle; }
    QVariantList cpuCores() const { return m_cpuCores; }
    QVariantList cpuHistory() const { return m_cpuHistory.values(); }
    QVariantList temperatureHistory() const { return m_temperatureHistory.values(); }
    qreal memoryUsedKiB() const { return m_memory.used; }
    qreal memoryCacheKiB() const { return m_memory.cache; }
    qreal memoryTotalKiB() const { return m_memory.total; }
    qreal swapUsedKiB() const { return m_swapUsedKiB; }
    qreal swapTotalKiB() const { return m_swapTotalKiB; }
    QVariantList memoryHistory() const { return m_memoryHistory.values(); }
    QVariantList swapHistory() const { return m_swapHistory.values(); }
    QVariantList downloadHistory() const { return m_downloadHistory.values(); }
    QVariantList uploadHistory() const { return m_uploadHistory.values(); }
    qreal netDownloadTotal() const { return m_netDownloadTotal; }
    qreal netUploadTotal() const { return m_netUploadTotal; }
    qreal uptimeSeconds() const { return m_uptimeSeconds; }
    qreal powerWatts() const { return m_powerWatts; }
    QString powerSource() const { return m_powerSource; }
    QVariantList fans() const { return m_fans; }
    int fanMaximum() const { return m_fanMaximum; }
    int fanCeiling() const { return m_fanCeiling; }
    QString dockChartMode() const { return m_dockChartMode; }
    int fanScaleRpm() const { return m_fanScaleRpm; }
    QVariantList powerReadings() const { return m_powerReadings; }
    QVariantList powerHistory() const { return m_powerHistory.values(); }
    QVariantList fanHistory() const { return m_fanHistory.values(); }
    QVariantList loadAverage() const { return m_loadAverage; }
    int cpuCoreCount() const { return m_cpuCores.size(); }

    /// Asks the process with this pid to terminate. False when it is gone, is
    /// not ours to signal, or is no longer the process that was listed.
    Q_INVOKABLE bool killProcess(int pid);

    /// Tells the applet whether the panel is on screen. The process table is the
    /// only reading that costs anything to take — one /proc/<pid>/stat per
    /// process, about 7 ms on a busy machine — so it is sampled only while
    /// something is showing it.
    Q_INVOKABLE void setPanelVisible(bool visible);

    /// Orders the process list by "cpu" or "memory". Anything else is ignored,
    /// and the choice is stored with the other settings so the panel remembers
    /// it and the control centre shows it.
    Q_INVOKABLE void setProcessSort(const QString &sort);

Q_SIGNALS:
    void dataChanged();
    void settingsChanged();
    void processesChanged();

private:
    /// One sample: reads everything the dock item and the detail panel show.
    void refresh();
    /// Each of these fills its part of the sample and pushes to the history.
    quint64 refreshCpu(const QByteArray &procStat);
    void refreshMemory(const QByteArray &memInfo);
    void refreshNetwork(const QByteArray &netDev, qint64 elapsedMs);
    void refreshSystem();
    /// Fans from hwmon and power from hwmon or the powercap energy counter.
    void refreshSensors(qint64 elapsedMs);
    void refreshProcesses(quint64 totalTicksDelta);
    void readSettings();

    QTimer m_timer;
    QElapsedTimer m_netClock;
    Dtk::Core::DConfig *m_config = nullptr;
    QString m_temperaturePath;
    qreal m_cpuUsage = 0;
    qreal m_memoryUsage = 0;
    qreal m_swapUsage = 0;
    qreal m_cpuTemperature = -1;
    qreal m_netDownloadRate = 0;
    qreal m_netUploadRate = 0;
    QString m_memoryText;
    QString m_swapText;
    QVariantList m_processes;
    polaris::CpuBreakdown m_cpuBreakdown;
    polaris::MemorySplit m_memory;
    QList<polaris::CpuTimes> m_lastCoreTimes;
    QVariantList m_cpuCores;
    QVariantList m_loadAverage;
    polaris::History m_cpuHistory;
    polaris::History m_temperatureHistory;
    polaris::History m_memoryHistory;
    polaris::History m_swapHistory;
    polaris::History m_downloadHistory;
    polaris::History m_uploadHistory;
    polaris::History m_powerHistory;
    polaris::History m_fanHistory;
    QVariantList m_fans;
    std::optional<polaris::EnergyCounter> m_lastEnergy;
    QString m_energyDir;
    QString m_powerSource;
    qreal m_powerWatts = -1;
    int m_fanMaximum = 0;
    int m_fanCeiling = 0;
    QVariantList m_powerReadings;
    qreal m_swapUsedKiB = 0;
    qreal m_swapTotalKiB = 0;
    qreal m_netDownloadTotal = 0;
    qreal m_netUploadTotal = 0;
    qreal m_uptimeSeconds = 0;
    bool m_coresPrimed = false;
    /// Cumulative cpu ticks per pid from the previous sample, and the command
    /// name the pid had then: a pid is only ours to kill while both still match.
    QHash<int, quint64> m_lastProcessTicks;
    QHash<int, QString> m_processNames;
    /// Start time per pid from the same sample: with the name it identifies the
    /// process, so a recycled pid cannot be signalled by mistake.
    QHash<int, quint64> m_processStartTicks;
    polaris::CpuTimes m_lastCpuTimes;
    quint64 m_lastNetRx = 0;
    quint64 m_lastNetTx = 0;
    bool m_cpuPrimed = false;
    bool m_netPrimed = false;
    bool m_processesPrimed = false;
    bool m_panelVisible = false;
    qint64 m_lastProcessSampleMs = 0;
    bool m_showCpu = true;
    bool m_showTemperature = true;
    bool m_showMemory = true;
    bool m_showSwap = true;
    bool m_showNetwork = true;
    bool m_showPower = false;
    bool m_showFan = false;
    /// "off", "both" or "line" — how the dock item draws its metrics.
    QString m_dockChartMode = QStringLiteral("off");
    int m_refreshIntervalMs = 2000;
    int m_processCount = 8;
    int m_fanScaleRpm = 3000;
    /// "cpu" or "memory", as the process list and the control centre see it.
    QString m_processSort = QStringLiteral("cpu");
    polaris::ProcessSort m_processOrder = polaris::ProcessSort::Cpu;
    /// The last machine-wide tick delta, so a sort change can re-rank the list
    /// right away instead of waiting for the next sample.
    quint64 m_lastTotalTicksDelta = 0;
};

DS_END_NAMESPACE
