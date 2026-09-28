// SPDX-License-Identifier: GPL-3.0-or-later

#include "systemreader.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QTimer>

#include <csignal>
#include <cstdio>
#include <cstdio>

namespace {

/// How often the counters are read. The dock item samples every two seconds by
/// default, so anything faster than this is published to nobody.
constexpr int kSampleIntervalMs = 2000;

constexpr auto kOutputPath = "/run/polaris/sensors";

/**
 * The well-known readings this service publishes. Only named values ever cross
 * the privilege boundary — never a path, never a command — so the worst a local
 * user can ask for is a power figure they could read anyway on most machines.
 */
QString renderReadings(qint64 time, const std::optional<qreal> &watts)
{
    QString text;
    text += QStringLiteral("# polaris-sensord\n");
    text += QStringLiteral("format=1\n");
    text += QStringLiteral("time=%1\n").arg(time);
    if (watts)
        text += QStringLiteral("power-watts=%1\npower-source=rapl\n").arg(*watts, 0, 'f', 2);
    return text;
}

/// Written to a temporary file and renamed, so a reader never sees half a file.
bool publish(const QString &path, const QString &contents)
{
    const QFileInfo info(path);
    if (!QDir().mkpath(info.absolutePath())) {
        std::fprintf(stderr, "polaris-sensord: cannot create %s\n", qPrintable(info.absolutePath()));
        return false;
    }

    // The temporary name is unlinked first and then created exclusively: a
    // symlink planted there — which a root process must never follow — makes the
    // open fail instead of writing through it.
    const QString temporary = path + QStringLiteral(".new");
    QFile::remove(temporary);
    QFile file(temporary);
    if (!file.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
        std::fprintf(stderr, "polaris-sensord: cannot write %s\n", qPrintable(temporary));
        return false;
    }
    file.write(contents.toUtf8());
    file.close();

    // Readable by everyone: it carries no secrets, and requiring privileges to
    // read it would only move the problem to every client.
    QFile::setPermissions(temporary, QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup
                                               | QFile::ReadOther);

    // rename(2) replaces the target in one step: QFile::rename() refuses to
    // overwrite, which would leave readers with the first reading forever, and
    // unlinking first would leave a window with no file at all.
    if (::rename(QFile::encodeName(temporary).constData(), QFile::encodeName(path).constData()) != 0) {
        std::fprintf(stderr, "polaris-sensord: cannot replace %s\n", qPrintable(path));
        QFile::remove(temporary);
        return false;
    }
    return true;
}

} // namespace

/**
 * @brief Publishes the readings that need privileges to read.
 *
 * The kernel hands the powercap energy counter to root only. Rather than opening
 * that file to every user, this small service samples it and publishes the
 * result — plus whatever else needs a privileged read later — as a handful of
 * named values under /run/polaris/sensors.
 */
int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("polaris-sensord"));

    // Kept overridable so the same binary can be exercised without root, and so
    // the unit file can point it elsewhere if a system wants that.
    QString energyRoot = QStringLiteral("/sys/class/powercap");
    QString outputPath = QString::fromLatin1(kOutputPath);
    const QStringList arguments = app.arguments();
    for (int i = 1; i < arguments.size(); ++i) {
        if (arguments.at(i) == QLatin1String("--powercap-root") && i + 1 < arguments.size())
            energyRoot = arguments.at(++i);
        else if (arguments.at(i) == QLatin1String("--output") && i + 1 < arguments.size())
            outputPath = arguments.at(++i);
    }

    const QString energyDir = polaris::findEnergyCounterDir(energyRoot);
    std::optional<polaris::EnergyCounter> previous;
    QElapsedTimer clock;
    clock.start();

    QTimer timer;
    timer.setInterval(kSampleIntervalMs);
    QObject::connect(&timer, &QTimer::timeout, &app, [&] {
        const qint64 elapsedMs = clock.restart();
        const std::optional<polaris::EnergyCounter> current =
                energyDir.isEmpty() ? std::nullopt : polaris::readEnergyCounter(energyDir);

        std::optional<qreal> watts;
        if (previous && current)
            watts = polaris::energyWatts(*previous, *current, elapsedMs);
        previous = current;

        publish(outputPath, renderReadings(QDateTime::currentSecsSinceEpoch(), watts));
    });
    timer.start();

    // Publish immediately so a client does not have to wait a whole interval for
    // the first file, and so the file exists even when the counter is unreadable.
    publish(outputPath, renderReadings(QDateTime::currentSecsSinceEpoch(), std::nullopt));

    // Dying on SIGTERM without unwinding is fine here: the only state is a file
    // written atomically on every tick.
    std::signal(SIGTERM, [](int) { std::exit(0); });

    return app.exec();
}
