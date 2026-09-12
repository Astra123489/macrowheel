#pragma once

#include <QString>

// Native keystroke injection.
//
// Used for built-in commands and for the fixed Add Effect automation. Keys are
// never routed through Python: injection is done with the OS input API so the
// Menu does not need the Command Runtime for ordinary commands.
class SendKeys
{
public:
    // Sends a key sequence such as "Ctrl+Shift+T", "B", "Down", "Enter".
    // Modifiers are pressed before and released after the main key.
    static bool send(const QString& sequence);

    // Types text into the focused window. Used for Add Effect search payloads,
    // where the characters must arrive as text rather than as key names.
    static bool sendText(const QString& text);

private:
#ifdef Q_OS_WIN
    static bool sendWindows(const QString& keys);
#endif
};