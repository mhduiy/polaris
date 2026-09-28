// SPDX-License-Identifier: GPL-3.0-or-later

#include "polarisapplet.h"

#include "pluginfactory.h"
#include "gpureader.h"
#include "systemreader.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QStandardPaths>
#include <QVariantMap>

#include <DConfig>

#include <algorithm>
#include <sys/syscall.h>

#include <csignal>
#include <unistd.h>

DS_USE_NAMESPACE

namespace {

// The applet and the control centre plugin share this schema: neither owns the
// other, they only agree on the same DConfig app id.
const QString kConfigAppId = QStringLiteral("org.deepin.ds.dock.polaris");

/// What polaris-sensord publishes for the readings only root can take.
const QString kSensorPath = QStringLiteral("/run/polaris/sensors");
const QString kConfigName = QStringLiteral("org.deepin.ds.dock.polaris");

constexpr int kDefaultRefreshIntervalMs = 2000;
constexpr int kMinRefreshIntervalMs = 500;
constexpr int kMaxRefreshIntervalMs = 10000;
constexpr int kDefaultFanScaleRpm = 3000;
constexpr int kMinFanScaleRpm = 500;
constexpr int kMaxFanScaleRpm = 10000;
/// How the dock item draws its metrics, spelled the way the config stores them.
const QStringList kChartModes{QStringLiteral("off"), QStringLiteral("both"), QStringLiteral("line")};
constexpr int kDefaultProcessCount = 8;
constexpr int kMinProcessCount = 3;
constexpr int kMaxProcessCount = 30;

constexpr qreal kKiBPerGiB = 1024.0 * 1024.0;

QByteArray readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

QString usageText(quint64 usedKiB, quint64 totalKiB)
{
    return QStringLiteral("%1 / %2 GiB")
        .arg(usedKiB / kKiBPerGiB, 0, 'f', 1)
        .arg(totalKiB / kKiBPerGiB, 0, 'f', 1);
}

} // namespace

PolarisApplet::PolarisApplet(QObject *parent)
    : DApplet(parent)
{
}

PolarisApplet::~PolarisApplet() = default;

bool PolarisApplet::load()
{
    return true;
}

bool PolarisApplet::init()
{
    DApplet::init();

    m_config = Dtk::Core::DConfig::create(kConfigAppId, kConfigName, QString(), this);
    readSettings();
    if (m_config) {
        connect(m_config, &Dtk::Core::DConfig::valueChanged, this, [this](const QString &) {
            readSettings();
        });
    }

    m_temperaturePath = polaris::findCpuTemperaturePath();

    // The first CPU sample only primes the counters: usage is a delta and a
    // sample taken microseconds after this one would be pure noise.
    m_lastCpuTimes = polaris::parseCpuTimes(readFile(QStringLiteral("/proc/stat")));
    m_cpuPrimed = false;
    m_coresPrimed = false;
    m_netClock.start();
    refresh();

    m_timer.setInterval(m_refreshIntervalMs);
    connect(&m_timer, &QTimer::timeout, this, &PolarisApplet::refresh);
    m_timer.start();

    return true;
}

void PolarisApplet::readSettings()
{
    // dtk answers a key that is not in the schema with a crash rather than a
    // default, so every key is checked against the schema first.
    const auto value = [this](const QString &key, const QVariant &fallback) {
        if (!m_config || !m_config->isValid() || !m_config->keyList().contains(key))
            return fallback;
        return m_config->value(key, fallback);
    };

    const bool showCpu = value(QStringLiteral("showCpu"), true).toBool();
    const bool showTemperature = value(QStringLiteral("showTemperature"), true).toBool();
    const bool showMemory = value(QStringLiteral("showMemory"), true).toBool();
    const bool showSwap = value(QStringLiteral("showSwap"), true).toBool();
    const bool showNetwork = value(QStringLiteral("showNetwork"), true).toBool();
    const bool showPower = value(QStringLiteral("showPower"), false).toBool();
    const bool showFan = value(QStringLiteral("showFan"), false).toBool();
    const int interval = qBound(kMinRefreshIntervalMs,
                                value(QStringLiteral("refreshIntervalMs"), kDefaultRefreshIntervalMs).toInt(),
                                kMaxRefreshIntervalMs);
    const int fanScale = qBound(kMinFanScaleRpm,
                                value(QStringLiteral("fanScaleRpm"), kDefaultFanScaleRpm).toInt(),
                                kMaxFanScaleRpm);
    const int processCount = qBound(kMinProcessCount,
                                    value(QStringLiteral("processCount"), kDefaultProcessCount).toInt(),
                                    kMaxProcessCount);
    const QString sort = value(QStringLiteral("processSort"), QStringLiteral("cpu")).toString();
    // An unrecognised mode would leave the dock item drawing something nobody
    // asked for, so it falls back to the plain numbers.
    const QString chartWanted = value(QStringLiteral("dockChartMode"), kChartModes.first()).toString();
    const QString dockChartMode = kChartModes.contains(chartWanted) ? chartWanted : kChartModes.first();

    const bool fanScaleDiffers = fanScale != m_fanScaleRpm;
    const bool settingsDiffer = showCpu != m_showCpu || showTemperature != m_showTemperature
            || showMemory != m_showMemory || showSwap != m_showSwap || showNetwork != m_showNetwork
            || showPower != m_showPower || showFan != m_showFan || sort != m_processSort
            || dockChartMode != m_dockChartMode || fanScaleDiffers;
    m_showCpu = showCpu;
    m_showTemperature = showTemperature;
    m_showMemory = showMemory;
    m_showSwap = showSwap;
    m_showNetwork = showNetwork;
    m_showPower = showPower;
    m_showFan = showFan;
    m_processCount = processCount;
    m_dockChartMode = dockChartMode;
    m_fanScaleRpm = fanScale;

    if (sort != m_processSort) {
        m_processSort = sort;
        m_processOrder = sort == QLatin1String("memory") ? polaris::ProcessSort::Memory
                                                         : polaris::ProcessSort::Cpu;
        // Re-rank now rather than at the next tick: a switch the user just
        // flipped has to show up while the eye is still on it.
        if (m_processesPrimed)
            refreshProcesses(m_lastTotalTicksDelta);
    }

    if (settingsDiffer)
        Q_EMIT settingsChanged();

    if (interval != m_refreshIntervalMs) {
        m_refreshIntervalMs = interval;
        if (m_timer.isActive())
            m_timer.setInterval(interval);
    }
}

void PolarisApplet::refresh()
{
    const QByteArray procStat = readFile(QStringLiteral("/proc/stat"));
    const quint64 totalDelta = refreshCpu(procStat);

    refreshMemory(readFile(QStringLiteral("/proc/meminfo")));

    // One interval for everything that measures a rate: the network counters, the
    // powercap energy counter and the cpu ticks are all sampled on this tick.
    const qint64 elapsedMs = m_netClock.restart();
    refreshNetwork(readFile(QStringLiteral("/proc/net/dev")), elapsedMs);
    refreshSystem();
    refreshSensors(elapsedMs);

    if (m_temperaturePath.isEmpty())
        m_temperaturePath = polaris::findCpuTemperaturePath();
    m_cpuTemperature = m_temperaturePath.isEmpty() ? -1 : polaris::readTemperature(m_temperaturePath);
    if (m_cpuTemperature >= 0)
        m_temperatureHistory.push(m_cpuTemperature);

    // The one reading that costs real work, and only while it is being looked at.
    if (m_panelVisible)
        refreshProcesses(totalDelta);

    Q_EMIT dataChanged();
}

quint64 PolarisApplet::refreshCpu(const QByteArray &procStat)
{
    const polaris::CpuTimes times = polaris::parseCpuTimes(procStat);

    quint64 totalDelta = 0;
    if (m_cpuPrimed && times.total > m_lastCpuTimes.total && times.idle >= m_lastCpuTimes.idle) {
        totalDelta = times.total - m_lastCpuTimes.total;
        const quint64 idleDelta = times.idle - m_lastCpuTimes.idle;
        m_cpuUsage = qBound(0.0, 1.0 - qreal(idleDelta) / qreal(totalDelta), 1.0);
        m_cpuBreakdown = polaris::cpuBreakdown(m_lastCpuTimes, times);
    }
    m_lastCpuTimes = times;
    m_cpuPrimed = true;
    m_cpuHistory.push(m_cpuUsage * 100.0);

    // Per-core usage needs the same two samples the aggregate does; a machine
    // that reports a different core count than last time (hotplug) only gets a
    // fresh baseline instead of a wrong delta.
    const QList<polaris::CpuTimes> cores = polaris::parseCpuPerCore(procStat);
    if (m_coresPrimed && cores.size() == m_lastCoreTimes.size()) {
        QVariantList usage;
        usage.reserve(cores.size());
        for (int i = 0; i < cores.size(); ++i) {
            const polaris::CpuTimes &now = cores.at(i);
            const polaris::CpuTimes &before = m_lastCoreTimes.at(i);
            if (now.total > before.total && now.idle >= before.idle) {
                const quint64 coreTotal = now.total - before.total;
                const quint64 coreIdle = now.idle - before.idle;
                usage.append(qBound(0.0, 1.0 - qreal(coreIdle) / qreal(coreTotal), 1.0) * 100.0);
            } else {
                usage.append(0.0);
            }
        }
        m_cpuCores = usage;
    }
    m_lastCoreTimes = cores;
    m_coresPrimed = true;

    return totalDelta;
}

void PolarisApplet::refreshMemory(const QByteArray &memInfo)
{
    const polaris::MemInfo mem = polaris::parseMemInfo(memInfo);
    m_memory = polaris::memorySplit(mem);

    if (m_memory.total > 0)
        m_memoryUsage = qBound(0.0, qreal(m_memory.used) / qreal(m_memory.total), 1.0);
    m_memoryText = usageText(m_memory.used, m_memory.total);
    m_memoryHistory.push(m_memoryUsage * 100.0);

    m_swapUsedKiB = mem.swapTotal - mem.swapFree;
    m_swapTotalKiB = mem.swapTotal;
    if (mem.swapTotal > 0) {
        m_swapUsage = qBound(0.0, qreal(m_swapUsedKiB) / qreal(m_swapTotalKiB), 1.0);
        m_swapText = usageText(quint64(m_swapUsedKiB), quint64(m_swapTotalKiB));
        m_swapHistory.push(m_swapUsage * 100.0);
    } else {
        m_swapUsage = 0;
        m_swapText = QStringLiteral("--");
    }
}

void PolarisApplet::refreshNetwork(const QByteArray &netDev, qint64 elapsedMs)
{
    // Counters are cumulative: the rate is the delta over the time actually
    // elapsed between two samples, which is not exactly the timer interval.
    const polaris::NetCounters net = polaris::parseNetDev(netDev);
    if (m_netPrimed) {
        // The first sample only primes the counters: a delta against zero would
        // be everything the machine has transferred since it booted.
        if (const std::optional<polaris::NetCounters> rate =
                polaris::netRate({m_lastNetRx, m_lastNetTx}, net, elapsedMs)) {
            m_netDownloadRate = rate->rxBytes;
            m_netUploadRate = rate->txBytes;
        }
    }
    m_netPrimed = true;
    m_lastNetRx = net.rxBytes;
    m_lastNetTx = net.txBytes;
    m_netDownloadTotal = net.rxBytes;
    m_netUploadTotal = net.txBytes;

    m_downloadHistory.push(m_netDownloadRate);
    m_uploadHistory.push(m_netUploadRate);
}

void PolarisApplet::refreshSensors(qint64 elapsedMs)
{
    const QList<polaris::FanReading> fans = polaris::readFans();
    QVariantList fanList;
    fanList.reserve(fans.size());
    int maximum = 0;
    int ceiling = 0;
    for (const polaris::FanReading &fan : fans) {
        QVariantMap entry;
        entry.insert(QStringLiteral("name"), fan.name);
        entry.insert(QStringLiteral("rpm"), fan.rpm);
        fanList.append(entry);
        maximum = qMax(maximum, int(fan.rpm));
        ceiling = qMax(ceiling, int(fan.maxRpm));
    }
    m_fans = fanList;
    m_fanMaximum = maximum;
    m_fanCeiling = ceiling;
    m_fanHistory.push(maximum);

    // In order of what the number then means: the battery reports the whole
    // machine and always reads, the helper reports the cpu package, the powercap
    // counter reports the same thing but is root-only, and a hwmon chip reports
    // one device of its own — a gpu, usually.
    m_powerReadings.clear();
    const auto record = [this](const QString &source, qreal watts) {
        QVariantMap entry;
        entry.insert(QStringLiteral("source"), source);
        entry.insert(QStringLiteral("watts"), watts);
        m_powerReadings.append(entry);
    };
    // The graphics card does not need the helper — the driver answers a normal
    // user — so it is recorded whatever the other sources do.
    const auto recordGpu = [&record] {
        if (const std::optional<polaris::GpuPower> gpu = polaris::readGpuPower())
            record(gpu->name.isEmpty() ? QStringLiteral("gpu") : gpu->name, gpu->watts);
    };

    if (const std::optional<qreal> battery = polaris::readBatteryPowerWatts()) {
        m_powerWatts = *battery;
        m_powerSource = QStringLiteral("battery");
        m_powerHistory.push(m_powerWatts);
        record(m_powerSource, m_powerWatts);
        recordGpu();
        return;
    }

    // The helper package publishes what we cannot read ourselves. Its file is
    // only believed while it is fresh: a stopped daemon leaves its last reading
    // behind, and yesterday's watts are worse than none.
    const polaris::SensorReadings published = polaris::parseSensorReadings(readFile(kSensorPath));
    if (published.hasPower
        && polaris::sensorReadingsFresh(published, QDateTime::currentSecsSinceEpoch())) {
        m_powerWatts = published.powerWatts;
        m_powerSource = published.powerSource.isEmpty() ? QStringLiteral("daemon") : published.powerSource;
        m_powerHistory.push(m_powerWatts);
        record(m_powerSource, m_powerWatts);
        recordGpu();
        return;
    }

    if (m_energyDir.isEmpty())
        m_energyDir = polaris::findEnergyCounterDir();
    if (!m_energyDir.isEmpty()) {
        const std::optional<polaris::EnergyCounter> counter = polaris::readEnergyCounter(m_energyDir);
        if (counter) {
            if (m_lastEnergy) {
                if (const std::optional<qreal> watts = polaris::energyWatts(*m_lastEnergy, *counter, elapsedMs)) {
                    m_powerWatts = *watts;
                    m_powerSource = QStringLiteral("rapl");
                    m_powerHistory.push(m_powerWatts);
                    record(m_powerSource, m_powerWatts);
                }
            }
            m_lastEnergy = counter;
            recordGpu();
            return;
        }
    }
    m_lastEnergy.reset();

    if (const std::optional<polaris::PowerReading> chip = polaris::readHwmonPower()) {
        m_powerWatts = chip->watts;
        m_powerSource = chip->source;
        m_powerHistory.push(m_powerWatts);
        record(m_powerSource, m_powerWatts);
        recordGpu();
        return;
    }

    m_powerWatts = -1;
    m_powerSource.clear();
    recordGpu();
}

void PolarisApplet::refreshSystem()
{
    m_uptimeSeconds = polaris::parseUptimeSeconds(readFile(QStringLiteral("/proc/uptime")));

    QVariantList loads;
    const QList<qreal> average = polaris::parseLoadAverage(readFile(QStringLiteral("/proc/loadavg")));
    loads.reserve(average.size());
    for (const qreal load : average)
        loads.append(load);
    m_loadAverage = loads;
}

void PolarisApplet::setPanelVisible(bool visible)
{
    if (m_panelVisible == visible)
        return;

    m_panelVisible = visible;
    if (m_panelVisible)
        refreshProcesses(m_lastTotalTicksDelta); // so the panel opens with data, not empty
}

void PolarisApplet::refreshProcesses(quint64 totalTicksDelta)
{
    const qreal pageSize = qreal(sysconf(_SC_PAGESIZE));
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    // Coming back after a pause, the ticks recorded last time are minutes old:
    // that sample is a fresh baseline, and the shares appear one interval later.
    const bool continuous = polaris::processSampleContinuous(m_processesPrimed, nowMs - m_lastProcessSampleMs,
                                                             m_refreshIntervalMs);
    m_lastProcessSampleMs = nowMs;

    const QList<polaris::ProcessStat> sampled = polaris::sampleProcesses();

    QHash<int, quint64> ticks;
    QHash<int, QString> names;
    QHash<int, quint64> startTicks;
    ticks.reserve(sampled.size());
    names.reserve(sampled.size());
    startTicks.reserve(sampled.size());
    for (const polaris::ProcessStat &stat : sampled) {
        ticks.insert(stat.pid, stat.cpuTicks);
        names.insert(stat.pid, stat.name);
        startTicks.insert(stat.pid, stat.startTicks);
    }

    // The first sample has no previous ticks to subtract, so every process would
    // look idle; the memory column is still meaningful then.
    const QList<polaris::RankedProcess> ranked =
            polaris::rankProcesses(sampled,
                                   continuous ? m_lastProcessTicks : QHash<int, quint64>(),
                                   continuous ? totalTicksDelta : 0,
                                   m_processCount,
                                   m_processOrder);

    m_lastTotalTicksDelta = totalTicksDelta;
    m_lastProcessTicks = ticks;
    m_processNames = names;
    m_processStartTicks = startTicks;
    m_processesPrimed = true;

    QVariantList processes;
    processes.reserve(ranked.size());
    for (const polaris::RankedProcess &process : ranked) {
        QVariantMap entry;
        entry.insert(QStringLiteral("pid"), process.stat.pid);
        entry.insert(QStringLiteral("name"), process.stat.name);
        entry.insert(QStringLiteral("cpu"), process.cpuPercent);
        entry.insert(QStringLiteral("memory"), qreal(process.stat.rssPages) * pageSize);
        processes.append(entry);
    }

    m_processes = processes;
    Q_EMIT processesChanged();
}

namespace {

/**
 * @brief Signals a process through a pidfd, so the kernel signals the process the
 * descriptor refers to rather than whatever holds that pid by now.
 *
 * Opened first and checked afterwards: if the process exited in between, the
 * descriptor refers to a process that no longer runs — signalling it does
 * nothing — while the check below rejects it. Returns nothing when the kernel
 * has no pidfd support, and the caller falls back to kill(2).
 */
std::optional<bool> signalThroughPidfd(int pid, int signal)
{
#if defined(SYS_pidfd_open) && defined(SYS_pidfd_send_signal)
    const int descriptor = int(::syscall(SYS_pidfd_open, pid, 0));
    if (descriptor < 0)
        return std::nullopt;

    const bool signalled = ::syscall(SYS_pidfd_send_signal, descriptor, signal, nullptr, 0) == 0;
    ::close(descriptor);
    return signalled;
#else
    Q_UNUSED(pid)
    Q_UNUSED(signal)
    return std::nullopt;
#endif
}

} // namespace

bool PolarisApplet::killProcess(int pid)
{
    // Init is not a process anyone gets to signal from a taskbar, and neither
    // is the shell we run inside of.
    if (pid <= 1 || pid == int(QCoreApplication::applicationPid()))
        return false;

    // Between filling the panel and the click the pid may have been recycled by
    // another program, so the name and the start time both have to still match.
    const QString path = QStringLiteral("/proc/%1/stat").arg(pid);
    const std::optional<polaris::ProcessStat> stat = polaris::parseProcessStat(readFile(path));
    if (!polaris::sameProcess(pid, stat, m_processNames.value(pid), m_processStartTicks.value(pid)))
        return false;

    if (const std::optional<bool> throughPidfd = signalThroughPidfd(pid, SIGTERM))
        return *throughPidfd;

    // No pidfd: the name check above is the only guard, and the window between
    // it and this call is one syscall wide.
    return ::kill(pid, SIGTERM) == 0;
}

void PolarisApplet::setProcessSort(const QString &sort)
{
    if (sort != QLatin1String("cpu") && sort != QLatin1String("memory"))
        return;

    // The setting is the single source of truth, so the control centre page and
    // the dock agree; readSettings() then re-ranks through the usual path.
    if (!m_config || !m_config->isValid() || !m_config->keyList().contains(QStringLiteral("processSort"))) {
        m_processSort = sort;
        m_processOrder = sort == QLatin1String("memory") ? polaris::ProcessSort::Memory
                                                         : polaris::ProcessSort::Cpu;
        if (m_processesPrimed)
            refreshProcesses(m_lastTotalTicksDelta);
        Q_EMIT settingsChanged();
        return;
    }

    m_config->setValue(QStringLiteral("processSort"), sort);
}

D_APPLET_CLASS(PolarisApplet)

#include "polarisapplet.moc"
