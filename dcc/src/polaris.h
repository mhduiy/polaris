
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef POLARIS_H
#define POLARIS_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QVariant>

namespace Dtk::Core {
class DConfig;
}

/**
 * Control-center backend ("dccData" in QML) for the Polaris settings page.
 *
 * It reads and writes the same org.deepin.ds.dock.polaris DConfig the dock
 * applet reads — which metrics the dock item shows, how often it refreshes and
 * how many processes its popup lists. Both sides talk to the same schema, so a
 * change here reaches the dock without any IPC of ours.
 */
class Polaris : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool showCpu READ showCpu NOTIFY showCpuChanged)
    Q_PROPERTY(bool showTemperature READ showTemperature NOTIFY showTemperatureChanged)
    Q_PROPERTY(bool showMemory READ showMemory NOTIFY showMemoryChanged)
    Q_PROPERTY(bool showSwap READ showSwap NOTIFY showSwapChanged)
    Q_PROPERTY(bool showNetwork READ showNetwork NOTIFY showNetworkChanged)
    Q_PROPERTY(bool showPower READ showPower NOTIFY showPowerChanged)
    Q_PROPERTY(bool showFan READ showFan NOTIFY showFanChanged)
    Q_PROPERTY(QString dockChartMode READ dockChartMode NOTIFY dockChartModeChanged)
    Q_PROPERTY(int refreshIntervalMs READ refreshIntervalMs NOTIFY refreshIntervalMsChanged)
    Q_PROPERTY(int fanScaleRpm READ fanScaleRpm NOTIFY fanScaleRpmChanged)
    Q_PROPERTY(int processCount READ processCount NOTIFY processCountChanged)
    Q_PROPERTY(QString processSort READ processSort NOTIFY processSortChanged)

public:
    explicit Polaris(QObject *parent = nullptr);

    bool showCpu() const { return m_showCpu; }
    bool showTemperature() const { return m_showTemperature; }
    bool showMemory() const { return m_showMemory; }
    bool showSwap() const { return m_showSwap; }
    bool showNetwork() const { return m_showNetwork; }
    bool showPower() const { return m_showPower; }
    bool showFan() const { return m_showFan; }
    QString dockChartMode() const { return m_dockChartMode; }
    int refreshIntervalMs() const { return m_refreshIntervalMs; }
    int fanScaleRpm() const { return m_fanScaleRpm; }
    int processCount() const { return m_processCount; }
    QString processSort() const { return m_processSort; }

    Q_INVOKABLE void setShowCpu(bool show);
    Q_INVOKABLE void setShowTemperature(bool show);
    Q_INVOKABLE void setShowMemory(bool show);
    Q_INVOKABLE void setShowSwap(bool show);
    Q_INVOKABLE void setShowNetwork(bool show);
    Q_INVOKABLE void setShowPower(bool show);
    Q_INVOKABLE void setShowFan(bool show);
    /** Clamped to 500..10000 ms. */
    Q_INVOKABLE void setRefreshIntervalMs(int intervalMs);
    /** Clamped to 3..30. */
    Q_INVOKABLE void setProcessCount(int count);
    /** Clamped to 500..10000 RPM. */
    Q_INVOKABLE void setFanScaleRpm(int rpm);
    /** "cpu" or "memory"; anything else is ignored. */
    Q_INVOKABLE void setProcessSort(const QString &sort);
    /** "off", "both" or "line"; anything else is ignored. */
    Q_INVOKABLE void setDockChartMode(const QString &mode);

Q_SIGNALS:
    void showCpuChanged(bool show);
    void showTemperatureChanged(bool show);
    void showMemoryChanged(bool show);
    void showSwapChanged(bool show);
    void showNetworkChanged(bool show);
    void showPowerChanged(bool show);
    void showFanChanged(bool show);
    void dockChartModeChanged(const QString &mode);
    void refreshIntervalMsChanged(int intervalMs);
    void processCountChanged(int count);
    void fanScaleRpmChanged(int rpm);
    void processSortChanged(const QString &sort);

private:
    /** Re-read every key and re-emit its NOTIFY signal. */
    void reload();
    /** True when the installed schema knows this key at all. */
    bool configKeyAvailable(const QString &key) const;
    /**
     * Read a key, or the fallback when the installed schema does not have it.
     *
     * The availability check is not belt-and-braces: dtk6's DConfigFile::value()
     * dereferences a null pointer for a key the meta file does not have, so on
     * the file backend a plain read of a missing key takes the whole process
     * down. Never call value() without asking first.
     */
    QVariant configValue(const QString &key, const QVariant &fallback) const;
    /** Write a key; refuses (with a one-off warning) what the schema lacks. */
    void writeConfig(const QString &key, const QVariant &value);

    Dtk::Core::DConfig *m_config = nullptr;
    bool m_showCpu = true;
    bool m_showTemperature = true;
    bool m_showMemory = true;
    bool m_showSwap = true;
    bool m_showNetwork = true;
    bool m_showPower = false;
    bool m_showFan = false;
    QString m_dockChartMode = QStringLiteral("off");
    int m_refreshIntervalMs = 2000;
    int m_processCount = 8;
    int m_fanScaleRpm = 3000;
    QString m_processSort = QStringLiteral("cpu");
    /** Keys already reported as missing — one warning per key, not per click. */
    QSet<QString> m_warnedKeys;
};

#endif // POLARIS_H
