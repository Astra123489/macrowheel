#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>

class ConfigService;
class ScriptRuntimeManager;
class ResolveConnection;
class ShortcutResolver;

// Executes a wheel selection.
//
// Input is the payload emitted by WheelGeometry::commandTriggered:
//   { "type": "builtin"|"custom"|"script"|"addEffect", ... }
//
// Built-in and Add Effect commands are performed with native keystroke
// injection through SendKeys. No Python process is spawned per command; the
// Command Runtime is only involved when a built-in genuinely needs the Resolve
// scripting API.
class CommandExecutor : public QObject
{
    Q_OBJECT

public:
    explicit CommandExecutor(ConfigService* configService,
                             ScriptRuntimeManager* scriptRuntimeManager,
                             ResolveConnection* resolveConnection,
                             QObject* parent = nullptr);

    // The key sequence bound to editSearchInEffects in the imported preset.
    // Set by ShortcutResolver once the preset has been parsed.
    void setSearchEffectsShortcut(const QString& sequence);
    QString searchEffectsShortcut() const { return m_searchEffectsShortcut; }

public slots:
    // Connected to WheelGeometry::commandTriggered.
    void executeCommand(const QVariantMap& command);

signals:
    void commandStarted(const QString& description);
    void commandFinished(const QString& description, bool success);
    void errorOccurred(const QString& message);

private:
    bool executeBuiltin(const QString& builtinId);
    bool executeCustom(const QString& customId);
    bool executeScript(const QString& scriptId);
    bool executeAddEffect(const QString& payload);
    void sendKeystrokes(const QString& keys);

    ConfigService* m_configService;
    ScriptRuntimeManager* m_scriptRuntimeManager;
    ResolveConnection* m_resolveConnection;
    QString m_searchEffectsShortcut;
};