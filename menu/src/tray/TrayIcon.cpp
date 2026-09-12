#include "TrayIcon.h"
#include "config/ConfigService.h"
#include "resolve/ResolveConnection.h"
#include "updater/Updater.h"
#include "hotkey/GlobalHotkey.h"
#include "profile/ProfileResolver.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QUrl>

TrayIcon::TrayIcon(ConfigService* configService,
                   ResolveConnection* resolveConnection,
                   Updater* updater,
                   GlobalHotkey* globalHotkey,
                   QObject* parent)
    : QObject(parent)
    , m_configService(configService)
    , m_resolveConnection(resolveConnection)
    , m_updater(updater)
    , m_globalHotkey(globalHotkey)
{
    connect(m_resolveConnection, &ResolveConnection::connectionStatusChanged,
            this, &TrayIcon::connectionStatusChanged);
    connect(m_resolveConnection, &ResolveConnection::pageChanged,
            this, &TrayIcon::statusChanged);

    connect(m_updater, &Updater::updateAvailable,
            this, [this](const QString& version, const QString& notes, const QUrl&, const QString&) {
        emit notificationRequested(
            QStringLiteral("Macro Wheel update available"),
            QStringLiteral("Version %1 is available.\n%2").arg(version, notes));
    });
}

bool TrayIcon::isConnected() const
{
    return m_resolveConnection && m_resolveConnection->isConnected();
}

QString TrayIcon::statusText() const
{
    return isConnected() ? QStringLiteral("DaVinci Resolve: connected")
                         : QStringLiteral("DaVinci Resolve: not connected");
}

QString TrayIcon::pageName() const
{
    return m_resolveConnection ? m_resolveConnection->currentPage() : QString();
}

QString TrayIcon::profileName() const
{
    // The active profile name is owned by ProfileResolver; the tray reads the
    // same resolved state through the configuration snapshot.
    return QString();
}

QString TrayIcon::version() const
{
    return QCoreApplication::applicationVersion();
}

void TrayIcon::requestProfileCycle()
{
    emit profileCycleRequested();
}

void TrayIcon::requestCheckForUpdates()
{
    if (m_updater) m_updater->checkForUpdates();
}

void TrayIcon::requestOpenConfigFolder()
{
    // The configuration file lives in the per-OS application data directory.
    // Opening its folder is the only filesystem action the tray performs.
    const QString scriptsFolder = m_configService ? m_configService->currentConfig().scriptsFolder
                                                  : QString();
    if (scriptsFolder.isEmpty()) return;
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(scriptsFolder).absolutePath()));
}

void TrayIcon::requestQuit()
{
    emit quitRequested();
    QCoreApplication::quit();
}