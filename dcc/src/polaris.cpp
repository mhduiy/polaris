
// SPDX-License-Identifier: GPL-3.0-or-later
#include "polaris.h"

#include "dccfactory.h"

#include <DConfig>

#include <QVariant>

namespace {
const QString kAppId = QStringLiteral("org.deepin.ds.dock.polaris");
const QString kShowCpuKey = QStringLiteral("showCpu");
const QString kShowTemperatureKey = QStringLiteral("showTemperature");
const QString kShowMemoryKey = QStringLiteral("showMemory");
const QString kShowSwapKey = QStringLiteral("showSwap");
const QString kShowNetworkKey = QStringLiteral("showNetwork");
const QString kShowPowerKey = QStringLiteral("showPower");
const QString kShowFanKey = QStringLiteral("showFan");
const QString kRefreshIntervalKey = QStringLiteral("refreshIntervalMs");
const QString kProcessCountKey = QStringLiteral("processCount");
const QString kFanScaleKey = QStringLiteral("fanScaleRpm");
const QString kProcessSortKey = QStringLiteral("processSort");
const QString kDockChartModeKey = QStringLiteral("dockChartMode");

// Ranges the schema documents; the dock applet cannot work outside them, so a
// value that somehow arrives from QML is clamped rather than persisted as is.
constexpr int kIntervalMin = 500;
constexpr int kIntervalMax = 10000;
constexpr int kProcessCountMin = 3;
constexpr int kProcessCountMax = 30;
constexpr int kFanScaleMin = 500;
constexpr int kFanScaleMax = 10000;
const QStringList kChartModes{QStringLiteral("off"), QStringLiteral("both"), QStringLiteral("line")};
} // namespace

Polaris::Polaris(QObject *parent)
    : QObject(parent)
    , m_config(Dtk::Core::DConfig::create(kAppId, kAppId, QString(), this))
{
    if (m_config) {
        // A schema update, another page or a hand-edited config can move a value
        // under us; re-read and re-emit so the page never shows a stale setting.
        connect(m_config, &Dtk::Core::DConfig::valueChanged, this, [this] {
            reload();
        });
    }
    reload();
}

void Polaris::reload()
{
    if (!m_config || !m_config->isValid())
        return;
    // Reads go through configValue() so that a key the installed schema does not
    // have is never handed to DConfig at all — see its comment for why that
    // matters. A control center running ahead of the installed package must show
    // "the setting is not there", not die.
    m_showCpu = configValue(kShowCpuKey, true).toBool();
    m_showTemperature = configValue(kShowTemperatureKey, true).toBool();
    m_showMemory = configValue(kShowMemoryKey, true).toBool();
    m_showSwap = configValue(kShowSwapKey, true).toBool();
    m_showNetwork = configValue(kShowNetworkKey, true).toBool();
    m_showPower = configValue(kShowPowerKey, false).toBool();
    m_showFan = configValue(kShowFanKey, false).toBool();
    m_refreshIntervalMs = configValue(kRefreshIntervalKey, 2000).toInt();
    m_processCount = configValue(kProcessCountKey, 8).toInt();
    m_fanScaleRpm = configValue(kFanScaleKey, 3000).toInt();
    m_processSort = configValue(kProcessSortKey, QStringLiteral("cpu")).toString();
    m_dockChartMode = configValue(kDockChartModeKey, QStringLiteral("off")).toString();

    Q_EMIT showCpuChanged(m_showCpu);
    Q_EMIT showTemperatureChanged(m_showTemperature);
    Q_EMIT showMemoryChanged(m_showMemory);
    Q_EMIT showSwapChanged(m_showSwap);
    Q_EMIT showNetworkChanged(m_showNetwork);
    Q_EMIT showPowerChanged(m_showPower);
    Q_EMIT showFanChanged(m_showFan);
    Q_EMIT refreshIntervalMsChanged(m_refreshIntervalMs);
    Q_EMIT processCountChanged(m_processCount);
    Q_EMIT fanScaleRpmChanged(m_fanScaleRpm);
    Q_EMIT processSortChanged(m_processSort);
    Q_EMIT dockChartModeChanged(m_dockChartMode);
}

bool Polaris::configKeyAvailable(const QString &key) const
{
    return m_config && m_config->isValid() && m_config->keyList().contains(key);
}

QVariant Polaris::configValue(const QString &key, const QVariant &fallback) const
{
    // Never hand a missing key to DConfig: on the file backend dtk6 dereferences
    // a null pointer instead of returning the fallback, so this is the difference
    // between "the setting is not there" and a dead control center.
    if (!configKeyAvailable(key))
        return fallback;
    return m_config->value(key, fallback);
}

void Polaris::writeConfig(const QString &key, const QVariant &value)
{
    if (!configKeyAvailable(key)) {
        // dtk6's setValue() returns void, and the daemon refuses a key the
        // installed schema does not have without saying so. One warning per key —
        // a warning per checkbox click would be noise.
        if (!m_warnedKeys.contains(key)) {
            m_warnedKeys.insert(key);
            qWarning().noquote() << "polaris: config key not in the installed schema:" << key;
        }
        return;
    }
    m_config->setValue(key, value);
    reload();
}

void Polaris::setShowCpu(bool show)
{
    writeConfig(kShowCpuKey, show);
}

void Polaris::setShowTemperature(bool show)
{
    writeConfig(kShowTemperatureKey, show);
}

void Polaris::setShowMemory(bool show)
{
    writeConfig(kShowMemoryKey, show);
}

void Polaris::setShowSwap(bool show)
{
    writeConfig(kShowSwapKey, show);
}

void Polaris::setShowNetwork(bool show)
{
    writeConfig(kShowNetworkKey, show);
}

void Polaris::setRefreshIntervalMs(int intervalMs)
{
    writeConfig(kRefreshIntervalKey, qBound(kIntervalMin, intervalMs, kIntervalMax));
}

void Polaris::setProcessCount(int count)
{
    writeConfig(kProcessCountKey, qBound(kProcessCountMin, count, kProcessCountMax));
}

void Polaris::setShowPower(bool show)
{
    writeConfig(kShowPowerKey, show);
}

void Polaris::setShowFan(bool show)
{
    writeConfig(kShowFanKey, show);
}

void Polaris::setFanScaleRpm(int rpm)
{
    writeConfig(kFanScaleKey, qBound(kFanScaleMin, rpm, kFanScaleMax));
}

void Polaris::setProcessSort(const QString &sort)
{
    if (sort != QLatin1String("cpu") && sort != QLatin1String("memory"))
        return;
    writeConfig(kProcessSortKey, sort);
}

void Polaris::setDockChartMode(const QString &mode)
{
    if (!kChartModes.contains(mode))
        return;
    writeConfig(kDockChartModeKey, mode);
}

DCC_FACTORY_CLASS(Polaris)
#include "polaris.moc"
