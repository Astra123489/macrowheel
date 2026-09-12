#include "ScriptLauncher.h"
#include "ScriptRuntimeManager.h"

ScriptLauncher::ScriptLauncher(ScriptRuntimeManager* runtimeManager, QObject* parent)
    : QObject(parent)
    , m_runtimeManager(runtimeManager)
{
}

void ScriptLauncher::launchScript(const QUuid& scriptId)
{
    // This is a thin wrapper around ScriptRuntimeManager::runScript
    // The actual execution happens in ScriptRuntimeManager
    m_runtimeManager->runScript(scriptId);
    emit launched(scriptId);
}