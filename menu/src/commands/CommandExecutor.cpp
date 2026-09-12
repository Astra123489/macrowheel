#include "CommandExecutor.h"
#include "CommandRegistry.h"
#include "SendKeys.h"
#include "config/ConfigService.h"
#include "script/ScriptRuntimeManager.h"
#include "resolve/ResolveConnection.h"

#include <QDebug>
#include <QThread>

namespace {
// Delay between the fixed steps of the Add Effect automation. Resolve's
// search field needs a moment to appear and filter.
constexpr int kSearchOpenDelayMs = 120;
constexpr int kFilterDelayMs     = 80;
}

CommandExecutor::CommandExecutor(ConfigService* configService,
                                 ScriptRuntimeManager* scriptRuntimeManager,
                                 ResolveConnection* resolveConnection,
                                 QObject* parent)
    : QObject(parent)
    , m_configService(configService)
    , m_scriptRuntimeManager(scriptRuntimeManager)
    , m_resolveConnection(resolveConnection)
    , m_searchEffectsShortcut(QStringLiteral("Shift+Space")) // provisional
{
}

void CommandExecutor::setSearchEffectsShortcut(const QString& sequence)
{
    if (!sequence.isEmpty())
        m_searchEffectsShortcut = sequence;
}

void CommandExecutor::executeCommand(const QVariantMap& command)
{
    const QString type = command.value(QStringLiteral("type")).toString();
    const QString description = command.value(QStringLiteral("name"),
                                              command.value(QStringLiteral("id"))).toString();

    emit commandStarted(description);

    bool ok = false;

    if (type == QLatin1String("builtin")) {
        const QString id = command.value(QStringLiteral("id")).toString();
        // Built-in Add Effects are addressed as builtin.effect.*
        if (id.startsWith(QLatin1String("builtin.effect."))) {
            const QString payload = CommandRegistry::effectPayloadFor(id);
            ok = payload.isEmpty() ? false : executeAddEffect(payload);
        } else {
            ok = executeBuiltin(id);
        }
    } else if (type == QLatin1String("custom")) {
        ok = executeCustom(command.value(QStringLiteral("id")).toString());
    } else if (type == QLatin1String("script")) {
        ok = executeScript(command.value(QStringLiteral("id")).toString());
    } else if (type == QLatin1String("addEffect")) {
        ok = executeAddEffect(command.value(QStringLiteral("payload")).toString());
    } else {
        emit errorOccurred(QStringLiteral("Unknown command type: %1").arg(type));
    }

    emit commandFinished(description, ok);
}

bool CommandExecutor::executeBuiltin(const QString& builtinId)
{
    const QString sequence = CommandRegistry::keySequenceFor(builtinId);
    if (sequence.isEmpty()) {
        emit errorOccurred(QStringLiteral("No binding for built-in command: %1").arg(builtinId));
        return false;
    }
    sendKeystrokes(sequence);
    return true;
}

bool CommandExecutor::executeCustom(const QString& customId)
{
    const QString sequence = m_configService->customCommandSequence(customId);
    if (sequence.isEmpty()) {
        emit errorOccurred(QStringLiteral("Custom command not found: %1").arg(customId));
        return false;
    }
    sendKeystrokes(sequence);
    return true;
}

bool CommandExecutor::executeScript(const QString& scriptId)
{
    if (!m_scriptRuntimeManager) {
        emit errorOccurred(QStringLiteral("Script runtime unavailable"));
        return false;
    }
    // ScriptRuntimeManager resolves the ID to a file and runs it in a separate
    // process. Failures stay isolated from the Menu (spec 13.2.12).
    m_scriptRuntimeManager->runScript(QUuid(scriptId));
    return true;
}

bool CommandExecutor::executeAddEffect(const QString& payload)
{
    if (payload.isEmpty()) {
        emit errorOccurred(QStringLiteral("Add Effect command has no search payload"));
        return false;
    }

    // Fixed automation, not user editable (spec 13.3):
    //   Search Effects -> type payload -> Down -> Enter
    sendKeystrokes(m_searchEffectsShortcut);
    QThread::msleep(kSearchOpenDelayMs);
    SendKeys::sendText(payload);
    QThread::msleep(kFilterDelayMs);
    sendKeystrokes(QStringLiteral("Down"));
    QThread::msleep(kFilterDelayMs);
    sendKeystrokes(QStringLiteral("Enter"));
    return true;
}

void CommandExecutor::sendKeystrokes(const QString& keys)
{
    if (!SendKeys::send(keys)) {
        qWarning() << "Failed to send keystrokes:" << keys;
    }
}