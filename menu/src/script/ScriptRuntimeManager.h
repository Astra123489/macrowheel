#pragma once

#include <QObject>
#include <QUuid>
#include <QString>
#include <QMap>
#include <QVector>
#include <QProcessEnvironment>

#include "config/generated/ConfigTypes.h"

struct PackageInfo {
    QString name;
    QString version;
    bool isBundled = false;
    bool isUserInstalled = false;
};

class ScriptRuntimeManager : public QObject
{
    Q_OBJECT

public:
    explicit ScriptRuntimeManager(const QString& scriptsDir, const ScriptRuntimeConfig& config, QObject* parent = nullptr);
    ~ScriptRuntimeManager();

    bool initialize();
    void runScript(const QUuid& scriptId);

    // Package management (called from Studio via config changes)
    bool installPackage(const QString& name, const QString& version = QString());
    bool removePackage(const QString& name);
    QVector<PackageInfo> listPackages() const;
    bool resetToDefaults();

    void onConfigurationChanged(const RuntimeConfig& newConfig);

signals:
    void scriptStarted(const QUuid& scriptId);
    void scriptFinished(const QUuid& scriptId, bool success, const QString& output);
    void packageListChanged();
    void errorOccurred(const QString& message);

private:
    QString resolveScriptPath(const QUuid& scriptId) const;
    QString pythonExecutable() const;
    QProcessEnvironment pythonEnvironment() const;
    bool runPipCommand(const QStringList& args);

    QString m_scriptsDir;
    ScriptRuntimeConfig m_config;
    QString m_pythonPath;
    QString m_userSitePackagesDir;
    QString m_bundledSitePackagesDir;
    bool m_initialized = false;
};