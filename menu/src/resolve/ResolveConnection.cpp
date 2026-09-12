#include "ResolveConnection.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>

ResolveConnection::ResolveConnection(const QString& scriptApiPath, const QString& scriptLibPath, QObject* parent)
    : QObject(parent)
    , m_scriptApiPath(scriptApiPath)
    , m_scriptLibPath(scriptLibPath)
{
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(500); // Poll every 500ms
    connect(m_pollTimer, &QTimer::timeout, this, &ResolveConnection::pollCurrentPage);
}

ResolveConnection::~ResolveConnection()
{
    stop();
}

void ResolveConnection::start()
{
    if (m_pythonProcess) return;
    
    launchResolveScript();
    m_pollTimer->start();
}

void ResolveConnection::stop()
{
    m_pollTimer->stop();
    if (m_pythonProcess) {
        m_pythonProcess->terminate();
        if (!m_pythonProcess->waitForFinished(1000)) {
            m_pythonProcess->kill();
        }
        m_pythonProcess->deleteLater();
        m_pythonProcess = nullptr;
    }
    m_connected = false;
}

bool ResolveConnection::launchResolveScript()
{
    // Exactly one long-lived helper process. The QProcess object is created
    // once and reused so the finished()/readyRead() connections survive
    // relaunches after a crash.
    if (!m_pythonProcess) {
        m_pythonProcess = new QProcess(this);

        connect(m_pythonProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ResolveConnection::onProcessFinished);
        connect(m_pythonProcess, &QProcess::readyReadStandardOutput,
                this, &ResolveConnection::onReadyReadStandardOutput);
        connect(m_pythonProcess, &QProcess::readyReadStandardError,
                this, &ResolveConnection::onReadyReadStandardError);
    }

    if (m_pythonProcess->state() != QProcess::NotRunning)
        return true;

    // Set up environment for DaVinciResolveScript.
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    if (!m_scriptApiPath.isEmpty())
        env.insert("RESOLVE_SCRIPT_API", m_scriptApiPath);
    if (!m_scriptLibPath.isEmpty())
        env.insert("RESOLVE_SCRIPT_LIB", m_scriptLibPath);
    m_pythonProcess->setProcessEnvironment(env);

    // Persistent helper: prints the current page only when it changes
    // (change-based monitoring, spec section 7.1) and sleeps in between.
    QString script = R"(
import os, sys, time

api_path = os.environ.get('RESOLVE_SCRIPT_API', '')
lib_path = os.environ.get('RESOLVE_SCRIPT_LIB', '')
if api_path:
    sys.path.insert(0, api_path)
if lib_path:
    sys.path.insert(0, lib_path)

try:
    import DaVinciResolveScript as dvr
except Exception as e:
    print("ERROR: %s" % e, flush=True)
    sys.exit(1)

try:
    resolve = dvr.scriptapp("Resolve")
except Exception as e:
    print("ERROR: %s" % e, flush=True)
    sys.exit(1)

if not resolve:
    print("ERROR: Could not connect to Resolve", flush=True)
    sys.exit(1)

last = None
while True:
    try:
        page = resolve.GetCurrentPage()
    except Exception as e:
        print("ERROR: %s" % e, flush=True)
        time.sleep(1.0)
        continue
    if page and page != last:
        print(page, flush=True)
        last = page
    time.sleep(0.5)
)";

    m_pythonProcess->setProgram("python");
    m_pythonProcess->setArguments({"-c", script});

    m_pythonProcess->start();
    return m_pythonProcess->waitForStarted(5000);
}

void ResolveConnection::pollCurrentPage()
{
    // The helper is a persistent process that reports page changes on its own.
    // This timer only checks liveness and relaunches after a crash.
    if (m_pythonProcess && m_pythonProcess->state() != QProcess::NotRunning)
        return;

    if (m_restartPending)
        return;

    m_retryCount = qMin(m_retryCount + 1, 6);
    const int delayMs = qMin(1000 * (1 << m_retryCount), 30000); // 2s .. 30s
    m_restartPending = true;

    QTimer::singleShot(delayMs, this, [this]() {
        m_restartPending = false;
        if (!launchResolveScript()) {
            qWarning() << "Resolve helper failed to start; will retry.";
        }
    });
}

void ResolveConnection::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitCode);
    Q_UNUSED(exitStatus);
    // Process finished, will be restarted on next poll
}

void ResolveConnection::onReadyReadStandardOutput()
{
    QString output = QString::fromUtf8(m_pythonProcess->readAllStandardOutput()).trimmed();
    if (output.startsWith("ERROR:")) {
        qWarning() << "Resolve script error:" << output;
        if (m_connected) {
            m_connected = false;
            emit connectionStatusChanged(false);
        }
        return;
    }

    QString page = parsePageFromOutput(output);
    if (!page.isEmpty()) {
        // A valid page proves Resolve is reachable: this is the only place
        // the retry counter is reset, so a helper that starts successfully
        // but cannot import DaVinciResolveScript still backs off.
        m_retryCount = 0;
        if (page != m_currentPage) {
            m_previousPage = m_currentPage;
            m_currentPage = page;
            m_connected = true;
            emit connectionStatusChanged(true);
            emit pageChanged(page);
        }
    }
}

void ResolveConnection::onReadyReadStandardError()
{
    QString error = QString::fromUtf8(m_pythonProcess->readAllStandardError()).trimmed();
    if (!error.isEmpty()) {
        qWarning() << "Resolve script stderr:" << error;
    }
}

QString ResolveConnection::parsePageFromOutput(const QString& output)
{
    // GetCurrentPage() returns lowercase page names
    static const QStringList validPages = {"media", "cut", "edit", "fusion", "color", "fairlight", "deliver"};
    QString page = output.toLower().trimmed();
    if (validPages.contains(page)) {
        return page;
    }
    return QString();
}