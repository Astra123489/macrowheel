#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QLoggingCategory>
#include <QDir>
#include <QStandardPaths>

#include "config/ConfigService.h"
#include "resolve/ResolveConnection.h"
#include "profile/ProfileResolver.h"
#include "wheel/WheelGeometry.h"
#include "commands/CommandExecutor.h"
#include "commands/ShortcutResolver.h"
#include "script/ScriptRuntimeManager.h"
#include "hotkey/GlobalHotkey.h"
#include "updater/Updater.h"
#include "tray/TrayIcon.h"

#include <QFile>

int main(int argc, char *argv[])
{
    // Must be set before the application object is constructed.
    // Qt 6 scales by default; AA_EnableHighDpiScaling and AA_UseHighDpiPixmaps
    // are removed/no-ops in Qt 6 and must not be used.
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QGuiApplication app(argc, argv);
    app.setApplicationName("MacroWheelMenu");
    // Supplied by the build (see MACROWHEEL_VERSION in CMakeLists.txt) so the
    // running version, the installer, and latest.json cannot drift apart.
    app.setApplicationVersion(MACROWHEEL_VERSION);
    app.setOrganizationName("MacroWheel");
    app.setQuitOnLastWindowClosed(false); // keep running in the tray

    // Set up logging
    QLoggingCategory::setFilterRules("*.debug=false\nmacro_wheel.*.debug=true");

    // Determine config directory (per-OS convention)
    QString configDir;
    #ifdef Q_OS_WIN
        configDir = qgetenv("APPDATA") + "/MacroWheel";
    #elif defined(Q_OS_MACOS)
        configDir = QDir::homePath() + "/Library/Application Support/MacroWheel";
    #else
        QString xdgConfig = qgetenv("XDG_CONFIG_HOME");
        if (xdgConfig.isEmpty()) xdgConfig = QDir::homePath() + "/.config";
        configDir = xdgConfig + "/macrowheel";
    #endif

    QDir().mkpath(configDir);
    QString configPath = configDir + "/configuration.json";
    QString scriptsDir = configDir + "/scripts";
    QDir().mkpath(scriptsDir);

    // Initialize core services
    ConfigService configService(configPath);
    if (!configService.load()) {
        qCritical() << "Failed to load configuration from" << configPath;
        return 1;
    }

    // Export the Resolve scripting paths for the whole process tree. Child
    // processes — the Command Runtime helper and every user script — inherit
    // these and use them to import DaVinciResolveScript.
    const QString resolveApiPath = configService.resolveScriptApiPath();
    const QString resolveLibPath = configService.resolveScriptLibPath();
    if (!resolveApiPath.isEmpty())
        qputenv("RESOLVE_SCRIPT_API", resolveApiPath.toUtf8());
    if (!resolveLibPath.isEmpty())
        qputenv("RESOLVE_SCRIPT_LIB", resolveLibPath.toUtf8());

    ScriptRuntimeManager scriptRuntimeManager(scriptsDir, configService.scriptRuntimeConfig());
    ResolveConnection resolveConnection(configService.resolveScriptApiPath(),
                                        configService.resolveScriptLibPath());
    ProfileResolver profileResolver(&configService, &resolveConnection);
    WheelGeometry wheelGeometry;
    CommandExecutor commandExecutor(&configService, &scriptRuntimeManager, &resolveConnection);
    GlobalHotkey globalHotkey(configService.interactionSettings().wheelActivationHotkey);
    Updater updater(QStringLiteral(
        "https://github.com/Astra123489/macrowheel/releases/latest/download/latest.json"));

    // The updater decides whether an update exists by comparing latest.json
    // against the running build, so it has to use the version the application
    // reports rather than its own hardcoded default.
    updater.setCurrentVersion(QCoreApplication::applicationVersion());

    TrayIcon trayIcon(&configService, &resolveConnection, &updater, &globalHotkey);

    // Resolve the Search Effects shortcut from the imported preset. The Menu
    // needs only this one binding (spec section 13.3); conflict analysis lives
    // in Studio.
    {
        ShortcutResolver shortcutResolver;
        QFile preset(configService.shortcutPresetPath());
        if (preset.exists() && preset.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString contents = QString::fromUtf8(preset.readAll());
            preset.close();
            if (shortcutResolver.parse(contents)) {
                const QString seq = shortcutResolver.searchEffectsShortcut();
                if (!seq.isEmpty())
                    commandExecutor.setSearchEffectsShortcut(seq);
                else
                    qWarning() << "Preset has no editSearchInEffects binding; "
                                  "using the built-in default for Add Effects.";
            }
        } else {
            qWarning() << "Shortcut preset not readable:" << configService.shortcutPresetPath();
        }
    }

    // --- Signal wiring ----------------------------------------------------
    QObject::connect(&resolveConnection, &ResolveConnection::pageChanged,
                     &profileResolver, &ProfileResolver::onPageChanged);
    QObject::connect(&profileResolver, &ProfileResolver::activeProfileChanged,
                     &wheelGeometry, &WheelGeometry::onActiveProfileChanged);
    QObject::connect(&wheelGeometry, &WheelGeometry::commandTriggered,
                     &commandExecutor, &CommandExecutor::executeCommand);

    QObject::connect(&configService, &ConfigService::configurationChanged,
                     &profileResolver, &ProfileResolver::onConfigurationChanged);
    QObject::connect(&configService, &ConfigService::configurationChanged,
                     &scriptRuntimeManager, &ScriptRuntimeManager::onConfigurationChanged);
    QObject::connect(&configService, &ConfigService::configurationChanged,
                     &globalHotkey, [&globalHotkey](const RuntimeConfig& cfg) {
                         globalHotkey.onConfigurationChanged(cfg.interactionSettings);
                     });

    QObject::connect(&trayIcon, &TrayIcon::profileCycleRequested,
                     &profileResolver, &ProfileResolver::cycleProfile);
    QObject::connect(&trayIcon, &TrayIcon::quitRequested,
                     &app, &QCoreApplication::quit);

    // --- Start ------------------------------------------------------------
    // Resolve may not be running yet; ResolveConnection retries on a timer and
    // the wheel stays disabled until a page is reported (spec section 21.3).
    resolveConnection.start();

    // Hotkey registration failure is non-fatal: the tray still works and the
    // error is surfaced to the user.
    QObject::connect(&globalHotkey, &GlobalHotkey::errorOccurred,
                     &trayIcon, [&trayIcon](const QString& message) {
                         trayIcon.notificationRequested(
                             QStringLiteral("Macro Wheel"), message);
                     });
    globalHotkey.start();

    // Start update checker (periodic)
    updater.startPeriodicCheck(6 * 60 * 60 * 1000); // 6 hours

    // Set up QML engine
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("wheelGeometry", &wheelGeometry);
    engine.rootContext()->setContextProperty("profileResolver", &profileResolver);
    engine.rootContext()->setContextProperty("resolveConnection", &resolveConnection);
    engine.rootContext()->setContextProperty("trayIcon", &trayIcon);
    engine.rootContext()->setContextProperty("globalHotkey", &globalHotkey);
    engine.rootContext()->setContextProperty("updater", &updater);

    const QUrl url(QStringLiteral("qrc:/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}