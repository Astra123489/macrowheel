#include "ConfigService.h"
#include "SchemaValidator.h"
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <QDebug>

ConfigService::ConfigService(const QString& configPath, QObject* parent)
    : QObject(parent)
    , m_configPath(configPath)
    , m_debounceTimer(new QTimer(this))
{
    m_debounceTimer->setSingleShot(true);
    m_debounceTimer->setInterval(300); // 300ms debounce
    connect(m_debounceTimer, &QTimer::timeout, this, &ConfigService::debouncedReload);

    // Watch for file changes
    m_watcher.addPath(configPath);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged,
            this, &ConfigService::onFileChanged);
}

ConfigService::~ConfigService() = default;

bool ConfigService::load()
{
    QFile file(m_configPath);
    if (!file.exists()) {
        qWarning() << "Configuration file does not exist:" << m_configPath;
        return false;
    }

    if (!file.open(QIODevice::ReadOnly)) {
        qCritical() << "Failed to open config file:" << m_configPath;
        return false;
    }

    QByteArray data = file.readAll();
    file.close();

    RuntimeConfig config;
    if (!validateAndParse(data, config)) {
        return false;
    }

    QMutexLocker locker(&m_mutex);
    m_currentConfig = QSharedPointer<RuntimeConfig>::create(config);
    return true;
}

const RuntimeConfig& ConfigService::currentConfig() const
{
    QMutexLocker locker(&m_mutex);
    return *m_currentConfig;
}

const InteractionSettings& ConfigService::interactionSettings() const
{
    return currentConfig().interactionSettings;
}

const WheelSettings& ConfigService::wheelSettings() const
{
    return currentConfig().wheelSettings;
}

const ScriptRuntimeConfig& ConfigService::scriptRuntimeConfig() const
{
    return currentConfig().scriptRuntime;
}

QString ConfigService::resolveScriptApiPath() const
{
    const QMap<QString, PageConfig>& pages = currentConfig().pages;
    for (auto it = pages.constBegin(); it != pages.constEnd(); ++it) {
        if (!it.value().resolveScriptApiPath.isEmpty()) {
            return it.value().resolveScriptApiPath;
        }
    }
    return QString();
}

QString ConfigService::resolveScriptLibPath() const
{
    const QMap<QString, PageConfig>& pages = currentConfig().pages;
    for (auto it = pages.constBegin(); it != pages.constEnd(); ++it) {
        if (!it.value().resolveScriptLibPath.isEmpty()) {
            return it.value().resolveScriptLibPath;
        }
    }
    return QString();
}

QString ConfigService::shortcutPresetPath() const
{
    return currentConfig().shortcutPresetPath;
}

QString ConfigService::customCommandSequence(const QString& customId) const
{
    return currentConfig().customCommands.value(customId);
}

void ConfigService::onFileChanged(const QString& path)
{
    Q_UNUSED(path);
    m_debounceTimer->start();
}

void ConfigService::debouncedReload()
{
    QFile file(m_configPath);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "Failed to open config for reload:" << m_configPath;
        return;
    }

    QByteArray data = file.readAll();
    file.close();

    RuntimeConfig newConfig;
    if (!validateAndParse(data, newConfig)) {
        qWarning() << "Invalid configuration, keeping previous";
        return;
    }

    QMutexLocker locker(&m_mutex);
    m_currentConfig = QSharedPointer<RuntimeConfig>::create(newConfig);
    locker.unlock();

    emit configurationChanged(newConfig);
}

bool ConfigService::validateAndParse(const QByteArray& data, RuntimeConfig& outConfig)
{
    // Validate against JSON schema
    if (!SchemaValidator::validate(data)) {
        qCritical() << "Configuration schema validation failed";
        return false;
    }

    // Parse JSON
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (doc.isNull() || !doc.isObject()) {
        qCritical() << "Configuration is not a valid JSON object";
        return false;
    }

    // Parse into typed struct (generated from schema)
    outConfig = RuntimeConfig::fromJson(doc.object());
    return true;
}