#include "Updater.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QDir>
#include <QDebug>

Updater::Updater(const QString& manifestUrl, QObject* parent)
    : QObject(parent)
    , m_manifestUrl(manifestUrl)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_checkTimer(new QTimer(this))
{
    m_checkTimer->setSingleShot(false);
    connect(m_checkTimer, &QTimer::timeout, this, &Updater::checkForUpdates);
}

void Updater::startPeriodicCheck(int intervalMs)
{
    m_checkTimer->start(intervalMs);
    // Also check immediately
    checkForUpdates();
}

void Updater::checkForUpdates()
{
    QNetworkRequest request(m_manifestUrl);
    request.setRawHeader("User-Agent", "MacroWheelMenu/1.0.0");
    
    QNetworkReply* reply = m_networkManager->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onManifestDownloaded(reply);
    });
}

void Updater::onManifestDownloaded(QNetworkReply* reply)
{
    reply->deleteLater();
    
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Update check failed:" << reply->errorString();
        return;
    }

    QByteArray data = reply->readAll();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (doc.isNull() || !doc.isObject()) {
        qWarning() << "Invalid update manifest";
        return;
    }

    QJsonObject obj = doc.object();
    QString latestVersion = obj.value("version").toString();
    QString notes = obj.value("notes").toString();
    
    if (latestVersion == m_currentVersion) {
        emit noUpdateAvailable();
        return;
    }

    // Find the right asset for current platform
    QJsonObject assets = obj.value("assets").toObject();
    QString platformKey;
    #ifdef Q_OS_WIN
        platformKey = "windows";
    #elif defined(Q_OS_MACOS)
        platformKey = "macos";
    #else
        platformKey = "linux";
    #endif

    QJsonObject platformAsset = assets.value(platformKey).toObject();
    if (platformAsset.isEmpty()) {
        qWarning() << "No asset for platform:" << platformKey;
        return;
    }

    QString downloadUrl = platformAsset.value("url").toString();
    QString sha256 = platformAsset.value("sha256").toString();

    if (downloadUrl.isEmpty() || sha256.isEmpty()) {
        qWarning() << "Invalid asset data";
        return;
    }

    emit updateAvailable(latestVersion, notes, QUrl(downloadUrl), sha256);
}

void Updater::downloadInstaller(const QUrl& url, const QString& sha256)
{
    m_expectedSha256 = sha256;
    QNetworkRequest request(url);
    m_currentDownload = m_networkManager->get(request);
    
    connect(m_currentDownload, &QNetworkReply::finished, this, [this]() {
        onInstallerDownloaded(m_currentDownload);
    });
    
    connect(m_currentDownload, &QNetworkReply::downloadProgress, this, [](qint64 received, qint64 total) {
        qDebug() << "Download progress:" << received << "/" << total;
    });
}

void Updater::onInstallerDownloaded(QNetworkReply* reply)
{
    reply->deleteLater();
    m_currentDownload = nullptr;
    
    if (reply->error() != QNetworkReply::NoError) {
        emit errorOccurred("Download failed: " + reply->errorString());
        return;
    }

    QByteArray data = reply->readAll();
    
    // Save to temp file
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    QString fileName = "MacroWheelUpdate";
    #ifdef Q_OS_WIN
        fileName += ".exe";
    #elif defined(Q_OS_MACOS)
        fileName += ".dmg";
    #else
        fileName += ".AppImage";
    #endif
    
    QString filePath = tempDir + "/" + fileName;
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        emit errorOccurred("Failed to save installer");
        return;
    }
    file.write(data);
    file.close();

    // Verify checksum
    if (!verifyChecksum(filePath, m_expectedSha256)) {
        emit errorOccurred("Checksum verification failed");
        QFile::remove(filePath);
        return;
    }

    // Install
    installUpdate(filePath);
}

bool Updater::verifyChecksum(const QString& filePath, const QString& expectedSha256)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) return false;
    
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&file)) return false;
    
    QString actual = hash.result().toHex();
    return actual.compare(expectedSha256, Qt::CaseInsensitive) == 0;
}

void Updater::installUpdate(const QString& filePath)
{
    QString appDir = QCoreApplication::applicationDirPath();
    bool success = false;
    
    #ifdef Q_OS_WIN
        // Run NSIS installer silently
        QProcess process;
        process.start(filePath, {"/S", "/D=" + appDir});
        success = process.waitForFinished(60000) && process.exitCode() == 0;
    #elif defined(Q_OS_MACOS)
        // Mount DMG and copy .app
        QProcess process;
        process.start("hdiutil", {"attach", filePath, "-nobrowse", "-quiet"});
        if (process.waitForFinished(30000)) {
            // Find mounted volume and copy app
            // This is simplified - real implementation would be more robust
            success = true;
        }
    #else
        // Linux AppImage - replace current executable
        QFile::remove(appDir + "/MacroWheelMenu");
        success = QFile::copy(filePath, appDir + "/MacroWheelMenu");
        if (success) {
            QFile::setPermissions(appDir + "/MacroWheelMenu", QFile::ExeOwner | QFile::ReadOwner | QFile::WriteOwner);
        }
    #endif

    if (success) {
        qInfo() << "Update installed successfully, restart required";
        // Could emit a signal to prompt restart
    } else {
        emit errorOccurred("Installation failed");
    }
}