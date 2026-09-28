// SPDX-License-Identifier: GPL-3.0-or-later

#include "systemreader.h"

#include <QCoreApplication>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>
#include <QThread>
#include <cstdio>

// Not <cassert>: NDEBUG (Release builds) must not silently disable the checks.
#define CHECK(cond)                                                                                                    \
    do {                                                                                                               \
        if (!(cond)) {                                                                                                 \
            std::printf("FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                                              \
            return 1;                                                                                                  \
        }                                                                                                              \
    } while (false)

namespace {

QByteArray readFile(const char *path)
{
    QFile file(QString::fromLatin1(path));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

/// Sums the first eight CPU fields of one "cpu..." line, or 0 when the line is
/// not a CPU line. Independent of parseCpuTimes on purpose.
quint64 sumCpuLine(const QByteArray &line)
{
    const QList<QByteArray> fields = line.simplified().split(' ');
    if (fields.isEmpty() || !fields.first().startsWith("cpu"))
        return 0;

    quint64 total = 0;
    for (int i = 1; i <= 8 && i < fields.size(); ++i) {
        bool ok = false;
        const quint64 value = fields.at(i).toULongLong(&ok);
        if (ok)
            total += value;
    }
    return total;
}

} // namespace

int main()
{
    // user nice system idle iowait irq softirq steal guest guest_nice
    const auto times = polaris::parseCpuTimes("cpu  100 20 30 400 50 5 6 7 0 0\n");
    CHECK(times.total == 100 + 20 + 30 + 400 + 50 + 5 + 6 + 7);
    CHECK(times.idle == 400 + 50); // idle + iowait: a CPU waiting on I/O is not busy

    // Regression: /proc/stat is not one line. The per-CPU lines and the
    // intr/softirq counters must not be added on top of the aggregate line.
    // Summing the whole file used to pin the reported CPU usage near 100%.
    const auto whole = polaris::parseCpuTimes("cpu  100 20 30 400 50 5 6 7 0 0\n"
                                                 "cpu0 50 10 15 200 25 2 3 3 0 0\n"
                                                 "cpu1 50 10 15 200 25 3 3 4 0 0\n"
                                                 "intr 99999 5000 4000 3000\n"
                                                 "softirq 88888 1000 2000\n"
                                                 "ctxt 777777\n"
                                                 "btime 1700000000\n"
                                                 "processes 123456\n");
    CHECK(whole.total == 100 + 20 + 30 + 400 + 50 + 5 + 6 + 7);
    CHECK(whole.idle == 400 + 50);

    // guest and guest_nice are already accounted in user and nice.
    const auto guest = polaris::parseCpuTimes("cpu  100 20 30 400 50 5 6 7 40 5\n");
    CHECK(guest.total == 100 + 20 + 30 + 400 + 50 + 5 + 6 + 7);

    // Anything that is not a complete aggregate cpu line must be ignored.
    CHECK(polaris::parseCpuTimes("intr 123 0 0\n").total == 0);
    CHECK(polaris::parseCpuTimes("").total == 0);
    CHECK(polaris::parseCpuTimes("cpu0 1 2 3 4 5 6 7 8\n").total == 0);
    CHECK(polaris::parseCpuTimes("cpu  100 20 30\n").total == 0);
    CHECK(polaris::parseCpuTimes("cpu  100 20 30 400 50 5 6 7 0 0").idle == 400 + 50); // no trailing newline

    // Cross-check against the real file. The aggregate line holds only a small
    // fraction of the numbers in /proc/stat: the per-CPU lines and the
    // intr/softirq counters make up the rest. Summing the whole file used to
    // pin the reported CPU usage near 100%.
    const QByteArray real = readFile("/proc/stat");
    CHECK(!real.isEmpty());

    quint64 everyNumber = 0;
    const QList<QByteArray> allTokens = QByteArray(real).replace('\n', ' ').simplified().split(' ');
    for (const QByteArray &token : allTokens) {
        bool ok = false;
        const quint64 value = token.toULongLong(&ok);
        if (ok)
            everyNumber += value;
    }

    const quint64 aggregate = polaris::parseCpuTimes(real).total;
    CHECK(aggregate > 0);
    CHECK(aggregate < everyNumber);

    // And it is exactly the sum of the aggregate line's own fields. (The
    // per-CPU lines are accumulated in a separate pass by the kernel, so their
    // sum can trail the aggregate by whatever the other CPUs did in between.)
    CHECK(aggregate == sumCpuLine(real.split('\n').first()));

    const auto mem = polaris::parseMemInfo("MemTotal:       16140776 kB\n"
                                              "MemFree:         1000000 kB\n"
                                              "MemAvailable:    7925136 kB\n"
                                              "SwapTotal:      25165816 kB\n"
                                              "SwapFree:       20473916 kB\n");
    CHECK(mem.memTotal == 16140776);
    CHECK(mem.memAvailable == 7925136);
    CHECK(mem.swapTotal == 25165816);
    CHECK(mem.swapFree == 20473916);

    // Swap disabled: totals stay zero and callers must not divide by them.
    const auto noSwap = polaris::parseMemInfo("MemTotal: 100 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n");
    CHECK(noSwap.memTotal == 100);
    CHECK(noSwap.swapTotal == 0);

    // Missing keys stay zero instead of carrying garbage.
    const auto partial = polaris::parseMemInfo("MemTotal: 42 kB\n");
    CHECK(partial.memTotal == 42);
    CHECK(partial.memAvailable == 0);
    CHECK(partial.swapTotal == 0);

    // /proc/net/dev: two header lines, then "iface: rx... tx..." with the byte
    // counters first in each group.
    const QByteArray netDev = "Inter-|   Receive                                                |  Transmit\n"
                              " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n"
                              "    lo: 9999999    1234    0    0    0     0          0         0  9999999    1234    0    0    0     0       0          0\n"
                              "  eth0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                              " wlan0:   50000      80    0    0    0     0          0         0     4000      40    0    0    0     0       0          0\n";

    // Stands in for isHardwareInterface(), which asks sysfs and therefore cannot
    // be exercised with synthetic names.
    const auto hardwareOnly = [](const QString &name) {
        return name != QLatin1String("lo") && (name.startsWith("eth") || name.startsWith("wl"))
                && !name.contains(QLatin1Char('.'));
    };

    const auto net = polaris::parseNetDev(netDev, hardwareOnly);
    CHECK(net.rxBytes == 10000 + 50000); // loopback is not traffic
    CHECK(net.txBytes == 2000 + 4000);
    CHECK(net.interfaces == 2);

    // Counting the virtual interfaces on top of their parent would report
    // roughly twice the bytes that actually crossed the wire. tailscale0 is the
    // one that bit on the development machine: it rides on the physical NIC.
    const QByteArray virtualDev = "  eth0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "docker0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  " veth1a:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "    br0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "  bond0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "   tun0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "   tap0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  " virbr0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "tailscale0: 10000     50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "   wg0:   10000      50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n"
                                  "eth0.100: 10000     50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n";
    const auto onlyPhysical = polaris::parseNetDev(virtualDev, hardwareOnly);
    CHECK(onlyPhysical.rxBytes == 10000);
    CHECK(onlyPhysical.txBytes == 2000);
    CHECK(onlyPhysical.interfaces == 1);

    // A truncated or non-numeric line must not contribute half a counter.
    const auto truncated = polaris::parseNetDev("  eth0:   10000      50    0\n"
                                                   "  eth1:   abc     50    0    0    0     0          0         0     2000      30    0    0    0     0       0          0\n",
                                                   hardwareOnly);
    CHECK(truncated.rxBytes == 0);
    CHECK(truncated.txBytes == 0);
    CHECK(truncated.interfaces == 0);
    CHECK(polaris::parseNetDev("", hardwareOnly).interfaces == 0);
    CHECK(polaris::parseNetDev("Inter-|   Receive  |  Transmit\n", hardwareOnly).interfaces == 0);

    // The real rules: loopback is never counted, a name no interface has is not
    // hardware-backed.
    CHECK(!polaris::isHardwareInterface("lo"));
    CHECK(!polaris::isNotLoopback("lo"));
    CHECK(polaris::isNotLoopback("eth0"));
    CHECK(!polaris::isHardwareInterface("no-such-interface-42"));

    // Cross-check the default filter against the real machine. The interfaces it
    // sums must be exactly the driver-bound ones, so the same bytes read back
    // from sysfs — a moment later, hence never fewer — are the ceiling. This is
    // the check that caught tailscale0 being counted on top of enp5s0.
    const QByteArray realNet = readFile("/proc/net/dev");
    CHECK(!realNet.isEmpty());
    const auto realCounters = polaris::parseNetDev(realNet);

    quint64 hardwareBytes = 0;
    const QDir netClass(QStringLiteral("/sys/class/net"));
    const auto realNames = netClass.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &name : realNames) {
        if (!polaris::isHardwareInterface(name))
            continue;
        QFile rxFile(QStringLiteral("/sys/class/net/%1/statistics/rx_bytes").arg(name));
        if (!rxFile.open(QIODevice::ReadOnly))
            continue;
        hardwareBytes += QString::fromLatin1(rxFile.readAll()).trimmed().toULongLong();
    }

    if (realCounters.interfaces > 0) {
        CHECK(hardwareBytes > 0);
        CHECK(realCounters.rxBytes <= hardwareBytes);
    } else {
        // No driver-bound interface on this machine: the reader falls back to
        // everything but loopback rather than reporting no traffic at all.
        CHECK(hardwareBytes == 0);
    }

    // Per-process counters are only trustworthy against a sample taken close
    // enough in time: dividing a long idle gap by one interval would be nonsense.
    CHECK(polaris::processSampleContinuous(true, 2000, 2000));
    CHECK(polaris::processSampleContinuous(true, 4000, 2000));
    CHECK(!polaris::processSampleContinuous(true, 4001, 2000));
    CHECK(!polaris::processSampleContinuous(false, 2000, 2000)); // nothing to subtract from
    CHECK(!polaris::processSampleContinuous(true, 0, 2000));
    CHECK(!polaris::processSampleContinuous(true, 2000, 0));

    // Rates are bytes per second over the interval that actually elapsed, and a
    // shrinking counter means an interface went away — not a negative rate.
    const polaris::NetCounters before{1000, 2000};
    const auto rate = polaris::netRate(before, {4000, 6000}, 1000);
    CHECK(rate.has_value());
    CHECK(rate->rxBytes == 3000);
    CHECK(rate->txBytes == 4000);
    CHECK(polaris::netRate(before, {4000, 6000}, 2000)->rxBytes == 1500); // half the interval, half the rate
    CHECK(polaris::netRate(before, {1000, 2000}, 1000)->rxBytes == 0);    // idle is a rate of zero, not a failure
    CHECK(!polaris::netRate(before, {999, 6000}, 1000).has_value());
    CHECK(!polaris::netRate(before, {4000, 1999}, 1000).has_value());
    CHECK(!polaris::netRate(before, {4000, 6000}, 0).has_value());

    // /proc/<pid>/stat: the fields are counted from the closing parenthesis of
    // the command name, which itself may contain spaces and parentheses.
    // pid (comm) state ppid ... utime(14) stime(15) ... rss(24) ...
    QByteArray statLine = "1234 (bash) S 1 1234 1234 0 -1 4194304 ";
    for (int i = 0; i < 4; ++i)
        statLine += "0 ";        // minflt cminflt majflt cmajflt (fields 10..13)
    statLine += "70 30 ";        // utime 70, stime 30 (fields 14, 15)
    for (int i = 0; i < 8; ++i)
        statLine += "0 ";        // fields 16..23
    statLine += "512 ";          // rss 512 pages (field 24), after starttime (field 22)
    for (int i = 0; i < 4; ++i)
        statLine += "0 ";

    const auto process = polaris::parseProcessStat(statLine);
    CHECK(process.has_value());
    CHECK(process->pid == 1234);
    CHECK(process->name == QLatin1String("bash"));
    CHECK(process->cpuTicks == 100);
    CHECK(process->rssPages == 512);
    CHECK(process->startTicks == 0); // the fixture leaves field 22 at zero

    // A name with spaces and brackets must not shift the fields.
    const auto spaced = polaris::parseProcessStat(QByteArray(statLine).replace("(bash)", "(my (odd) prog)"));
    CHECK(spaced.has_value());
    CHECK(spaced->name == QLatin1String("my (odd) prog"));
    CHECK(spaced->cpuTicks == 100);
    CHECK(spaced->rssPages == 512);
    CHECK(spaced->startTicks == 0); // the extra parentheses must not shift the fields

    // Truncated, non-numeric and empty records carry no information.
    CHECK(!polaris::parseProcessStat("1234 (bash) S 1 1234 0 0 0 0 0 0 0 0\n").has_value());
    CHECK(!polaris::parseProcessStat("1234 (bash) S 1 1234\n").has_value());
    CHECK(!polaris::parseProcessStat("").has_value());
    CHECK(!polaris::parseProcessStat("(bash) S 1\n").has_value());
    CHECK(!polaris::parseProcessStat("1234 bash S 1 1234\n").has_value());

    // Cross-check against this very process: the kernel reports it under the pid
    // the runtime knows and the name /proc/<pid>/comm holds.
    QFile ownStat(QStringLiteral("/proc/self/stat"));
    CHECK(ownStat.open(QIODevice::ReadOnly));
    const auto own = polaris::parseProcessStat(ownStat.readAll());
    CHECK(own.has_value());
    CHECK(own->pid == QCoreApplication::applicationPid());
    CHECK(own->rssPages > 0);
    QFile ownComm(QStringLiteral("/proc/self/comm"));
    CHECK(ownComm.open(QIODevice::ReadOnly));
    CHECK(own->name == QString::fromLatin1(ownComm.readAll()).trimmed());

    // The cpu column is a share of the whole machine, so the shares of all
    // processes add up to the machine-wide usage.
    CHECK(polaris::processCpuPercent(100, 150, 200) == 25.0);
    CHECK(polaris::processCpuPercent(100, 100, 200) == 0.0);
    CHECK(polaris::processCpuPercent(100, 150, 0) == 0.0);
    CHECK(polaris::processCpuPercent(150, 100, 200) == 0.0); // the pid was recycled

    // Sampling the real /proc: this process must be in there, and every entry
    // must be a parsed record rather than a placeholder.
    const QList<polaris::ProcessStat> processes = polaris::sampleProcesses();
    CHECK(processes.size() > 1);
    bool sawOurselves = false;
    for (const polaris::ProcessStat &process : processes) {
        CHECK(process.pid > 0);
        CHECK(!process.name.isEmpty());
        CHECK(process.startTicks > 0); // a running process has a start time
        if (process.pid == QCoreApplication::applicationPid())
            sawOurselves = true;
    }
    CHECK(sawOurselves);
    CHECK(polaris::sampleProcesses(QStringLiteral("/no/such/proc")).isEmpty());

    // A row is only still ours to signal while the pid carries the same command
    // it did when the list was filled. Ending an unrelated process because a pid
    // was recycled is the one mistake this button must never make.
    const polaris::ProcessStat listed{1234, QStringLiteral("bash"), 100, 512, 4200};
    CHECK(polaris::sameProcess(1234, listed, QLatin1String("bash"), 4200));
    CHECK(!polaris::sameProcess(1234, listed, QLatin1String("dde-shell"), 4200)); // pid recycled
    CHECK(!polaris::sameProcess(4321, listed, QLatin1String("bash"), 4200));      // the record moved on
    CHECK(!polaris::sameProcess(1234, std::nullopt, QLatin1String("bash"), 4200)); // it exited
    CHECK(!polaris::sameProcess(1234, listed, QString(), 4200));                  // never listed
    // The same command name but a different start time: the pid was handed to
    // another instance of the same program, which must not be signalled either.
    CHECK(!polaris::sameProcess(1234, listed, QLatin1String("bash"), 4100));
    CHECK(!polaris::sameProcess(1234, listed, QLatin1String("bash"), 0)); // nothing was recorded

    // Ranking: busiest first, memory breaking ties, and a limit that truncates
    // from the busy end rather than the idle one.
    const polaris::ProcessStat idle{10, QStringLiteral("idle"), 100, 900};
    const polaris::ProcessStat busy{11, QStringLiteral("busy"), 300, 10};
    const polaris::ProcessStat newcomer{12, QStringLiteral("newcomer"), 5, 5000};
    const polaris::ProcessStat sameTicksSmall{13, QStringLiteral("small"), 150, 100};
    const polaris::ProcessStat sameTicksBig{14, QStringLiteral("big"), 150, 200};
    const QList<polaris::ProcessStat> sampled{idle, busy, newcomer, sameTicksSmall, sameTicksBig};

    QHash<int, quint64> previous;
    previous.insert(10, 100);   // idle: 0 of 1000 ticks
    previous.insert(11, 100);   // busy: 200 of 1000 ticks
    previous.insert(13, 100);   // small: tied with big on cpu
    previous.insert(14, 100);

    const QList<polaris::RankedProcess> ranked = polaris::rankProcesses(sampled, previous, 1000, 0);
    CHECK(ranked.size() == 5);
    CHECK(ranked.at(0).stat.pid == 11);
    CHECK(ranked.at(0).cpuPercent == 20.0);
    CHECK(ranked.at(1).stat.pid == 14); // same cpu as 13, more memory
    CHECK(ranked.at(2).stat.pid == 13);
    CHECK(ranked.at(3).stat.pid == 12); // new since the last sample: no delta to trust
    CHECK(ranked.at(3).cpuPercent == 0.0);
    CHECK(ranked.at(4).stat.pid == 10);

    const QList<polaris::RankedProcess> few = polaris::rankProcesses(sampled, previous, 1000, 2);
    CHECK(few.size() == 2);
    CHECK(few.at(0).stat.pid == 11);
    CHECK(few.at(1).stat.pid == 14);

    // The other order: resident memory first, cpu breaking ties, and the same
    // limit cutting from the heavy end.
    const QList<polaris::RankedProcess> byMemory =
            polaris::rankProcesses(sampled, previous, 1000, 0, polaris::ProcessSort::Memory);
    CHECK(byMemory.size() == 5);
    CHECK(byMemory.at(0).stat.pid == 12); // newcomer: 5000 pages
    CHECK(byMemory.at(1).stat.pid == 10); // idle: 900 pages
    CHECK(byMemory.at(2).stat.pid == 14); // 200 pages, ahead of 13 on nothing but size
    CHECK(byMemory.at(3).stat.pid == 13);
    CHECK(byMemory.at(4).stat.pid == 11); // the busiest by cpu, the smallest by memory
    CHECK(byMemory.at(0).cpuPercent == 0.0); // the share is still reported in both orders

    const QList<polaris::RankedProcess> fewByMemory =
            polaris::rankProcesses(sampled, previous, 1000, 2, polaris::ProcessSort::Memory);
    CHECK(fewByMemory.size() == 2);
    CHECK(fewByMemory.at(0).stat.pid == 12);
    CHECK(fewByMemory.at(1).stat.pid == 10);

    // A sample pair taken from the live machine still measures a process that ran
    // through the whole window: this is the end-to-end shape of what the popup
    // lists. The share is taken against the machine-wide tick delta over the same
    // window, exactly as the applet does it.
    QProcess burner;
    const QByteArray statBefore = readFile("/proc/stat");
    burner.start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), QStringLiteral("while :; do :; done")});
    CHECK(burner.waitForStarted());
    // processId() is the running process: read it before the burner is gone.
    const qint64 burnerPid = qint64(burner.processId());
    const QList<polaris::ProcessStat> first = polaris::sampleProcesses();
    QThread::msleep(400);
    const QList<polaris::ProcessStat> second = polaris::sampleProcesses();
    const quint64 totalDelta = polaris::parseCpuTimes(readFile("/proc/stat")).total
            - polaris::parseCpuTimes(statBefore).total;
    burner.kill();
    burner.waitForFinished();

    const auto ticksOf = [](const QList<polaris::ProcessStat> &sample, qint64 pid) {
        for (const polaris::ProcessStat &stat : sample) {
            if (stat.pid == pid)
                return stat.cpuTicks;
        }
        return quint64(0);
    };
    const quint64 burnerBefore = ticksOf(first, burnerPid);
    const quint64 burnerAfter = ticksOf(second, burnerPid);
    CHECK(burnerAfter > burnerBefore); // it really was running through the window
    CHECK(totalDelta > 0);

    QHash<int, quint64> livePrevious;
    livePrevious.insert(int(burnerPid), burnerBefore);
    // No limit: whether the burner is in the top few depends on what else the
    // machine is doing, which a test must not depend on.
    const QList<polaris::RankedProcess> live = polaris::rankProcesses(second, livePrevious, totalDelta, 0);
    CHECK(!live.isEmpty());

    bool sawBurner = false;
    for (int i = 0; i < live.size(); ++i) {
        if (i > 0)
            CHECK(live.at(i - 1).cpuPercent >= live.at(i).cpuPercent); // busiest first
        if (live.at(i).stat.pid == burnerPid) {
            sawBurner = true;
            CHECK(live.at(i).cpuPercent > 0.0);
        }
    }
    CHECK(sawBurner);

    // The detail panel's cpu bar: every elapsed tick lands in exactly one
    // bucket, so the four percentages add up to 100.
    const auto cpuBefore = polaris::parseCpuTimes("cpu  100 0 50 800 50 0 0 0 0 0\n");
    const auto cpuAfter = polaris::parseCpuTimes("cpu  150 0 70 950 80 0 0 0 0 0\n");
    const auto split = polaris::cpuBreakdown(cpuBefore, cpuAfter);
    CHECK(qFuzzyCompare(split.user, 20.0));   // 50 of 250 ticks
    CHECK(qFuzzyCompare(split.system, 8.0));  // 20 of 250
    CHECK(qFuzzyCompare(split.iowait, 12.0)); // 30 of 250
    CHECK(qFuzzyCompare(split.idle, 60.0));   // 150 of 250
    CHECK(qFuzzyCompare(split.user + split.system + split.iowait + split.idle, 100.0));
    CHECK(qFuzzyCompare(polaris::cpuBreakdown(cpuAfter, cpuAfter).user, 0.0));
    CHECK(qFuzzyCompare(polaris::cpuBreakdown(cpuAfter, cpuBefore).idle, 0.0)); // the counters went backwards

    // Per-core counters: one entry per "cpuN" line, the aggregate line skipping
    // this path, and the other /proc/stat counters ignored.
    const auto cores = polaris::parseCpuPerCore("cpu  300 0 50 800 50 0 0 0 0 0\n"
                                                "cpu0 100 0 25 400 25 0 0 0 0 0\n"
                                                "cpu1 200 0 25 400 25 0 0 0 0 0\n"
                                                "intr 12345 0 0\n");
    CHECK(cores.size() == 2);
    CHECK(cores.at(0).total == 550);
    CHECK(cores.at(0).idle == 425);
    CHECK(cores.at(1).total == 650);
    CHECK(polaris::parseCpuPerCore("cpu  300 0 50 800 50 0 0 0 0 0\n").isEmpty());

    // The memory bar is the free(1) split: used + cache + free is exactly the
    // total, which is what makes it honest.
    const polaris::MemInfo memSample{1000, 200, 400, 100, 300, 0, 0};
    const auto memory = polaris::memorySplit(memSample);
    CHECK(memory.used == 400);
    CHECK(memory.cache == 400);
    CHECK(memory.free == 200);
    CHECK(memory.used + memory.cache + memory.free == memory.total);
    CHECK(polaris::memorySplit(polaris::MemInfo{}).total == 0);
    // Nonsense values must not produce a used figure larger than the machine,
    // and the parts must still add up to the total.
    const polaris::MemInfo odd{1000, 0, 0, 900, 900, 0, 0};
    CHECK(polaris::memorySplit(odd).used == 0);
    CHECK(polaris::memorySplit(odd).free == 0);
    CHECK(polaris::memorySplit(odd).cache == 1000);
    CHECK(polaris::memorySplit(odd).used + polaris::memorySplit(odd).cache + polaris::memorySplit(odd).free
          == polaris::memorySplit(odd).total);

    CHECK(qFuzzyCompare(polaris::parseUptimeSeconds("12345.67 8901.23\n"), 12345.67));
    CHECK(polaris::parseUptimeSeconds("not a number\n") == 0.0);

    const auto average = polaris::parseLoadAverage("0.52 0.58 0.59 1/1234 5678\n");
    CHECK(average.size() == 3);
    CHECK(qFuzzyCompare(average.at(0), 0.52));
    CHECK(qFuzzyCompare(average.at(2), 0.59));
    CHECK(polaris::parseLoadAverage("").isEmpty());
    CHECK(polaris::parseLoadAverage("0.1 0.2 nonsense\n").isEmpty());

    // The charts' ring buffer: fixed length, newest sample last, oldest dropped.
    polaris::History history(3);
    CHECK(history.capacity() == 3);
    CHECK(history.maximum() == 0.0);
    history.push(1.0);
    history.push(2.0);
    CHECK(history.values() == QVariantList({1.0, 2.0}));
    history.push(3.0);
    history.push(4.0);
    CHECK(history.values() == QVariantList({2.0, 3.0, 4.0}));
    CHECK(qFuzzyCompare(history.maximum(), 4.0));
    CHECK(polaris::History(0).capacity() == 1); // a chart needs room for one sample

    // hwmon and powercap are directory trees, so a fake one can be laid out the
    // way the kernel lays out the real thing — no sensor needed to test the
    // reading of one.
    QTemporaryDir hwmon;
    CHECK(hwmon.isValid());
    const auto writeFile = [](const QString &path, const QByteArray &contents) {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile file(path);
        return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
    };

    CHECK(writeFile(hwmon.filePath("hwmon0/name"), "coretemp\n"));
    CHECK(writeFile(hwmon.filePath("hwmon1/name"), "nct6798\n"));
    CHECK(writeFile(hwmon.filePath("hwmon1/fan1_input"), "929\n"));
    CHECK(writeFile(hwmon.filePath("hwmon1/fan1_label"), "CPU Fan\n"));
    CHECK(writeFile(hwmon.filePath("hwmon1/fan1_max"), "2400\n")); // the chip's own ceiling, when it has one
    CHECK(writeFile(hwmon.filePath("hwmon1/fan2_input"), "0\n")); // header with nothing plugged in
    CHECK(writeFile(hwmon.filePath("hwmon2/name"), "thinkpad\n"));
    CHECK(writeFile(hwmon.filePath("hwmon2/fan1_input"), "3200\n"));

    const QList<polaris::FanReading> fans = polaris::readFans(hwmon.path());
    CHECK(fans.size() == 2); // the idle header is dropped while something spins
    CHECK(fans.at(0).name == QLatin1String("CPU Fan")); // the chip's own label wins
    CHECK(fans.at(0).rpm == 929);
    CHECK(fans.at(0).maxRpm == 2400);
    CHECK(fans.at(1).name == QLatin1String("thinkpad 1")); // no label: chip and index
    CHECK(fans.at(1).rpm == 3200);
    CHECK(fans.at(1).maxRpm == 0); // no ceiling reported: the panel's scale applies

    // When nothing spins, zero is the reading, not noise: a stopped fan has to
    // stay visible.
    QTemporaryDir stalled;
    CHECK(stalled.isValid());
    CHECK(writeFile(stalled.filePath("hwmon0/name"), "nct6798\n"));
    CHECK(writeFile(stalled.filePath("hwmon0/fan1_input"), "0\n"));
    CHECK(writeFile(stalled.filePath("hwmon0/fan2_input"), "0\n"));
    const QList<polaris::FanReading> stopped = polaris::readFans(stalled.path());
    CHECK(stopped.size() == 2);
    CHECK(stopped.at(0).rpm == 0);
    CHECK(polaris::readFans(QStringLiteral("/no/such/hwmon")).isEmpty());

    // Watts from a chip: microwatts, and the averaged reading preferred over the
    // instantaneous one when it has both.
    CHECK(writeFile(hwmon.filePath("hwmon1/power1_input"), "45000000\n"));
    CHECK(writeFile(hwmon.filePath("hwmon1/power1_average"), "42000000\n"));
    const auto watts = polaris::readHwmonPower(hwmon.path());
    CHECK(watts.has_value());
    CHECK(qFuzzyCompare(watts->watts, 42.0));
    CHECK(watts->source == QLatin1String("nct6798")); // the label says which device
    CHECK(!polaris::readHwmonPower(stalled.path()).has_value());

    // The battery: the one power reading a normal user always gets, in micro
    // watts or as microvolts times microamps.
    QTemporaryDir supplies;
    CHECK(supplies.isValid());
    CHECK(writeFile(supplies.filePath("BAT0/power_now"), "12300000\n"));
    const auto battery = polaris::readBatteryPowerWatts(supplies.path());
    CHECK(battery.has_value());
    CHECK(qFuzzyCompare(*battery, 12.3));

    QTemporaryDir oldSupplies;
    CHECK(oldSupplies.isValid());
    CHECK(writeFile(oldSupplies.filePath("BAT1/voltage_now"), "12000000\n"));
    CHECK(writeFile(oldSupplies.filePath("BAT1/current_now"), "1000000\n"));
    const auto multiplied = polaris::readBatteryPowerWatts(oldSupplies.path());
    CHECK(multiplied.has_value());
    CHECK(qFuzzyCompare(*multiplied, 12.0));
    CHECK(!polaris::readBatteryPowerWatts(stalled.path()).has_value()); // no battery on a desktop

    // The powercap energy counter: package zone preferred, and a wrap reported
    // as a wrap instead of negative energy.
    QTemporaryDir powercap;
    CHECK(powercap.isValid());
    CHECK(writeFile(powercap.filePath("intel-rapl:0/name"), "package-0\n"));
    CHECK(writeFile(powercap.filePath("intel-rapl:0/energy_uj"), "1000000\n"));
    CHECK(writeFile(powercap.filePath("intel-rapl:0/max_energy_range_uj"), "262143328850\n"));
    CHECK(writeFile(powercap.filePath("intel-rapl:0:0/name"), "core\n"));
    CHECK(writeFile(powercap.filePath("intel-rapl:0:0/energy_uj"), "500\n"));

    const QString zone = polaris::findEnergyCounterDir(powercap.path());
    CHECK(zone.endsWith(QLatin1String("intel-rapl:0")));
    const auto counter = polaris::readEnergyCounter(zone);
    CHECK(counter.has_value());
    CHECK(counter->microJoules == 1000000);
    CHECK(counter->maxMicroJoules == 262143328850ULL);
    CHECK(!polaris::readEnergyCounter(powercap.filePath("intel-rapl:0:0/nothing")).has_value());
    CHECK(polaris::findEnergyCounterDir(QStringLiteral("/no/such/powercap")).isEmpty());

    // 500000 µJ in 2 s is 0.25 W.
    const auto wattsAverage = polaris::energyWatts({1000000, 262143328850ULL}, {1500000, 262143328850ULL}, 2000);
    CHECK(wattsAverage.has_value());
    CHECK(qAbs(*wattsAverage - 0.25) < 1e-9);

    // A counter that wrapped: 50 µJ to reach the top plus 50 µJ after it, over
    // the max range, instead of a negative delta.
    const auto wrapped = polaris::energyWatts({262143328800ULL, 262143328850ULL}, {50, 262143328850ULL}, 2000);
    CHECK(wrapped.has_value());
    CHECK(qAbs(*wrapped - 100.0 / 1000000.0 / 2.0) < 1e-12);

    // Without a wrap range a smaller reading cannot be turned into a rate, and a
    // zero interval has no rate at all.
    CHECK(!polaris::energyWatts({1000, 0}, {500, 0}, 2000).has_value());
    CHECK(!polaris::energyWatts({1000, 262143328850ULL}, {1500, 262143328850ULL}, 0).has_value());

    // What polaris-sensord publishes: named values only, unknown keys ignored so
    // a newer daemon can add readings without breaking an older reader.
    const auto published = polaris::parseSensorReadings("# polaris-sensord\n"
                                                        "format=1\n"
                                                        "time=1700000000\n"
                                                        "power-watts=42.66\n"
                                                        "power-source=rapl\n"
                                                        "fan-max-rpm=1200\n"); // a reading from the future
    CHECK(published.time == 1700000000);
    CHECK(published.hasPower);
    CHECK(qFuzzyCompare(published.powerWatts, 42.66));
    CHECK(published.powerSource == QLatin1String("rapl"));

    // The daemon up and running, and the daemon that stopped an hour ago.
    CHECK(polaris::sensorReadingsFresh(published, 1700000005));
    CHECK(polaris::sensorReadingsFresh(published, 1700000010));
    CHECK(!polaris::sensorReadingsFresh(published, 1700000011));
    CHECK(!polaris::sensorReadingsFresh(published, 1699999999)); // clock stepped backwards
    CHECK(!polaris::sensorReadingsFresh(polaris::SensorReadings{}, 1700000000)); // no timestamp to trust

    // A daemon that started but could not read the counter publishes a file with
    // no power in it, which is not the same as a power of zero.
    const auto unreadable = polaris::parseSensorReadings("time=1700000000\n");
    CHECK(!unreadable.hasPower);
    CHECK(polaris::sensorReadingsFresh(unreadable, 1700000000));
    CHECK(polaris::parseSensorReadings("power-watts=nonsense\ntime=abc\n").time == 0);
    CHECK(!polaris::parseSensorReadings("power-watts=nonsense\n").hasPower);
    CHECK(!polaris::parseSensorReadings("").hasPower);

    std::puts("systemreader checks passed");
    return 0;
}
