#include "SendKeys.h"

#include <QDebug>
#include <QHash>
#include <QStringList>

namespace {

#if defined(Q_OS_WIN)
#include <windows.h>

// Maps a key token from a hotkey string to a Win32 virtual-key code.
WORD tokenToVk(const QString& token)
{
    const QString k = token.toLower();
    if (k == "space")   return VK_SPACE;
    if (k == "enter")   return VK_RETURN;
    if (k == "tab")     return VK_TAB;
    if (k == "esc" || k == "escape") return VK_ESCAPE;
    if (k == "up")      return VK_UP;
    if (k == "down")    return VK_DOWN;
    if (k == "left")    return VK_LEFT;
    if (k == "right")   return VK_RIGHT;
    if (k == "backspace") return VK_BACK;
    if (k == "delete" || k == "del") return VK_DELETE;
    if (k == "home")    return VK_HOME;
    if (k == "end")     return VK_END;
    if (k == "pageup")  return VK_PRIOR;
    if (k == "pagedown")return VK_NEXT;
    if (k.startsWith('f')) {
        bool ok = false;
        const int n = k.mid(1).toInt(&ok);
        if (ok && n >= 1 && n <= 24) return static_cast<WORD>(VK_F1 + (n - 1));
    }
    if (k.length() == 1) {
        const SHORT vk = VkKeyScanA(k.at(0).toLatin1());
        if (vk != -1) return static_cast<WORD>(vk & 0xFF);
    }
    return 0;
}

WORD tokenToModifier(const QString& token)
{
    const QString k = token.toLower();
    if (k == "ctrl" || k == "control") return VK_CONTROL;
    if (k == "shift") return VK_SHIFT;
    if (k == "alt")   return VK_MENU;
    if (k == "win" || k == "meta" || k == "super") return VK_LWIN;
    return 0;
}

bool pressKey(WORD vk)
{
    INPUT in = {};
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    return SendInput(1, &in, sizeof(INPUT)) == 1;
}

bool releaseKey(WORD vk)
{
    INPUT in = {};
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    in.ki.dwFlags = KEYEVENTF_KEYUP;
    return SendInput(1, &in, sizeof(INPUT)) == 1;
}

bool sendKeySequence(const QString& sequence)
{
    const QStringList parts = sequence.split('+', Qt::SkipEmptyParts);
    if (parts.isEmpty()) return false;

    QVector<WORD> modifiers;
    for (int i = 0; i < parts.size() - 1; ++i) {
        const WORD m = tokenToModifier(parts.at(i));
        if (m) modifiers.append(m);
    }
    const WORD vk = tokenToVk(parts.last());
    if (!vk) return false;

    for (WORD m : modifiers) pressKey(m);
    pressKey(vk);
    releaseKey(vk);
    for (int i = modifiers.size() - 1; i >= 0; --i) releaseKey(modifiers.at(i));
    return true;
}

bool typeText(const QString& text)
{
    for (const QChar& ch : text) {
        INPUT in[2] = {};
        in[0].type = INPUT_KEYBOARD;
        in[0].ki.wScan = ch.unicode();
        in[0].ki.dwFlags = KEYEVENTF_UNICODE;
        in[1] = in[0];
        in[1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
        if (SendInput(2, in, sizeof(INPUT)) != 2) return false;
    }
    return true;
}

#elif defined(Q_OS_MACOS)

#include <ApplicationServices/ApplicationServices.h>

CGKeyCode tokenToKeyCode(const QString& token)
{
    const QString k = token.toLower();
    if (k == "space")  return 0x31;
    if (k == "enter")  return 0x24;
    if (k == "tab")    return 0x30;
    if (k == "esc" || k == "escape") return 0x35;
    if (k == "up")     return 0x7E;
    if (k == "down")   return 0x7D;
    if (k == "left")   return 0x7B;
    if (k == "right")  return 0x7C;
    if (k == "backspace") return 0x33;
    if (k == "delete" || k == "del") return 0x75;
    if (k.length() == 1) {
        const QChar c = k.at(0).toUpper();
        // Rough mapping; a full table can replace this later.
        static const CGKeyCode letters[26] = {
            0x00,0x0B,0x08,0x02,0x0E,0x03,0x05,0x04,0x22,0x26,0x28,0x25,0x2E,
            0x2D,0x1F,0x23,0x0C,0x0F,0x01,0x11,0x20,0x09,0x0D,0x07,0x10,0x06 };
        static const CGKeyCode digits[10] = {
            0x1D,0x12,0x13,0x14,0x15,0x17,0x16,0x1A,0x1C,0x19 };
        if (c >= 'A' && c <= 'Z') return letters[c.unicode() - 'A'];
        if (c >= '0' && c <= '9') return digits[c.unicode() - '0'];
    }
    return 0;
}

CGEventFlags tokenToFlag(const QString& token)
{
    const QString k = token.toLower();
    if (k == "ctrl" || k == "control") return kCGEventFlagMaskControl;
    if (k == "shift") return kCGEventFlagMaskShift;
    if (k == "alt" || k == "option") return kCGEventFlagMaskAlternate;
    if (k == "cmd" || k == "meta" || k == "super" || k == "win") return kCGEventFlagMaskCommand;
    return 0;
}

void postKey(CGKeyCode code, bool down, CGEventFlags flags)
{
    CGEventRef e = CGEventCreateKeyboardEvent(nullptr, code, down);
    if (!e) return;
    CGEventSetFlags(e, flags);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

bool sendKeySequence(const QString& sequence)
{
    const QStringList parts = sequence.split('+', Qt::SkipEmptyParts);
    if (parts.isEmpty()) return false;

    CGEventFlags flags = 0;
    for (int i = 0; i < parts.size() - 1; ++i) flags |= tokenToFlag(parts.at(i));
    const CGKeyCode code = tokenToKeyCode(parts.last());
    if (!code) return false;

    postKey(code, true, flags);
    postKey(code, false, flags);
    return true;
}

bool typeText(const QString& text)
{
    for (const QChar& ch : text) {
        // Best-effort; Unicode text injection on macOS needs the input method.
        // Not implemented in v1 - the payload for Add Effects is normally ASCII.
        Q_UNUSED(ch);
    }
    return false;
}

#else // Linux / X11

#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>

KeySym tokenToKeysym(const QString& token)
{
    const QString k = token.toLower();
    if (k == "space")  return XK_space;
    if (k == "enter")  return XK_Return;
    if (k == "tab")    return XK_Tab;
    if (k == "esc" || k == "escape") return XK_Escape;
    if (k == "up")     return XK_Up;
    if (k == "down")   return XK_Down;
    if (k == "left")   return XK_Left;
    if (k == "right")  return XK_Right;
    if (k == "backspace") return XK_BackSpace;
    if (k == "delete" || k == "del") return XK_Delete;
    if (k.length() == 1) {
        const QChar c = k.at(0).toUpper();
        if (c >= 'A' && c <= 'Z') return XK_A + (c.unicode() - 'A');
        if (c >= '0' && c <= '9') return XK_0 + (c.unicode() - '0');
    }
    return 0;
}

KeySym tokenToModKeysym(const QString& token)
{
    const QString k = token.toLower();
    if (k == "ctrl" || k == "control") return XK_Control_L;
    if (k == "shift") return XK_Shift_L;
    if (k == "alt")   return XK_Alt_L;
    if (k == "meta" || k == "super" || k == "win") return XK_Super_L;
    return 0;
}

bool sendKeySequence(const QString& sequence)
{
    Display* d = XOpenDisplay(nullptr);
    if (!d) return false;

    const QStringList parts = sequence.split('+', Qt::SkipEmptyParts);
    if (parts.isEmpty()) { XCloseDisplay(d); return false; }

    QVector<KeySym> mods;
    for (int i = 0; i < parts.size() - 1; ++i) {
        const KeySym m = tokenToModKeysym(parts.at(i));
        if (m) mods.append(m);
    }
    const KeySym ks = tokenToKeysym(parts.last());
    if (!ks) { XCloseDisplay(d); return false; }

    for (KeySym m : mods) XTestFakeKeyEvent(d, XKeysymToKeycode(d, m), True, 0);
    const KeyCode kc = XKeysymToKeycode(d, ks);
    XTestFakeKeyEvent(d, kc, True, 0);
    XTestFakeKeyEvent(d, kc, False, 0);
    for (int i = mods.size() - 1; i >= 0; --i)
        XTestFakeKeyEvent(d, XKeysymToKeycode(d, mods.at(i)), False, 0);

    XFlush(d);
    XCloseDisplay(d);
    return true;
}

bool typeText(const QString& text)
{
    // ASCII-only best-effort via XTest.
    Display* d = XOpenDisplay(nullptr);
    if (!d) return false;
    for (const QChar& ch : text) {
        const QChar c = ch.toUpper();
        KeySym ks = 0;
        if (c >= 'A' && c <= 'Z') ks = XK_A + (c.unicode() - 'A');
        else if (c >= '0' && c <= '9') ks = XK_0 + (c.unicode() - '0');
        else if (ch == ' ') ks = XK_space;
        if (!ks) continue;
        const KeyCode kc = XKeysymToKeycode(d, ks);
        XTestFakeKeyEvent(d, kc, True, 0);
        XTestFakeKeyEvent(d, kc, False, 0);
    }
    XFlush(d);
    XCloseDisplay(d);
    return true;
}

#endif

} // namespace

bool SendKeys::send(const QString& sequence)
{
    if (sequence.isEmpty()) return false;
    return sendKeySequence(sequence);
}

bool SendKeys::sendText(const QString& text)
{
    if (text.isEmpty()) return false;
    return typeText(text);
}

#ifdef Q_OS_WIN
#include <windows.h>

bool SendKeys::sendWindows(const QString& keys)
{
    // Parse keys like "Ctrl+Shift+T" or "B" or "Down"
    // This is a simplified implementation
    QStringList parts = keys.split('+', Qt::SkipEmptyParts);
    
    QVector<INPUT> inputs;
    
    // Press modifiers first
    for (const QString& part : parts) {
        QString key = part.toLower();
        WORD vk = 0;
        
        if (key == "ctrl") vk = VK_CONTROL;
        else if (key == "shift") vk = VK_SHIFT;
        else if (key == "alt") vk = VK_MENU;
        else if (key == "win") vk = VK_LWIN;
        else continue;
        
        INPUT input = {0};
        input.type = INPUT_KEYBOARD;
        input.ki.wVk = vk;
        inputs.append(input);
    }
    
    // Press main key
    QString mainKey = parts.last().toLower();
    WORD vk = 0;
    
    if (mainKey == "enter") vk = VK_RETURN;
    else if (mainKey == "tab") vk = VK_TAB;
    else if (mainKey == "space") vk = VK_SPACE;
    else if (mainKey == "up") vk = VK_UP;
    else if (mainKey == "down") vk = VK_DOWN;
    else if (mainKey == "left") vk = VK_LEFT;
    else if (mainKey == "right") vk = VK_RIGHT;
    else if (mainKey == "esc") vk = VK_ESCAPE;
    else if (mainKey.length() == 1) vk = VkKeyScanW(mainKey.at(0).unicode());
    else return false;
    
    INPUT input = {0};
    input.type = INPUT_KEYBOARD;
    input.ki.wVk = vk;
    inputs.append(input);
    
    // Release main key
    INPUT release = input;
    release.ki.dwFlags = KEYEVENTF_KEYUP;
    inputs.append(release);
    
    // Release modifiers in reverse order
    for (int i = parts.size() - 2; i >= 0; --i) {
        QString key = parts[i].toLower();
        WORD mvk = 0;
        if (key == "ctrl") mvk = VK_CONTROL;
        else if (key == "shift") mvk = VK_SHIFT;
        else if (key == "alt") mvk = VK_MENU;
        else if (key == "win") mvk = VK_LWIN;
        else continue;
        
        INPUT minput = {0};
        minput.type = INPUT_KEYBOARD;
        minput.ki.wVk = mvk;
        minput.ki.dwFlags = KEYEVENTF_KEYUP;
        inputs.append(minput);
    }
    
    return SendInput(inputs.size(), inputs.data(), sizeof(INPUT)) == inputs.size();
}
#elif defined(Q_OS_MACOS)
// macOS implementation would use CGEventPost
bool SendKeys::sendMacOS(const QString& keys)
{
    qWarning() << "macOS SendKeys not yet implemented";
    return false;
}
#else
// Linux implementation would use uinput or xdotool
bool SendKeys::sendLinux(const QString& keys)
{
    qWarning() << "Linux SendKeys not yet implemented";
    return false;
}
#endif