#include "batctlplasmaplugin.h"

#include "batctlbackend.h"

#include <QQmlEngine>

void BatctlPlasmaPlugin::registerTypes(const char *uri)
{
    qmlRegisterType<BatctlBackend>(uri, 1, 0, "BatctlBackend");
}
