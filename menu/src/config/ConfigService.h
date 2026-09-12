#pragma once

#include <QObject>
#include <QFileSystemWatcher>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutex>
#include <QSharedPointer>
#include <QString>
#include <QUuid>

#include "generated/ConfigTypes.h"

class ConfigService : public QObject
{
    Q_OBJECT

public:
    explicit ConfigService(const QString& configPath, QObject* parent = nullptr);
    ~ConfigService();

    bool load();
    const RuntimeConfig& currentConfig() const;
    
    // Accessors for commonly used config sections
    const InteractionSettings& interactionSettings() const;
    const WheelSettings& wheelSettings() const;
    const ScriptRuntimeConfig& scriptRuntimeConfig() const;
    QString resolveScriptApiPath() const;
    QString resolveScriptLibPath() const;
    QString shortcutPresetPath() const;

    // Looks up a user-defined command's key sequence.
    // Custom commands are user-owned (spec 13.6); their binding is stored in
    // the configuration rather than in the built-in registry.
    QString customCommandSequence(const QString& customId) const;

signals:
    void configurationChanged(const RuntimeConfig& newConfig);

private slots:
    void onFileChanged(const QString& path);

private:
    bool validateAndParse(const QByteArray& data, RuntimeConfig& outConfig);
    void debouncedReload();

    QString m_configPath;
    QFileSystemWatcher m_watcher;
    mutable QMutex m_mutex;
    QSharedPointer<RuntimeConfig> m_currentConfig;
    QTimer* m_debounceTimer;
};