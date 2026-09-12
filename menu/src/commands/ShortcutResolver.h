#pragma once

#include <QHash>
#include <QString>
#include <QStringList>

// Parses a DaVinci Resolve shortcut preset (.txt) and resolves the key
// sequences Macro Wheel needs at runtime.
//
// Studio owns full conflict analysis (spec 12). The Menu only needs the
// shortcut bound to editSearchInEffects so the Add Effect automation can open
// the Search Effects field with whatever the user has bound (spec 13.3).
//
// Preset line format:
//     <commandId> := <key sequence> [| <alt sequence> ...]
// Lines with an empty right-hand side mean the command is unbound.
class ShortcutResolver
{
public:
    // Parses `contents`. Returns false when the text is empty.
    bool parse(const QString& contents);

    // Full list of key sequences bound to the given Resolve command ID.
    QStringList sequencesFor(const QString& commandId) const;

    // Shortcut for editSearchInEffects, or an empty string when unbound.
    // The first alternative in the preset is preferred.
    QString searchEffectsShortcut() const;

    // Every command ID that shares one of `sequences`.
    // Used by Studio for conflict detection and reused here for diagnostics.
    QStringList commandsUsing(const QString& sequence) const;

    static QString commandIdFor(const QString& line);

private:
    // commandId -> key sequences (already trimmed, alternatives flattened).
    QHash<QString, QStringList> m_bindings;
};