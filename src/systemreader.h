// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QList>
#include <QString>
#include <QStringList>
#include <QtGlobal>

#include <optional>
#include <functional>

#include <QHash>
#include <algorithm>

/**
 * @brief Pure readers for the kernel interfaces used by the polaris applet.
 *
 * Kept header-only and free of applet dependencies so the parsing can be
 * checked with tests/test_systemreader.cpp.
 */
namespace polaris {

namespace detail {
/// The whole contents of a file, or nothing when it cannot be read. sysfs files
/// are small and single-valued, so this is all the reading any of this needs.
inline QByteArray readWholeFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}
} // namespace detail

struct CpuTimes
{
    quint64 total = 0;
    /// Idle *and* iowait: the time the CPU had nothing to run. iowait counts as
    /// not-busy here because top, vmstat, htop and psutil all agree that a CPU
    /// waiting on I/O is not busy. Usage is then 1 - idle / total.
    quint64 idle = 0;

    // The individual buckets, for the detail panel's breakdown bar.
    quint64 user = 0;   // user + nice
    quint64 system = 0; // system + irq + softirq
    quint64 iowait = 0;
    quint64 idleOnly = 0;
    quint64 steal = 0;
};

struct CpuBreakdown
{
    /// Percentage of the elapsed cpu time each bucket took; the four add up to
    /// 100 on a machine that has been up for more than one sample.
    qreal user = 0;
    qreal system = 0;
    qreal iowait = 0;
    qreal idle = 0;
};

/**
 * @brief Parses the aggregate CPU counters out of /proc/stat.
 *
 * Takes the whole file, not a single line: /proc/stat continues with per-CPU
 * lines and with counters such as intr/softirq, and none of those may be added
 * on top of the aggregate line.
 */
inline CpuTimes parseCpuTimes(const QByteArray &procStatContents)
{
    CpuTimes times;

    // Only the leading aggregate line. /proc/stat terminates every line with a
    // newline, but do not depend on it: Qt clamps left(-1) to an empty array.
    const qsizetype lineEnd = procStatContents.indexOf('\n');
    const QByteArray line = lineEnd < 0 ? procStatContents : procStatContents.left(lineEnd);
    const QList<QByteArray> fields = line.simplified().split(' ');
    if (fields.size() < 9 || fields.first() != "cpu")
        return times;

    // user nice system idle iowait irq softirq steal [guest guest_nice]
    // guest and guest_nice are already accounted in user and nice, so summing
    // them would count virtual-machine time twice.
    for (int i = 1; i <= 8; ++i) {
        bool ok = false;
        const quint64 value = fields.at(i).toULongLong(&ok);
        if (!ok)
            continue;
        times.total += value;
        switch (i) {
        case 1: // user
            times.user += value;
            break;
        case 2: // nice
            times.user += value;
            break;
        case 3: // system
            times.system += value;
            break;
        case 4: // idle
            times.idleOnly += value;
            break;
        case 5: // iowait
            times.iowait += value;
            break;
        case 6: // irq
            times.system += value;
            break;
        case 7: // softirq
            times.system += value;
            break;
        case 8: // steal: time the hypervisor took away from us
            times.steal += value;
            break;
        default:
            break;
        }
        if (i == 4 || i == 5) // idle + iowait
            times.idle += value;
    }
    return times;
}

/**
 * @brief Every CPU's counters, from the "cpu0 ..." lines of /proc/stat.
 *
 * Returns them in the order the kernel lists them, which is "cpu0", "cpu1",
 * "cpu10", "cpu11", ... in a plain string sort.
 */
inline QList<CpuTimes> parseCpuPerCore(const QByteArray &procStatContents)
{
    QList<CpuTimes> cores;
    const QList<QByteArray> lines = procStatContents.split('\n');
    for (const QByteArray &line : lines) {
        if (!line.startsWith("cpu") || line.startsWith("cpu "))
            continue;

        const QList<QByteArray> fields = line.simplified().split(' ');
        if (fields.size() < 9)
            continue;

        CpuTimes times;
        bool complete = true;
        for (int i = 1; i <= 8 && complete; ++i) {
            bool ok = false;
            const quint64 value = fields.at(i).toULongLong(&ok);
            if (!ok) {
                complete = false;
                break;
            }
            times.total += value;
            if (i == 4 || i == 5)
                times.idle += value;
        }
        if (complete)
            cores.append(times);
    }
    return cores;
}

/// How the elapsed cpu time was spent between two samples, in percent.
inline CpuBreakdown cpuBreakdown(const CpuTimes &previous, const CpuTimes &current)
{
    const auto delta = [](quint64 now, quint64 before) {
        return now >= before ? now - before : quint64(0);
    };

    const quint64 user = delta(current.user, previous.user);
    const quint64 system = delta(current.system, previous.system);
    const quint64 iowait = delta(current.iowait, previous.iowait);
    const quint64 idle = delta(current.idleOnly, previous.idleOnly) + delta(current.steal, previous.steal);
    const quint64 total = user + system + iowait + idle;
    if (total == 0)
        return {};

    const qreal scale = 100.0 / qreal(total);
    return {qreal(user) * scale, qreal(system) * scale, qreal(iowait) * scale, qreal(idle) * scale};
}

struct MemInfo
{
    quint64 memTotal = 0;
    quint64 memFree = 0;
    quint64 memAvailable = 0;
    quint64 buffers = 0;
    quint64 cached = 0;
    quint64 swapTotal = 0;
    quint64 swapFree = 0;
};

/// How the memory is spent, the way free(1) splits it: the three add up to the
/// total, which is what makes the detail panel's bar honest.
struct MemorySplit
{
    quint64 used = 0;
    quint64 cache = 0;
    quint64 free = 0;
    quint64 total = 0;
};

inline MemorySplit memorySplit(const MemInfo &info)
{
    const quint64 free = qMin(info.memFree, info.memTotal);
    // Cache cannot exceed what is left once the free pages are accounted for, so
    // a nonsensical /proc/meminfo cannot make the parts overshoot the total.
    const quint64 cache = qMin(info.buffers + info.cached, info.memTotal - free);
    return {info.memTotal - free - cache, cache, free, info.memTotal};
}

/// Seconds since boot, from /proc/uptime's first field.
inline qreal parseUptimeSeconds(const QByteArray &procUptimeContents)
{
    bool ok = false;
    const qreal seconds = procUptimeContents.simplified().split(' ').value(0).toDouble(&ok);
    return ok ? seconds : 0;
}

/// The three load averages, from /proc/loadavg.
inline QList<qreal> parseLoadAverage(const QByteArray &procLoadavgContents)
{
    const QList<QByteArray> fields = procLoadavgContents.simplified().split(' ');
    QList<qreal> loads;
    loads.reserve(3);
    for (int i = 0; i < 3 && i < fields.size(); ++i) {
        bool ok = false;
        const qreal load = fields.at(i).toDouble(&ok);
        if (!ok)
            return {};
        loads.append(load);
    }
    return loads;
}

/**
 * @brief A fixed-length series for the detail panel's charts, oldest first.
 *
 * The charts draw the newest sample at their right edge and keep the x scale
 * fixed at the capacity, so a half-filled history grows from the right instead
 * of being stretched over the whole width.
 */
class History
{
public:
    explicit History(int capacity = 60)
        : m_capacity(qMax(1, capacity))
    {
    }

    void push(qreal value)
    {
        m_values.append(value);
        if (m_values.size() > m_capacity)
            m_values.remove(0, m_values.size() - m_capacity);
    }

    int capacity() const { return m_capacity; }
    QVariantList values() const
    {
        QVariantList list;
        list.reserve(m_values.size());
        for (const qreal value : m_values)
            list.append(value);
        return list;
    }
    qreal maximum() const
    {
        qreal maximum = 0;
        for (const qreal value : m_values)
            maximum = qMax(maximum, value);
        return maximum;
    }

private:
    QList<qreal> m_values;
    int m_capacity;
};

/// Parses the contents of /proc/meminfo. Values are in KiB.
inline MemInfo parseMemInfo(const QByteArray &content)
{
    MemInfo info;
    const QList<QByteArray> lines = content.split('\n');
    for (const QByteArray &rawLine : lines) {
        const QList<QByteArray> parts = rawLine.simplified().split(' ');
        if (parts.size() < 2)
            continue;

        bool ok = false;
        const quint64 value = parts.at(1).toULongLong(&ok);
        if (!ok)
            continue;

        // /proc/meminfo keys carry a trailing colon, e.g. "MemTotal:".
        QByteArray key = parts.first();
        if (key.endsWith(':'))
            key.chop(1);

        if (key == "MemTotal")
            info.memTotal = value;
        else if (key == "MemFree")
            info.memFree = value;
        else if (key == "MemAvailable")
            info.memAvailable = value;
        else if (key == "Buffers")
            info.buffers = value;
        else if (key == "Cached")
            info.cached = value;
        else if (key == "SwapTotal")
            info.swapTotal = value;
        else if (key == "SwapFree")
            info.swapFree = value;
    }
    return info;
}

struct NetCounters
{
    quint64 rxBytes = 0;
    quint64 txBytes = 0;
    /// Interfaces that contributed, so callers can tell "no traffic" from
    /// "nothing matched the filter".
    int interfaces = 0;
};

/**
 * @brief Whether an interface carries its own bytes on the wire.
 *
 * A driver-bound interface has a /sys/class/net/<name>/device link. Everything
 * without one is stacked on top of another interface and therefore only moves
 * bytes that interface has already counted: loopback, bridges, bonds, VLAN
 * subinterfaces, container veth pairs, VM taps and VPN tunnels such as
 * tailscale0, wg0 or tun0. Adding those on top of their parent would report up
 * to twice the traffic that actually crossed the wire.
 */
inline bool isHardwareInterface(const QString &name)
{
    return name != QLatin1String("lo")
            && QFile::exists(QStringLiteral("/sys/class/net/%1/device").arg(name));
}

/// Loopback never leaves the machine, so it is never traffic.
inline bool isNotLoopback(const QString &name)
{
    return name != QLatin1String("lo");
}

/**
 * @brief Sums the byte counters of /proc/net/dev for the counted interfaces.
 *
 * The default filter is isHardwareInterface(); when that matches nothing — a
 * driver that does not expose the device link, a modem-only link such as ppp0 —
 * everything but loopback is counted instead of reporting no traffic at all.
 */
inline NetCounters parseNetDev(const QByteArray &procNetDevContents,
                               const std::function<bool(const QString &)> &countInterface = nullptr)
{
    QList<QPair<QString, NetCounters>> interfaces;
    interfaces.reserve(8);

    const QList<QByteArray> lines = procNetDevContents.split('\n');
    for (const QByteArray &line : lines) {
        // The two header lines carry no interface name, hence no colon.
        const qsizetype colon = line.indexOf(':');
        if (colon < 0)
            continue;

        const QString name = QString::fromLatin1(line.left(colon)).trimmed();
        if (name.isEmpty())
            continue;

        // rx: bytes packets errs drop fifo frame compressed multicast
        // tx: bytes packets errs drop fifo colls carrier compressed
        const QList<QByteArray> fields = line.mid(colon + 1).simplified().split(' ');
        if (fields.size() < 9)
            continue;

        bool rxOk = false;
        bool txOk = false;
        const quint64 rx = fields.at(0).toULongLong(&rxOk);
        const quint64 tx = fields.at(8).toULongLong(&txOk);
        // A truncated line must not contribute half a counter.
        if (!rxOk || !txOk)
            continue;

        interfaces.append({name, NetCounters{rx, tx, 1}});
    }

    const std::function<bool(const QString &)> counted = countInterface ? countInterface : isHardwareInterface;

    NetCounters totals;
    for (const auto &[name, counters] : interfaces) {
        if (!counted(name))
            continue;
        totals.rxBytes += counters.rxBytes;
        totals.txBytes += counters.txBytes;
        ++totals.interfaces;
    }

    if (totals.interfaces == 0 && !countInterface) {
        for (const auto &[name, counters] : interfaces) {
            if (!isNotLoopback(name))
                continue;
            totals.rxBytes += counters.rxBytes;
            totals.txBytes += counters.txBytes;
            ++totals.interfaces;
        }
    }
    return totals;
}

/**
 * @brief Bytes per second between two samples of parseNetDev().
 *
 * Returns nothing when the samples cannot be compared: a smaller counter means
 * an interface went away between them — reporting that as a rate would show a
 * negative or an absurd spike — and a non-positive interval has no rate at all.
 */
inline std::optional<NetCounters> netRate(const NetCounters &previous, const NetCounters &current, qint64 elapsedMs)
{
    if (elapsedMs <= 0 || current.rxBytes < previous.rxBytes || current.txBytes < previous.txBytes)
        return std::nullopt;

    const auto perSecond = [elapsedMs](quint64 delta) {
        return static_cast<quint64>(qreal(delta) * 1000.0 / qreal(elapsedMs));
    };
    return NetCounters{perSecond(current.rxBytes - previous.rxBytes), perSecond(current.txBytes - previous.txBytes)};
}

struct ProcessStat
{
    int pid = -1;
    /// The command name from /proc/<pid>/stat, i.e. what the kernel calls it.
    QString name;
    /// utime + stime, in clock ticks since the process started.
    quint64 cpuTicks = 0;
    /// Resident set size in pages; multiply by the page size for bytes.
    quint64 rssPages = 0;
    /// Since when the process has been running, in clock ticks since boot. A pid
    /// is recycled the moment its process exits, so this is what tells two
    /// processes that share a pid apart — a name alone does not.
    quint64 startTicks = 0;
};

/**
 * @brief Parses one /proc/<pid>/stat record.
 *
 * The command name sits in parentheses and may contain spaces and parentheses,
 * so the fields are counted from the closing one: the first token after it is
 * field 3 of the record, which makes utime/stime fields 14/15 and rss field 24.
 */
inline std::optional<ProcessStat> parseProcessStat(const QByteArray &procPidStatContents)
{
    const qsizetype open = procPidStatContents.indexOf('(');
    const qsizetype close = procPidStatContents.lastIndexOf(')');
    if (open < 0 || close < open)
        return std::nullopt;

    bool pidOk = false;
    const int pid = procPidStatContents.left(open).trimmed().toInt(&pidOk);
    if (!pidOk)
        return std::nullopt;

    const QList<QByteArray> fields = procPidStatContents.mid(close + 1).simplified().split(' ');
    if (fields.size() < 22)
        return std::nullopt;

    bool utimeOk = false;
    bool stimeOk = false;
    bool rssOk = false;
    const quint64 utime = fields.at(11).toULongLong(&utimeOk);
    const quint64 stime = fields.at(12).toULongLong(&stimeOk);
    const quint64 startTicks = fields.at(19).toULongLong(&rssOk); // field 22
    const quint64 rssPages = fields.at(21).toULongLong(&rssOk);
    if (!utimeOk || !stimeOk || !rssOk)
        return std::nullopt;

    ProcessStat stat;
    stat.pid = pid;
    stat.name = QString::fromUtf8(procPidStatContents.mid(open + 1, close - open - 1));
    stat.cpuTicks = utime + stime;
    stat.startTicks = startTicks;
    stat.rssPages = rssPages;
    return stat;
}

/**
 * @brief CPU share of one process between two samples, as a percentage of the
 * whole machine.
 *
 * The denominator is the delta of the aggregate CPU counters, so a process
 * pinning one core of an eight-core machine reads 12.5%, and the column adds up
 * to the machine-wide usage the dock item shows.
 */
inline qreal processCpuPercent(quint64 previousTicks, quint64 currentTicks, quint64 totalTicksDelta)
{
    if (totalTicksDelta == 0 || currentTicks < previousTicks)
        return 0;
    return 100.0 * qreal(currentTicks - previousTicks) / qreal(totalTicksDelta);
}

/**
 * @brief Reads every process it can from /proc.
 *
 * Processes come and go while this runs, so one that vanishes between the
 * directory listing and the read is skipped instead of being reported as an
 * empty record.
 */
inline QList<ProcessStat> sampleProcesses(const QString &procRoot = QStringLiteral("/proc"))
{
    const QDir proc(procRoot);
    const auto entries = proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot);

    QList<ProcessStat> processes;
    processes.reserve(entries.size());
    for (const QString &entry : entries) {
        bool pidOk = false;
        entry.toInt(&pidOk);
        if (!pidOk)
            continue;

        QFile statFile(proc.absoluteFilePath(entry + QStringLiteral("/stat")));
        if (!statFile.open(QIODevice::ReadOnly))
            continue;

        if (const std::optional<ProcessStat> stat = parseProcessStat(statFile.readAll()))
            processes.append(*stat);
    }
    return processes;
}

struct RankedProcess
{
    ProcessStat stat;
    /// Share of the whole machine since the previous sample, in percent.
    qreal cpuPercent = 0;
};

/// What the process list is ordered by; the other figure breaks ties.
enum class ProcessSort
{
    Cpu,
    Memory,
};

/**
 * @brief The processes that matter most first: by cpu share since the previous
 * sample, or by resident memory, with the other figure breaking ties.
 *
 * A process whose ticks cannot be compared — it is new, or its pid was recycled
 * — counts as idle for this sample instead of contributing a bogus delta.
 */
inline QList<RankedProcess> rankProcesses(const QList<ProcessStat> &sampled,
                                          const QHash<int, quint64> &previousTicks,
                                          quint64 totalTicksDelta,
                                          int limit,
                                          ProcessSort sort = ProcessSort::Cpu)
{
    QList<RankedProcess> ranked;
    ranked.reserve(sampled.size());
    for (const ProcessStat &stat : sampled) {
        ranked.append({stat, processCpuPercent(previousTicks.value(stat.pid, stat.cpuTicks), stat.cpuTicks,
                                               totalTicksDelta)});
    }

    std::sort(ranked.begin(), ranked.end(), [sort](const RankedProcess &left, const RankedProcess &right) {
        if (sort == ProcessSort::Memory) {
            if (left.stat.rssPages != right.stat.rssPages)
                return left.stat.rssPages > right.stat.rssPages;
            return left.cpuPercent > right.cpuPercent;
        }
        if (!qFuzzyCompare(left.cpuPercent, right.cpuPercent))
            return left.cpuPercent > right.cpuPercent;
        return left.stat.rssPages > right.stat.rssPages;
    });

    if (limit > 0 && ranked.size() > limit)
        ranked = ranked.mid(0, limit);
    return ranked;
}

/**
 * @brief Whether the process behind a pid is still the one that was listed.
 *
 * A pid is recycled as soon as its process exits, so between filling a process
 * list and the user acting on it the same number may already belong to an
 * unrelated program — possibly one with the same name, which is why the start
 * time is compared too. Signalling is only safe while the current record still
 * is the process that was listed.
 */
inline bool sameProcess(int pid, const std::optional<ProcessStat> &current, const QString &listedName,
                        quint64 listedStartTicks)
{
    return current.has_value() && current->pid == pid && listedStartTicks > 0 && current->name == listedName
            && current->startTicks == listedStartTicks;
}

struct FanReading
{
    /// The chip's own label when it has one, otherwise "<chip> <index>".
    QString name;
    quint64 rpm = 0;
    /// The ceiling the chip reports for this fan, 0 when it does not say. Most
    /// chips do not, which is why the panel also takes a configured scale.
    quint64 maxRpm = 0;
};

/**
 * @brief Every fan the hwmon chips report, in the order the kernel lists them.
 *
 * A header with nothing plugged into it reads zero, exactly like a fan that has
 * stopped, so zeros are only reported when the whole machine reports zeros: that
 * way a stopped fan is not hidden, and an unused header is not noise.
 */
inline QList<FanReading> readFans(const QString &hwmonRoot = QStringLiteral("/sys/class/hwmon"))
{
    QList<FanReading> fans;
    const QDir root(hwmonRoot);
    const auto chips = root.entryList({QStringLiteral("hwmon*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &chip : chips) {
        const QDir chipDir(root.absoluteFilePath(chip));
        QFile nameFile(chipDir.absoluteFilePath(QStringLiteral("name")));
        const QString chipName = nameFile.open(QIODevice::ReadOnly)
                ? QString::fromLatin1(nameFile.readAll()).trimmed() : chip;

        const auto inputs = chipDir.entryList({QStringLiteral("fan*_input")}, QDir::Files);
        for (const QString &input : inputs) {
            bool rpmOk = false;
            const quint64 rpm = QString::fromLatin1(detail::readWholeFile(chipDir.absoluteFilePath(input)))
                                        .trimmed().toULongLong(&rpmOk);
            if (!rpmOk)
                continue;

            // fan12_input -> "12", for a name when the chip has no label.
            const QString index = input.mid(3, input.indexOf(QLatin1Char('_')) - 3);
            QFile labelFile(chipDir.absoluteFilePath(QStringLiteral("fan%1_label").arg(index)));
            const QString label = labelFile.open(QIODevice::ReadOnly)
                    ? QString::fromLatin1(labelFile.readAll()).trimmed() : QString();

            bool maxOk = false;
            const quint64 maxRpm = QString::fromLatin1(detail::readWholeFile(
                                                               chipDir.absoluteFilePath(
                                                                       QStringLiteral("fan%1_max").arg(index))))
                                           .trimmed().toULongLong(&maxOk);

            fans.append({label.isEmpty() ? QStringLiteral("%1 %2").arg(chipName, index) : label, rpm,
                         maxOk ? maxRpm : quint64(0)});
        }
    }

    const bool anySpins = std::any_of(fans.cbegin(), fans.cend(), [](const FanReading &fan) {
        return fan.rpm > 0;
    });
    if (anySpins) {
        fans.erase(std::remove_if(fans.begin(), fans.end(), [](const FanReading &fan) {
                        return fan.rpm == 0;
                    }),
                   fans.end());
    }
    return fans;
}

struct EnergyCounter
{
    quint64 microJoules = 0;
    /// energy_uj wraps around at this value; the kernel says so in
    /// max_energy_range_uj and a wrap must not read as a negative delta.
    quint64 maxMicroJoules = 0;
};

/// The powercap zone to read: the cpu package when there is one, else the first
/// zone that exists.
inline QString findEnergyCounterDir(const QString &powercapRoot = QStringLiteral("/sys/class/powercap"))
{
    const QDir root(powercapRoot);
    const auto zones = root.entryList({QStringLiteral("intel-rapl*")}, QDir::Dirs | QDir::NoDotAndDotDot);

    QString fallback;
    for (const QString &zone : zones) {
        const QString dir = root.absoluteFilePath(zone);
        if (!QFile::exists(dir + QStringLiteral("/energy_uj")))
            continue;

        QFile nameFile(dir + QStringLiteral("/name"));
        const QString name = nameFile.open(QIODevice::ReadOnly)
                ? QString::fromLatin1(nameFile.readAll()).trimmed() : QString();
        if (name.startsWith(QLatin1String("package")))
            return dir;
        if (fallback.isEmpty())
            fallback = dir;
    }
    return fallback;
}

/// Reads a powercap energy counter; nothing when it is not readable, which is
/// the usual case: the kernel ships energy_uj as root-only.
inline std::optional<EnergyCounter> readEnergyCounter(const QString &directory)
{
    QFile energy(directory + QStringLiteral("/energy_uj"));
    if (!energy.open(QIODevice::ReadOnly))
        return std::nullopt;

    bool energyOk = false;
    const quint64 microJoules = QString::fromLatin1(energy.readAll()).trimmed().toULongLong(&energyOk);
    if (!energyOk)
        return std::nullopt;

    QFile maximum(directory + QStringLiteral("/max_energy_range_uj"));
    bool maximumOk = false;
    const quint64 maxMicroJoules = maximum.open(QIODevice::ReadOnly)
            ? QString::fromLatin1(maximum.readAll()).trimmed().toULongLong(&maximumOk) : quint64(0);

    return EnergyCounter{microJoules, maximumOk ? maxMicroJoules : quint64(0)};
}

/**
 * @brief Average power between two energy counter samples, in watts.
 *
 * The counter counts up and wraps at max_energy_range_uj, so a smaller reading
 * means a wrap rather than negative energy spent.
 */
inline std::optional<qreal> energyWatts(const EnergyCounter &previous, const EnergyCounter &current, qint64 elapsedMs)
{
    if (elapsedMs <= 0)
        return std::nullopt;

    quint64 delta = 0;
    if (current.microJoules >= previous.microJoules) {
        delta = current.microJoules - previous.microJoules;
    } else if (current.maxMicroJoules > 0) {
        delta = current.maxMicroJoules - previous.microJoules + current.microJoules;
    } else {
        return std::nullopt;
    }

    return qreal(delta) / 1000000.0 * 1000.0 / qreal(elapsedMs);
}

/**
 * @brief Watts a battery reports, i.e. what the whole machine is drawing.
 *
 * This is the one power reading a normal user can always get: the ACPI battery
 * driver publishes it in microwatts, and only falls back to multiplying the
 * voltage by the current when it does not. Absent on machines without a
 * battery, which is exactly when the other sources take over.
 */
inline std::optional<qreal> readBatteryPowerWatts(const QString &powerSupplyRoot =
                                                          QStringLiteral("/sys/class/power_supply"))
{
    const QDir root(powerSupplyRoot);
    const auto supplies = root.entryList({QStringLiteral("BAT*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &supply : supplies) {
        const QString dir = root.absoluteFilePath(supply);

        bool microwattsOk = false;
        const quint64 microwatts =
                QString::fromLatin1(detail::readWholeFile(dir + QStringLiteral("/power_now")))
                        .trimmed().toULongLong(&microwattsOk);
        if (microwattsOk)
            return qreal(microwatts) / 1000000.0;

        // Older drivers only publish microvolts and microamps.
        bool voltsOk = false;
        bool ampsOk = false;
        const quint64 microvolts = QString::fromLatin1(detail::readWholeFile(dir + QStringLiteral("/voltage_now")))
                                           .trimmed().toULongLong(&voltsOk);
        const quint64 microamps = QString::fromLatin1(detail::readWholeFile(dir + QStringLiteral("/current_now")))
                                          .trimmed().toULongLong(&ampsOk);
        if (voltsOk && ampsOk)
            return qreal(microvolts) * qreal(microamps) / 1000000000000.0;
    }
    return std::nullopt;
}

struct PowerReading
{
    qreal watts = 0;
    /// What is being measured — a hwmon chip name such as "amdgpu". Callers that
    /// know better (a battery, the cpu package) label it themselves.
    QString source;
};

/// Watts a hwmon chip reports, preferring its averaged reading over the
/// instantaneous one. Nothing when no chip reports power at all.
inline std::optional<PowerReading> readHwmonPower(const QString &hwmonRoot = QStringLiteral("/sys/class/hwmon"))
{
    const QDir root(hwmonRoot);
    const auto chips = root.entryList({QStringLiteral("hwmon*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &chip : chips) {
        const QDir chipDir(root.absoluteFilePath(chip));
        const auto inputs = chipDir.entryList({QStringLiteral("power*_average"), QStringLiteral("power*_input")},
                                              QDir::Files);
        for (const QString &input : inputs) {
            bool microwattsOk = false;
            const quint64 microwatts = QString::fromLatin1(detail::readWholeFile(chipDir.absoluteFilePath(input)))
                                               .trimmed().toULongLong(&microwattsOk);
            if (!microwattsOk)
                continue;

            QFile nameFile(chipDir.absoluteFilePath(QStringLiteral("name")));
            const QString chipName = nameFile.open(QIODevice::ReadOnly)
                    ? QString::fromLatin1(nameFile.readAll()).trimmed() : chip;
            return PowerReading{qreal(microwatts) / 1000000.0, chipName};
        }
    }
    return std::nullopt;
}

struct SensorReadings
{
    /// Unix time the daemon took the reading; 0 when the file carries none.
    qint64 time = 0;
    bool hasPower = false;
    qreal powerWatts = 0;
    QString powerSource;
};

/**
 * @brief Parses what polaris-sensord publishes.
 *
 * A flat "key=value" file: unknown keys and comments are ignored, so a newer
 * daemon can publish more readings without older readers having to know about
 * them, and a reader that understands a key the daemon does not publish simply
 * finds nothing.
 */
inline SensorReadings parseSensorReadings(const QByteArray &contents)
{
    SensorReadings readings;
    const QList<QByteArray> lines = contents.split('\n');
    for (const QByteArray &rawLine : lines) {
        const QByteArray line = rawLine.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;

        const qsizetype equals = line.indexOf('=');
        if (equals <= 0)
            continue;
        const QByteArray key = line.left(equals).trimmed();
        const QByteArray value = line.mid(equals + 1).trimmed();

        bool ok = false;
        if (key == "time") {
            const qint64 parsed = value.toLongLong(&ok);
            if (ok)
                readings.time = parsed;
        } else if (key == "power-watts") {
            const qreal parsed = value.toDouble(&ok);
            if (ok) {
                readings.hasPower = true;
                readings.powerWatts = parsed;
            }
        } else if (key == "power-source") {
            readings.powerSource = QString::fromUtf8(value);
        }
    }
    return readings;
}

/**
 * @brief Whether two process samples can be subtracted from each other.
 *
 * The per-process counters are only sampled while something is showing them, so
 * the first sample after a pause has to be treated as a fresh baseline: dividing
 * a long gap of ticks by one interval would report nonsense.
 */
inline bool processSampleContinuous(bool primed, qint64 sinceLastSampleMs, qint64 intervalMs)
{
    return primed && sinceLastSampleMs > 0 && intervalMs > 0 && sinceLastSampleMs <= intervalMs * 2;
}

/**
 * @brief Whether a daemon reading is recent enough to be believed.
 *
 * A stopped daemon leaves its last file behind, and yesterday's watts are worse
 * than no watts: the reader falls back to whatever it can read itself.
 */
inline bool sensorReadingsFresh(const SensorReadings &readings, qint64 nowUnix, qint64 maxAgeSeconds = 10)
{
    return readings.time > 0 && nowUnix >= readings.time && nowUnix - readings.time <= maxAgeSeconds;
}

/**
 * @brief Locates a CPU temperature input.
 *
 * Prefers a real CPU sensor from hwmon (coretemp / k10temp / ...) over the
 * generic acpitz reading, then falls back to the thermal zones.
 */
inline QString findCpuTemperaturePath()
{
    const QStringList preferredNames{"coretemp", "k10temp", "zenpower", "cpu_thermal", "soc_thermal"};
    const QDir hwmon(QStringLiteral("/sys/class/hwmon"));
    QString acpiFallback;

    const auto hwmonDirs = hwmon.entryList({QStringLiteral("hwmon*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : hwmonDirs) {
        const QString dir = hwmon.absoluteFilePath(entry);
        QFile nameFile(dir + QStringLiteral("/name"));
        if (!nameFile.open(QIODevice::ReadOnly))
            continue;

        const QString name = QString::fromLatin1(nameFile.readAll()).trimmed();
        const QString input = dir + QStringLiteral("/temp1_input");
        if (!QFile::exists(input))
            continue;

        if (preferredNames.contains(name))
            return input;
        if (acpiFallback.isEmpty() && name == QLatin1String("acpitz"))
            acpiFallback = input;
    }

    const QDir thermal(QStringLiteral("/sys/class/thermal"));
    const auto zones = thermal.entryList({QStringLiteral("thermal_zone*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : zones) {
        const QString dir = thermal.absoluteFilePath(entry);
        QFile typeFile(dir + QStringLiteral("/type"));
        if (!typeFile.open(QIODevice::ReadOnly))
            continue;

        const QString type = QString::fromLatin1(typeFile.readAll()).trimmed();
        const QString temp = dir + QStringLiteral("/temp");
        if ((type == QLatin1String("x86_pkg_temp") || type == QLatin1String("cpu-thermal")
             || type == QLatin1String("cpu_thermal"))
            && QFile::exists(temp)) {
            return temp;
        }
    }

    return acpiFallback;
}

/// Reads a sysfs millidegree file, returns degrees Celsius or -1 on failure.
inline qreal readTemperature(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return -1;

    bool ok = false;
    const qreal milliDegrees = QString::fromLatin1(file.readAll()).trimmed().toDouble(&ok);
    return ok ? milliDegrees / 1000.0 : -1;
}

} // namespace polaris
