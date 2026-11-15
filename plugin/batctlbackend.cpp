#include "batctlbackend.h"

#include <functional>
#include <memory>
#include <utility>

#include <QFileInfo>
#include <QObject>
#include <QProcess>
#include <QRegularExpression>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

BatctlBackend::BatctlBackend(QObject *parent)
    : QObject(parent)
{
    refresh();
}

bool BatctlBackend::installed() const
{
    return m_installed;
}
bool BatctlBackend::ready() const
{
    return m_installed && m_statusValid && !m_presets.isEmpty();
}
QString BatctlBackend::warning() const
{
    return m_warning;
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
    if (stop < 0) {
        return battery.value(QStringLiteral("capacity")).toString();
    }
    return start < 0 ? QStringLiteral("%1%").arg(stop) : QStringLiteral("%1–%2%").arg(start).arg(stop);
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

    setError(m_writeError);
    m_batctlPath = QStringLiteral("/usr/bin/batctl");
    const QFileInfo executable(m_batctlPath);
    m_installed =
        executable.isFile() && executable.isExecutable() && executable.ownerId() == 0 && !(executable.permissions() & (QFile::WriteGroup | QFile::WriteOther));
    m_statusValid = false;
    m_presets.clear();
    m_batteries.clear();
    m_warning = m_writeWarning;
    m_backend.clear();
    m_vendor.clear();
    m_product.clear();
    m_bootPersistence = false;
    m_resumePersistence = false;
    Q_EMIT dataChanged();

    if (!m_installed) {
        setError(QStringLiteral("Install the battery manager batctl as a root-owned executable at /usr/bin/batctl."));
        return;
    }

    m_pendingReads = 3;
    setBusy(true);

    runReadCommand({QStringLiteral("status")}, [this](const QString &output) {
        const StatusSnapshot snapshot = parseStatus(output);
        m_statusValid = snapshot.valid;
        if (!snapshot.valid) {
            setError(QStringLiteral("batctl returned an invalid battery status."));
        }
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
    if (m_busy || !ready() || !m_presets.contains(preset)) {
        return;
    }

    m_writeError.clear();
    m_writeWarning.clear();
    m_warning.clear();
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
    if (m_busy || !ready()) {
        return;
    }

    m_writeError.clear();
    m_writeWarning.clear();
    m_warning.clear();
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
    const QRegularExpression batteryHeader(QStringLiteral("^([^\\s:]+) \\((.*)\\)$"));
    const QRegularExpression thresholds(QStringLiteral("(?:(?:start=(\\d+)%)\\s+)?stop=(\\d+)%"));
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
                        if (!match.captured(1).isEmpty()) {
                            currentBattery.insert(QStringLiteral("startThreshold"), match.captured(1).toInt());
                        }
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
            snapshot.valid = true;
            snapshot.bootPersistence = persistenceMatch.captured(1) == QStringLiteral("true");
            snapshot.resumePersistence = persistenceMatch.captured(2) == QStringLiteral("true");
        }
    }

    flushBattery();
    snapshot.valid = snapshot.valid && !snapshot.backend.isEmpty() && !snapshot.batteries.isEmpty();
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

void BatctlBackend::runCommand(const QString &program,
                               const QStringList &arguments,
                               const std::function<void(const QString &)> &onSuccess,
                               const std::function<void()> &onFailure)
{
    auto *process = new QProcess(this);
    auto done = std::make_shared<bool>(false);
    const auto complete = [this, process, onSuccess, onFailure, done](bool success) {
        if (std::exchange(*done, true)) {
            return;
        }
        const QString output = QString::fromUtf8(process->readAllStandardOutput());
        const QString diagnostic = QString::fromUtf8(process->readAllStandardError()).trimmed();
        if (success) {
            QStringList warnings;
            if (!diagnostic.isEmpty()) {
                warnings.append(diagnostic);
            }
            bool inWarning = false;
            for (const QString &line : output.split('\n')) {
                inWarning = inWarning || line.contains(QStringLiteral("Warning:"));
                if (inWarning && !line.trimmed().isEmpty()) {
                    warnings.append(line.trimmed());
                }
            }
            if (!warnings.isEmpty()) {
                if (!m_warning.isEmpty()) {
                    m_warning += '\n';
                }
                m_warning += warnings.join('\n');
                Q_EMIT dataChanged();
            }
            onSuccess(output);
        } else {
            setError(diagnostic.isEmpty()
                         ? QStringLiteral("%1 failed: %2 (exit code %3)").arg(process->program(), process->errorString()).arg(process->exitCode())
                         : diagnostic);
            onFailure();
        }
        process->deleteLater();
    };
    connect(process, &QProcess::finished, this, [complete](int code, QProcess::ExitStatus status) {
        complete(status == QProcess::NormalExit && code == 0);
    });
    connect(process, &QProcess::errorOccurred, this, [complete](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            complete(false);
        }
    });
    process->start(program, arguments);
}

void BatctlBackend::runReadCommand(const QStringList &arguments, const std::function<void(const QString &)> &onSuccess)
{
    runCommand(
        m_batctlPath,
        arguments,
        [this, onSuccess](const QString &output) {
            onSuccess(output);
            finishRead();
        },
        [this]() {
            finishRead();
        });
}

void BatctlBackend::runPrivilegedCommand(const QStringList &arguments, const std::function<void()> &onSuccess, const std::function<void()> &onFailure)
{
    QStringList privilegedArguments{m_batctlPath};
    privilegedArguments.append(arguments);
    runCommand(
        QStringLiteral("/usr/bin/pkexec"),
        privilegedArguments,
        [this, onSuccess](const QString &) {
            m_writeWarning = m_warning;
            onSuccess();
        },
        [this, onFailure]() {
            m_writeError = m_error;
            setMessage({});
            setBusy(false);
            if (onFailure) {
                onFailure();
            }
        });
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
    const QString combined = m_writeError.isEmpty() || error.startsWith(m_writeError) ? error : m_writeError + QStringLiteral("\n") + error;
    if (m_error == combined) {
        return;
    }
    m_error = combined;
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
                m_writeError = QStringLiteral("Thresholds applied, but persistence could not be saved: %1").arg(m_error);
                refresh();
            });
        return;
    }
    setBusy(false);
    refresh();
}
