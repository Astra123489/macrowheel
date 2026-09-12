#pragma once

#include <QObject>
#include <QUuid>

class ScriptRuntimeManager;

class ScriptLauncher : public QObject
{
    Q_OBJECT

public:
    explicit ScriptLauncher(ScriptRuntimeManager* runtimeManager, QObject* parent = nullptr);

public slots:
    void launchScript(const QUuid& scriptId);

signals:
    void launched(const QUuid& scriptId);
    void failed(const QUuid& scriptId, const QString& error);

private:
    ScriptRuntimeManager* m_runtimeManager;
};