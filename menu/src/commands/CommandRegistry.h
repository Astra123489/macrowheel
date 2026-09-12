#pragma once

#include <QString>

// Static lookup tables for Macro Wheel-owned commands.
//
// Built-in commands are application-owned and read-only to users (spec 13.6).
// They are addressed by stable IDs such as "builtin.effect.gaussian_blur" so
// that library updates never break existing wheel assignments (spec 13.7).
//
// This header is the single place where built-in IDs map to their behaviour.
class CommandRegistry
{
public:
    // Key sequence to send for a non-effect built-in command.
    // Returns an empty string when the ID is unknown.
    static QString keySequenceFor(const QString& builtinId);

    // Add Effects commands all share one automation template; only the search
    // payload differs (spec 13.3 / 13.4).
    // Returns an empty string when the ID is not an Add Effect command.
    static QString effectPayloadFor(const QString& builtinId);

    // Display name for a built-in command, used by the wheel label when the
    // slice carries no explicit label.
    static QString displayNameFor(const QString& builtinId);
};