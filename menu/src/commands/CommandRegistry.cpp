#include "CommandRegistry.h"

#include <QHash>

namespace {

struct BuiltinEntry {
    const char* keySequence;   // empty when this is an effect command
    const char* effectPayload; // empty when this is a key-sequence command
    const char* displayName;
};

// Add Effects: payload is what gets typed into the Search Effects field.
// The surrounding automation (search -> type -> Down -> Enter) is fixed and
// lives in CommandExecutor::executeAddEffect.
const QHash<QString, BuiltinEntry>& table()
{
    static const QHash<QString, BuiltinEntry> t = {
        // --- Add Effects (spec 13.4, starter set) ---
        { QStringLiteral("builtin.effect.gaussian_blur"),
          { "", "Gaussian Blur OFX", "Gaussian Blur" } },
        { QStringLiteral("builtin.effect.sharpen"),
          { "", "Sharpen OFX", "Sharpen" } },
        { QStringLiteral("builtin.effect.glow"),
          { "", "Glow OFX", "Glow" } },
        { QStringLiteral("builtin.effect.directional_blur"),
          { "", "Directional Blur OFX", "Directional Blur" } },
        { QStringLiteral("builtin.effect.film_grain"),
          { "", "Film Grain OFX", "Film Grain" } },
        { QStringLiteral("builtin.effect.chromatic_aberration"),
          { "", "Chromatic Aberration OFX", "Chromatic Aberration" } },
        { QStringLiteral("builtin.effect.vignette"),
          { "", "Vignette OFX", "Vignette" } },
        { QStringLiteral("builtin.effect.letterbox"),
          { "", "Letterbox OFX", "Letterbox" } },
        { QStringLiteral("builtin.effect.motion_blur"),
          { "", "Motion Blur OFX", "Motion Blur" } },
        { QStringLiteral("builtin.effect.lens_flare"),
          { "", "Lens Flare OFX", "Lens Flare" } },

        // --- Edit page commands ---
        { QStringLiteral("builtin.edit.blade"),          { "B",              "", "Blade" } },
        { QStringLiteral("builtin.edit.ripple_delete"),  { "Shift+Backspace","", "Ripple Delete" } },
        { QStringLiteral("builtin.edit.add_transition"), { "Ctrl+T",         "", "Add Transition" } },

        // --- Color page commands ---
        { QStringLiteral("builtin.color.add_node"),      { "Alt+S",          "", "Add Serial Node" } },

        // --- Fusion page commands ---
        { QStringLiteral("builtin.fusion.add_tool"),     { "Shift+Space",    "", "Add Tool" } },
    };
    return t;
}

} // namespace

QString CommandRegistry::keySequenceFor(const QString& builtinId)
{
    const auto it = table().constFind(builtinId);
    if (it == table().constEnd())
        return QString();
    return QString::fromLatin1(it->keySequence);
}

QString CommandRegistry::effectPayloadFor(const QString& builtinId)
{
    const auto it = table().constFind(builtinId);
    if (it == table().constEnd())
        return QString();
    return QString::fromLatin1(it->effectPayload);
}

QString CommandRegistry::displayNameFor(const QString& builtinId)
{
    const auto it = table().constFind(builtinId);
    if (it == table().constEnd())
        return builtinId;
    return QString::fromLatin1(it->displayName);
}