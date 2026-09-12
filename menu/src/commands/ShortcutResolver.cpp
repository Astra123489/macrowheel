#include "ShortcutResolver.h"

#include <QRegularExpression>

namespace {
// The preset binds Resolve's effect search to this identifier. It is not
// hardcoded to Shift+Space; the value always comes from the imported preset.
const char* const kSearchEffectsCommandId = "editSearchInEffects";
}

bool ShortcutResolver::parse(const QString& contents)
{
    m_bindings.clear();
    if (contents.isEmpty())
        return false;

    const QStringList lines = contents.split('\n');
    for (const QString& rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;

        const int sep = line.indexOf(QStringLiteral(":="));
        if (sep < 0)
            continue;

        const QString commandId = line.left(sep).trimmed();
        const QString rhs = line.mid(sep + 2).trimmed();
        if (commandId.isEmpty() || rhs.isEmpty())
            continue;

        QStringList sequences;
        const QStringList alternatives = rhs.split('|');
        for (const QString& alt : alternatives) {
            const QString s = alt.trimmed();
            if (!s.isEmpty())
                sequences.append(s);
        }
        if (sequences.isEmpty())
            continue;

        // A later line overrides an earlier one for the same command.
        m_bindings.insert(commandId, sequences);
    }

    return !m_bindings.isEmpty();
}

QStringList ShortcutResolver::sequencesFor(const QString& commandId) const
{
    return m_bindings.value(commandId);
}

QString ShortcutResolver::searchEffectsShortcut() const
{
    const QStringList s = sequencesFor(QString::fromLatin1(kSearchEffectsCommandId));
    return s.isEmpty() ? QString() : s.first();
}

QStringList ShortcutResolver::commandsUsing(const QString& sequence) const
{
    QStringList hits;
    for (auto it = m_bindings.constBegin(); it != m_bindings.constEnd(); ++it) {
        if (it.value().contains(sequence))
            hits.append(it.key());
    }
    hits.sort();
    return hits;
}

QString ShortcutResolver::commandIdFor(const QString& line)
{
    const int sep = line.indexOf(QStringLiteral(":="));
    return sep < 0 ? QString() : line.left(sep).trimmed();
}