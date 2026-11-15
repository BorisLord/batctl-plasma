#include "batctlbackend.h"

#include <QtTest>

class BatctlBackendTest final : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesStatus();
    void parsesPresets();
    void parsesDetect();
    void parsesOptionalFields();
    void runsProcesses();
    void preservesWriteFailure();
};

void BatctlBackendTest::parsesStatus()
{
    const QString output = QStringLiteral(R"(Backend: ThinkPad

BAT0 (SMP 5B11B79217)
  Status:     Full
  Capacity:   100%
  Health:     81.7%
  Cycles:     294
  Energy:     73.6 / 73.6 Wh (design: 90.1 Wh)
  Thresholds: start=20% stop=80%
  Behaviour:  auto (available: auto, inhibit-charge, force-discharge)

Persistence:  boot=true  resume=true
)");

    const BatctlBackend::StatusSnapshot snapshot = BatctlBackend::parseStatus(output);
    QCOMPARE(snapshot.backend, QStringLiteral("ThinkPad"));
    QCOMPARE(snapshot.batteries.size(), 1);
    const QVariantMap battery = snapshot.batteries.first().toMap();
    QCOMPARE(battery.value(QStringLiteral("name")).toString(), QStringLiteral("BAT0"));
    QCOMPARE(battery.value(QStringLiteral("startThreshold")).toInt(), 20);
    QCOMPARE(battery.value(QStringLiteral("stopThreshold")).toInt(), 80);
    QCOMPARE(battery.value(QStringLiteral("health")).toString(), QStringLiteral("81.7%"));
    QVERIFY(snapshot.bootPersistence);
    QVERIFY(snapshot.resumePersistence);
}

void BatctlBackendTest::parsesPresets()
{
    const QString output = QStringLiteral(R"(Flags:
  -h, --help            help for set
      --preset string   Apply a named preset (max-lifespan, balanced, full-charge, plugged-in)
      --start int       Start charge threshold (%)
)");

    QCOMPARE(BatctlBackend::parsePresets(output),
             QStringList({
                 QStringLiteral("max-lifespan"),
                 QStringLiteral("balanced"),
                 QStringLiteral("full-charge"),
                 QStringLiteral("plugged-in"),
             }));
}

void BatctlBackendTest::parsesDetect()
{
    const QString output = QStringLiteral(R"(Device: /sys/class/power_supply/BAT0
Vendor: LENOVO
Product: ThinkPad X1 Carbon Gen 11
Backend: ThinkPad
Supported features: threshold, behaviour
)");

    const BatctlBackend::IdentitySnapshot identity = BatctlBackend::parseDetect(output);
    QCOMPARE(identity.vendor, QStringLiteral("LENOVO"));
    QCOMPARE(identity.product, QStringLiteral("ThinkPad X1 Carbon Gen 11"));
    QCOMPARE(identity.backend, QStringLiteral("ThinkPad"));
}

void BatctlBackendTest::parsesOptionalFields()
{
    const auto snapshot =
        BatctlBackend::parseStatus(QStringLiteral("Backend: Generic\nCMB0 (ACME Battery)\n  Capacity: 50%\n  Thresholds: stop=80%\n"
                                                  "BAT1 (ACME Spare)\n  Capacity: 75%\nPersistence: boot=false resume=true\n"));
    QVERIFY(snapshot.valid);
    QCOMPARE(snapshot.batteries.size(), 2);
    const auto battery = snapshot.batteries.first().toMap();
    QCOMPARE(battery.value(QStringLiteral("name")).toString(), QStringLiteral("CMB0"));
    QCOMPARE(battery.value(QStringLiteral("stopThreshold")).toInt(), 80);
    QVERIFY(!battery.contains(QStringLiteral("startThreshold")));
    QVERIFY(!battery.contains(QStringLiteral("cycles")));
    QVERIFY(!battery.contains(QStringLiteral("behaviour")));
    QVERIFY(!BatctlBackend::parseStatus(QStringLiteral("unrelated output")).valid);
    QVERIFY(BatctlBackend::parsePresets(QStringLiteral("network utility help")).isEmpty());
}

void BatctlBackendTest::runsProcesses()
{
    BatctlBackend backend;
    QTRY_VERIFY(!backend.busy());
    int success = 0;
    int failure = 0;
    QString output;
    backend.runCommand(
        QStringLiteral("/bin/sh"),
        {QStringLiteral("-c"), QStringLiteral("printf result; printf diagnostic >&2")},
        [&](const QString &text) {
            output = text;
            ++success;
        },
        [&]() {
            ++failure;
        });
    QTRY_COMPARE(success, 1);
    QCOMPARE(output, QStringLiteral("result"));
    QVERIFY(backend.warning().contains(QStringLiteral("diagnostic")));
    backend.runCommand(
        QStringLiteral("/bin/sh"),
        {QStringLiteral("-c"), QStringLiteral("printf failed >&2; exit 2")},
        [&](const QString &) {
            ++success;
        },
        [&]() {
            ++failure;
        });
    QTRY_COMPARE(failure, 1);
    QCOMPARE(backend.error(), QStringLiteral("failed"));
    backend.runCommand(
        QStringLiteral("/nonexistent/batctl-audit-process"),
        {},
        [&](const QString &) {
            ++success;
        },
        [&]() {
            ++failure;
        });
    QTRY_COMPARE(failure, 2);
    QCOMPARE(success, 1);
}

void BatctlBackendTest::preservesWriteFailure()
{
    BatctlBackend backend;
    QTRY_VERIFY(!backend.busy());
    backend.m_writeError = QStringLiteral("Persistence save failed");
    backend.m_writeWarning = QStringLiteral("Hardware warning");
    backend.refresh();
    QVERIFY(backend.error().contains(backend.m_writeError));
    QTRY_VERIFY(!backend.busy());
    backend.m_batctlPath = QStringLiteral("/bin/sh");
    backend.m_pendingReads = 1;
    backend.setBusy(true);
    backend.runReadCommand({QStringLiteral("-c"), QStringLiteral("sleep 0.1")}, [](const QString &) { });
    backend.refresh();
    QVERIFY(backend.m_refreshPending);
    QTRY_VERIFY(!backend.busy());
    QVERIFY(!backend.m_refreshPending);
    QVERIFY(backend.error().contains(backend.m_writeError));
    QVERIFY(backend.warning().contains(backend.m_writeWarning));
}

QTEST_GUILESS_MAIN(BatctlBackendTest)
#include "batctlbackend_test.moc"
