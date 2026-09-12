#pragma once

#include <QObject>
#include <QString>

class ConfigService;
class ResolveConnection;
class Updater;
class GlobalHotkey;

// Tray controller.
//
// The visual tray (icon, menu, notifications) is provided by QML through
// Qt.labs.platform's SystemTrayIcon, which works with QGuiApplication.
// QSystemTrayIcon (QtWidgets) is intentionally NOT used: the Menu must not
// depend on QtWidgets.
//
// This class holds the state the tray displays and exposes the user actions.
class TrayIcon : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool connected READ isConnected NOTIFY connectionStatusChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY connectionStatusChanged)
    Q_PROPERTY(QString pageName READ pageName NOTIFY statusChanged)
    Q_PROPERTY(QString profileName READ profileName NOTIFY statusChanged)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    explicit TrayIcon(ConfigService* configService,
                      ResolveConnection* resolveConnection,
                      Updater* updater,
                      GlobalHotkey* globalHotkey,
                      QObject* parent = nullptr);

    bool isConnected() const;
    QString statusText() const;
    QString pageName() const;
    QString profileName() const;
    QString version() const;

    // Called from QML (tray menu items).
    Q_INVOKABLE void requestProfileCycle();
    Q_INVOKABLE void requestCheckForUpdates();
    Q_INVOKABLE void requestOpenConfigFolder();
    Q_INVOKABLE void requestQuit();

signals:
    void connectionStatusChanged();
    void statusChanged();
    void profileCycleRequested();
    void settingsRequested();
    void quitRequested();
    void notificationRequested(const QString& title, const QString& message);

private:
    ConfigService* m_configService;
    ResolveConnection* m_resolveConnection;
    Updater* m_updater;
    GlobalHotkey* m_globalHotkey;
};