#include "ScriptRuntimeManager.h"
#include <QProcess>
#include <QProcessEnvironment>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QStandardPaths>

ScriptRuntimeManager::ScriptRuntimeManager(const QString& scriptsDir, const ScriptRuntimeConfig& config, QObject* parent)
    : QObject(parent)
    , m_scriptsDir(scriptsDir)
    , m_config(config)
{
}

ScriptRuntimeManager::~ScriptRuntimeManager()
{
}

bool ScriptRuntimeManager::initialize()
{
    if (m_initialized) return true;

    QString appDir = QCoreApplication::applicationDirPath();
    
    if (m_config.mode == ScriptRuntimeConfig::Mode::Custom && !m_config.customPythonPath.isEmpty()) {
        m_pythonPath = m_config.customPythonPath;
        m_userSitePackagesDir = ""; // Custom Python manages its own packages
        m_bundledSitePackagesDir = "";
    } else {
        // Use managed python-build-standalone
        m_pythonPath = appDir + "/script_runtime/python";
        #ifdef Q_OS_WIN
            m_pythonPath += ".exe";
        #endif
        
        m_bundledSitePackagesDir = appDir + "/script_runtime/site-packages/bundled";
        m_userSitePackagesDir = appDir + "/script_runtime/site-packages/user";
        QDir().mkpath(m_userSitePackagesDir);
    }

    // Verify Python executable exists
    if (!QFile::exists(m_pythonPath)) {
        emit errorOccurred(QString("Python executable not found: %1").arg(m_pythonPath));
        return false;
    }

    m_initialized = true;
    return true;
}

QString ScriptRuntimeManager::pythonExecutable() const
{
    return m_pythonPath;
}

QProcessEnvironment ScriptRuntimeManager::pythonEnvironment() const
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    
    if (m_config.mode == ScriptRuntimeConfig::Mode::Managed) {
        // Set PYTHONPATH to include bundled and user packages
        QString pythonPath = m_bundledSitePackagesDir;
        if (!m_userSitePackagesDir.isEmpty()) {
            pythonPath += ";" + m_userSitePackagesDir;
        }
        
        // Also add Resolve scripting paths
        QString resolveApi = qgetenv("RESOLVE_SCRIPT_API");
        QString resolveLib = qgetenv("RESOLVE_SCRIPT_LIB");
        if (!resolveApi.isEmpty()) pythonPath += ";" + resolveApi;
        if (!resolveLib.isEmpty()) pythonPath += ";" + resolveLib;
        
        env.insert("PYTHONPATH", pythonPath);
    }
    
    return env;
}

void ScriptRuntimeManager::runScript(const QUuid& scriptId)
{
    if (!initialize()) {
        emit scriptFinished(scriptId, false, "Runtime not initialized");
        return;
    }

    QString scriptPath = resolveScriptPath(scriptId);
    if (scriptPath.isEmpty() || !QFile::exists(scriptPath)) {
        emit scriptFinished(scriptId, false, "Script file not found");
        return;
    }

    emit scriptStarted(scriptId);

    QProcess* process = new QProcess(this);
    process->setProgram(m_pythonPath);
    process->setArguments({scriptPath});
    process->setProcessEnvironment(pythonEnvironment());
    process->setWorkingDirectory(m_scriptsDir);

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, process, scriptId](int exitCode, QProcess::ExitStatus status) {
        QString output = QString::fromUtf8(process->readAllStandardOutput());
        QString error = QString::fromUtf8(process->readAllStandardError());
        bool success = (exitCode == 0 && status == QProcess::NormalExit);
        if (!success) {
            output = error.isEmpty() ? output : error;
        }
        emit scriptFinished(scriptId, success, output);
        process->deleteLater();
    });

    process->start();
}

QString ScriptRuntimeManager::resolveScriptPath(const QUuid& scriptId) const
{
    // Scan scripts directory for .py files with matching MacroWheel ID
    QDir dir(m_scriptsDir);
    QStringList filters = {"*.py"};
    QFileInfoList files = dir.entryInfoList(filters, QDir::Files);

    for (const QFileInfo& file : files) {
        QFile f(file.absoluteFilePath());
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&f);
            QString firstLine = in.readLine();
            f.close();
            
            if (firstLine.contains("MacroWheel ID:")) {
                QString idStr = firstLine.split("MacroWheel ID:").last().trimmed();
                QUuid id(idStr);
                if (id == scriptId) {
                    return file.absoluteFilePath();
                }
            }
        }
    }
    return QString();
}

bool ScriptRuntimeManager::installPackage(const QString& name, const QString& version)
{
    if (m_config.mode != ScriptRuntimeConfig::Mode::Managed) {
        emit errorOccurred("Package installation only available in managed mode");
        return false;
    }

    QStringList args = {"-m", "pip", "install", "--target", m_userSitePackagesDir};
    if (!version.isEmpty()) {
        args.append(name + "==" + version);
    } else {
        args.append(name);
    }

    return runPipCommand(args);
}

bool ScriptRuntimeManager::removePackage(const QString& name)
{
    if (m_config.mode != ScriptRuntimeConfig::Mode::Managed) {
        emit errorOccurred("Package removal only available in managed mode");
        return false;
    }

    // Remove from user site-packages
    QString packageDir = m_userSitePackagesDir + "/" + name;
    QDir dir(packageDir);
    if (dir.exists()) {
        dir.removeRecursively();
    }
    
    // Also remove any .dist-info or .egg-info
    QFileInfoList entries = QDir(m_userSitePackagesDir).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo& entry : entries) {
        if (entry.fileName().startsWith(name + "-") || entry.fileName().startsWith(name + ".")) {
            QDir(entry.absoluteFilePath()).removeRecursively();
        }
    }

    emit packageListChanged();
    return true;
}

QVector<PackageInfo> ScriptRuntimeManager::listPackages() const
{
    QVector<PackageInfo> packages;

    if (m_config.mode != ScriptRuntimeConfig::Mode::Managed) {
        return packages;
    }

    // List bundled packages
    QDir bundledDir(m_bundledSitePackagesDir);
    if (bundledDir.exists()) {
        QFileInfoList entries = bundledDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& entry : entries) {
            PackageInfo info;
            info.name = entry.fileName();
            info.isBundled = true;
            // Try to read version from metadata
            packages.append(info);
        }
    }

    // List user packages
    QDir userDir(m_userSitePackagesDir);
    if (userDir.exists()) {
        QFileInfoList entries = userDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& entry : entries) {
            PackageInfo info;
            info.name = entry.fileName();
            info.isUserInstalled = true;
            packages.append(info);
        }
    }

    return packages;
}

bool ScriptRuntimeManager::resetToDefaults()
{
    if (m_config.mode != ScriptRuntimeConfig::Mode::Managed) {
        emit errorOccurred("Reset only available in managed mode");
        return false;
    }

    QDir userDir(m_userSitePackagesDir);
    if (userDir.exists()) {
        userDir.removeRecursively();
    }
    QDir().mkpath(m_userSitePackagesDir);

    emit packageListChanged();
    return true;
}

bool ScriptRuntimeManager::runPipCommand(const QStringList& args)
{
    QProcess process;
    process.setProgram(m_pythonPath);
    process.setArguments(args);
    process.setProcessEnvironment(pythonEnvironment());
    
    process.start();
    if (!process.waitForStarted(30000)) {
        emit errorOccurred("Failed to start pip");
        return false;
    }

    if (!process.waitForFinished(120000)) { // 2 minute timeout
        process.kill();
        emit errorOccurred("pip command timed out");
        return false;
    }

    if (process.exitCode() != 0) {
        QString error = QString::fromUtf8(process.readAllStandardError());
        emit errorOccurred("pip failed: " + error);
        return false;
    }

    emit packageListChanged();
    return true;
}

void ScriptRuntimeManager::onConfigurationChanged(const RuntimeConfig& newConfig)
{
    Q_UNUSED(newConfig);
    // Re-initialize if script runtime config changed
    // For simplicity, we'll just re-initialize on next use
    m_initialized = false;
}