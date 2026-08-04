#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QtQmlIntegration/qqmlintegration.h>
#include <functional>

class QProcess;

class BatctlBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool installed READ installed NOTIFY dataChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)
    Q_PROPERTY(QString vendor READ vendor NOTIFY dataChanged)
    Q_PROPERTY(QString product READ product NOTIFY dataChanged)
    Q_PROPERTY(QString backend READ backend NOTIFY dataChanged)
    Q_PROPERTY(QVariantList batteries READ batteries NOTIFY dataChanged)
    Q_PROPERTY(QStringList presets READ presets NOTIFY dataChanged)
    Q_PROPERTY(bool bootPersistence READ bootPersistence NOTIFY dataChanged)
    Q_PROPERTY(bool resumePersistence READ resumePersistence NOTIFY dataChanged)
    Q_PROPERTY(QString compactText READ compactText NOTIFY dataChanged)

public:
    struct StatusSnapshot {
        QString backend;
        QVariantList batteries;
        bool bootPersistence = false;
        bool resumePersistence = false;
    };

    struct IdentitySnapshot {
        QString vendor;
        QString product;
        QString backend; // populated only if status did not already report one
    };

    explicit BatctlBackend(QObject *parent = nullptr);

    bool installed() const;
    bool busy() const;
    QString error() const;
    QString message() const;
    QString vendor() const;
    QString product() const;
    QString backend() const;
    QVariantList batteries() const;
    QStringList presets() const;
    bool bootPersistence() const;
    bool resumePersistence() const;
    QString compactText() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void applyPreset(const QString &preset);
    Q_INVOKABLE void setPersistence(bool enabled);

    static StatusSnapshot parseStatus(const QString &output);
    static QStringList parsePresets(const QString &output);
    static IdentitySnapshot parseDetect(const QString &output);

Q_SIGNALS:
    void dataChanged();
    void busyChanged();
    void errorChanged();
    void messageChanged();

private:
    void runReadCommand(const QStringList &arguments, const std::function<void(const QString &)> &onSuccess);
    void runPrivilegedCommand(const QStringList &arguments, const std::function<void()> &onSuccess, const std::function<void()> &onFailure = {});
    void setBusy(bool busy);
    void setError(const QString &error);
    void setMessage(const QString &message);
    void finishRead();
    void refreshPersistenceAfterApply();

    QString m_batctlPath;
    bool m_installed = false;
    bool m_busy = false;
    int m_pendingReads = 0;
    bool m_refreshPending = false;
    QString m_error;
    QString m_message;
    QString m_vendor;
    QString m_product;
    QString m_backend;
    QVariantList m_batteries;
    QStringList m_presets;
    bool m_bootPersistence = false;
    bool m_resumePersistence = false;
};
