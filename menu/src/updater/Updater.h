#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QUrl>
#include <QTimer>
#include <QCryptographicHash>
#include <QFile>
#include <QProcess>

class Updater : public QObject
{
    Q_OBJECT

public:
    explicit Updater(const QString& manifestUrl, QObject* parent = nullptr);
    
    void startPeriodicCheck(int intervalMs);
    void checkForUpdates();
    QString currentVersion() const { return m_currentVersion; }
    void setCurrentVersion(const QString& version) { m_currentVersion = version; }

signals:
    void updateAvailable(const QString& version, const QString& notes, const QUrl& downloadUrl, const QString& sha256);
    void noUpdateAvailable();
    void errorOccurred(const QString& message);

private slots:
    void onManifestDownloaded(QNetworkReply* reply);
    void onInstallerDownloaded(QNetworkReply* reply);
    void installUpdate(const QString& filePath);

private:
    void downloadInstaller(const QUrl& url, const QString& sha256);
    bool verifyChecksum(const QString& filePath, const QString& expectedSha256);

    QString m_manifestUrl;
    QString m_currentVersion = "1.0.0";
    QString m_expectedSha256;
    QNetworkAccessManager* m_networkManager;
    QTimer* m_checkTimer;
    QNetworkReply* m_currentDownload = nullptr;
};