#include "batctlbackend.h"

#include <QtTest>

class BatctlBackendTest final : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesStatus();
    void parsesPresets();
    void parsesDetect();
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

QTEST_GUILESS_MAIN(BatctlBackendTest)
#include "batctlbackend_test.moc"
