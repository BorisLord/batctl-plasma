#include "batctlbackend.h"

#include <functional>
#include <memory>
#include <utility>

#include <QObject>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace
{
QString processError(QProcess *process)
{
    QString stderrText = QString::fromUtf8(process->readAllStandardError()).trimmed();
    if (!stderrText.isEmpty()) {
        return stderrText;
    }
    return process->errorString();
}
}

BatctlBackend::BatctlBackend(QObject *parent)
    : QObject(parent)
{
    refresh();
}

bool BatctlBackend::installed() const
{
    return m_installed;
}
bool BatctlBackend::busy() const
{
    return m_busy;
}
QString BatctlBackend::error() const
{
    return m_error;
}
QString BatctlBackend::message() const
{
    return m_message;
}
QString BatctlBackend::vendor() const
{
    return m_vendor;
}
QString BatctlBackend::product() const
{
    return m_product;
}
QString BatctlBackend::backend() const
{
    return m_backend;
}
QVariantList BatctlBackend::batteries() const
{
    return m_batteries;
}
QStringList BatctlBackend::presets() const
{
    return m_presets;
}
bool BatctlBackend::bootPersistence() const
{
    return m_bootPersistence;
}
bool BatctlBackend::resumePersistence() const
{
    return m_resumePersistence;
}

QString BatctlBackend::compactText() const
{
    if (m_batteries.isEmpty()) {
        return {};
    }
    const QVariantMap battery = m_batteries.first().toMap();
    const int start = battery.value(QStringLiteral("startThreshold"), -1).toInt();
    const int stop = battery.value(QStringLiteral("stopThreshold"), -1).toInt();
    if (start < 0 || stop < 0) {
        return battery.value(QStringLiteral("capacity")).toString();
    }
    return QStringLiteral("%1–%2").arg(start).arg(stop);
}

void BatctlBackend::refresh()
{
    // Coalesce refresh requests that arrive while reads are in flight; the
    // trailing one is replayed once the current batch settles. Without this,
    // a manual Refresh click during a periodic 30s timer fire was lost.
    if (m_busy || m_pendingReads > 0) {
        m_refreshPending = true;
        return;
    }

    setError({});
    m_batctlPath = QStandardPaths::findExecutable(QStringLiteral("batctl"));
    m_installed = !m_batctlPath.isEmpty();
    Q_EMIT dataChanged();

    if (!m_installed) {
        setError(QStringLiteral("batctl is not installed or not on PATH."));
        return;
    }

    m_pendingReads = 3;
    setBusy(true);

    runReadCommand({QStringLiteral("status")}, [this](const QString &output) {
        const StatusSnapshot snapshot = parseStatus(output);
        m_backend = snapshot.backend;
        m_batteries = snapshot.batteries;
        m_bootPersistence = snapshot.bootPersistence;
        m_resumePersistence = snapshot.resumePersistence;
        Q_EMIT dataChanged();
    });

    runReadCommand({QStringLiteral("detect")}, [this](const QString &output) {
        const IdentitySnapshot identity = parseDetect(output);
        m_vendor = identity.vendor;
        m_product = identity.product;
        if (m_backend.isEmpty()) {
            m_backend = identity.backend;
        }
        Q_EMIT dataChanged();
    });

    runReadCommand({QStringLiteral("set"), QStringLiteral("--help")}, [this](const QString &output) {
        const QStringList discovered = parsePresets(output);
        if (discovered.isEmpty()) {
            setError(QStringLiteral("The installed batctl version did not expose any presets."));
        } else {
            m_presets = discovered;
            Q_EMIT dataChanged();
        }
    });
}

void BatctlBackend::applyPreset(const QString &preset)
{
    if (m_busy || !m_presets.contains(preset)) {
        return;
    }

    setError({});
    setMessage({});
    setBusy(true);
    runPrivilegedCommand({QStringLiteral("set"), QStringLiteral("--preset"), preset}, [this, preset]() {
        setMessage(QStringLiteral("Applied %1.").arg(preset));
        refreshPersistenceAfterApply();
    });
}

void BatctlBackend::setPersistence(bool enabled)
{
    if (m_busy) {
        return;
    }

    setError({});
    setMessage({});
    setBusy(true);
    const QString action = enabled ? QStringLiteral("enable") : QStringLiteral("disable");
    runPrivilegedCommand({QStringLiteral("persist"), action}, [this, enabled]() {
        setMessage(enabled ? QStringLiteral("Persistence enabled.") : QStringLiteral("Persistence disabled."));
        setBusy(false);
        refresh();
    });
}

BatctlBackend::StatusSnapshot BatctlBackend::parseStatus(const QString &output)
{
    StatusSnapshot snapshot;
    QVariantMap currentBattery;
    const QRegularExpression batteryHeader(QStringLiteral("^(BAT\\d+) \\((.*)\\)$"));
    const QRegularExpression thresholds(QStringLiteral("start=(\\d+)% stop=(\\d+)%"));
    const QRegularExpression persistence(QStringLiteral("boot=(true|false)\\s+resume=(true|false)"));

    const auto flushBattery = [&snapshot, &currentBattery]() {
        if (!currentBattery.isEmpty()) {
            snapshot.batteries.append(currentBattery);
            currentBattery.clear();
        }
    };

    for (const QString &rawLine : output.split('\n')) {
        const QString line = rawLine.trimmed();
        if (line.startsWith(QStringLiteral("Backend:"))) {
            snapshot.backend = line.section(':', 1).trimmed();
            continue;
        }

        const QRegularExpressionMatch batteryMatch = batteryHeader.match(line);
        if (batteryMatch.hasMatch()) {
            flushBattery();
            currentBattery.insert(QStringLiteral("name"), batteryMatch.captured(1));
            currentBattery.insert(QStringLiteral("model"), batteryMatch.captured(2));
            continue;
        }

        if (!currentBattery.isEmpty()) {
            const auto separator = line.indexOf(':');
            if (separator >= 0) {
                const QString key = line.left(separator).trimmed();
                const QString value = line.mid(separator + 1).trimmed();
                if (key == QStringLiteral("Status")) {
                    currentBattery.insert(QStringLiteral("status"), value);
                } else if (key == QStringLiteral("Capacity")) {
                    currentBattery.insert(QStringLiteral("capacity"), value);
                } else if (key == QStringLiteral("Health")) {
                    currentBattery.insert(QStringLiteral("health"), value);
                } else if (key == QStringLiteral("Cycles")) {
                    currentBattery.insert(QStringLiteral("cycles"), value);
                } else if (key == QStringLiteral("Energy")) {
                    currentBattery.insert(QStringLiteral("energy"), value);
                } else if (key == QStringLiteral("Thresholds")) {
                    const QRegularExpressionMatch match = thresholds.match(value);
                    if (match.hasMatch()) {
                        currentBattery.insert(QStringLiteral("startThreshold"), match.captured(1).toInt());
                        currentBattery.insert(QStringLiteral("stopThreshold"), match.captured(2).toInt());
                    }
                } else if (key == QStringLiteral("Behaviour")) {
                    currentBattery.insert(QStringLiteral("behaviour"), value.section(' ', 0, 0));
                }
            }
        }

        const QRegularExpressionMatch persistenceMatch = persistence.match(line);
        if (persistenceMatch.hasMatch()) {
            flushBattery();
            snapshot.bootPersistence = persistenceMatch.captured(1) == QStringLiteral("true");
            snapshot.resumePersistence = persistenceMatch.captured(2) == QStringLiteral("true");
        }
    }

    flushBattery();
    return snapshot;
}

QStringList BatctlBackend::parsePresets(const QString &output)
{
    const QRegularExpression expression(QStringLiteral("--preset\\s+string\\s+.*\\(([^)]+)\\)"));
    const QRegularExpressionMatch match = expression.match(output);
    if (!match.hasMatch()) {
        return {};
    }

    QStringList result;
    for (const QString &preset : match.captured(1).split(',')) {
        const QString trimmed = preset.trimmed();
        if (!trimmed.isEmpty()) {
            result.append(trimmed);
        }
    }
    return result;
}

BatctlBackend::IdentitySnapshot BatctlBackend::parseDetect(const QString &output)
{
    IdentitySnapshot identity;
    for (const QString &rawLine : output.split('\n')) {
        const auto separator = rawLine.indexOf(':');
        if (separator < 0) {
            continue;
        }
        const QString key = rawLine.left(separator).trimmed();
        const QString value = rawLine.mid(separator + 1).trimmed();
        if (key == QStringLiteral("Vendor")) {
            identity.vendor = value;
        } else if (key == QStringLiteral("Product")) {
            identity.product = value;
        } else if (key == QStringLiteral("Backend")) {
            identity.backend = value;
        }
    }
    return identity;
}

void BatctlBackend::runReadCommand(const QStringList &arguments, const std::function<void(const QString &)> &onSuccess)
{
    auto *process = new QProcess(this);
    // finished and errorOccurred(FailedToStart) may both fire depending on the
    // platform; complete exactly once per process to avoid double-counting.
    auto done = std::make_shared<bool>(false);
    connect(process, &QProcess::finished, this, [this, process, onSuccess, done](int exitCode, QProcess::ExitStatus exitStatus) {
        if (std::exchange(*done, true)) {
            return;
        }
        if (exitStatus == QProcess::NormalExit && exitCode == 0) {
            onSuccess(QString::fromUtf8(process->readAllStandardOutput()));
        } else {
            setError(processError(process));
        }
        process->deleteLater();
        finishRead();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, done](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || std::exchange(*done, true)) {
            return;
        }
        setError(processError(process));
        process->deleteLater();
        finishRead();
    });
    process->start(m_batctlPath, arguments);
}

void BatctlBackend::runPrivilegedCommand(const QStringList &arguments, const std::function<void()> &onSuccess, const std::function<void()> &onFailure)
{
    auto *process = new QProcess(this);
    QStringList privilegedArguments{m_batctlPath};
    privilegedArguments.append(arguments);
    auto done = std::make_shared<bool>(false);
    connect(process, &QProcess::finished, this, [this, process, onSuccess, onFailure, done](int exitCode, QProcess::ExitStatus exitStatus) {
        if (std::exchange(*done, true)) {
            return;
        }
        if (exitStatus == QProcess::NormalExit && exitCode == 0) {
            onSuccess();
        } else {
            setError(processError(process));
            setBusy(false);
            if (onFailure) {
                onFailure();
            }
        }
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, onFailure, done](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || std::exchange(*done, true)) {
            return;
        }
        setError(processError(process));
        setBusy(false);
        if (onFailure) {
            onFailure();
        }
        process->deleteLater();
    });
    process->start(QStringLiteral("pkexec"), privilegedArguments);
}

void BatctlBackend::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    Q_EMIT busyChanged();
}

void BatctlBackend::setError(const QString &error)
{
    if (m_error == error) {
        return;
    }
    m_error = error;
    Q_EMIT errorChanged();
}

void BatctlBackend::setMessage(const QString &message)
{
    if (m_message == message) {
        return;
    }
    m_message = message;
    Q_EMIT messageChanged();
}

void BatctlBackend::finishRead()
{
    --m_pendingReads;
    if (m_pendingReads == 0) {
        setBusy(false);
        if (std::exchange(m_refreshPending, false)) {
            refresh();
        }
    }
}

void BatctlBackend::refreshPersistenceAfterApply()
{
    if (m_bootPersistence || m_resumePersistence) {
        runPrivilegedCommand(
            {QStringLiteral("persist"), QStringLiteral("enable")},
            [this]() {
                setBusy(false);
                refresh();
            },
            [this]() {
                refresh();
            });
        return;
    }
    setBusy(false);
    refresh();
}
