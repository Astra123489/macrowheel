#pragma once

#include <QObject>
#include <QString>
#include <QProcess>
#include <QTimer>
#include <QMutex>

class ResolveConnection : public QObject
{
    Q_OBJECT

public:
    explicit ResolveConnection(const QString& scriptApiPath, const QString& scriptLibPath, QObject* parent = nullptr);
    ~ResolveConnection();

    void start();
    void stop();
    bool isConnected() const { return m_connected; }
    QString currentPage() const { return m_currentPage; }

signals:
    void pageChanged(const QString& pageName);
    void connectionStatusChanged(bool connected);
    void errorOccurred(const QString& message);

private slots:
    void pollCurrentPage();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onReadyReadStandardOutput();
    void onReadyReadStandardError();

private:
    bool launchResolveScript();
    QString parsePageFromOutput(const QString& output);

    QString m_scriptApiPath;
    QString m_scriptLibPath;
    QProcess* m_pythonProcess = nullptr;
    QTimer* m_pollTimer = nullptr;
    QString m_currentPage;
    QString m_previousPage;
    bool m_connected = false;
    bool m_restartPending = false;
    int m_retryCount = 0;
    QMutex m_mutex;
};