#include "GlobalHotkey.h"
#include <QDebug>

#ifdef Q_OS_MACOS
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>

class MacHotkey : public GlobalHotkey
{
    Q_OBJECT

public:
    explicit MacHotkey(const QString& hotkeyString, QObject* parent = nullptr)
        : GlobalHotkey(hotkeyString, parent), m_eventTap(nullptr), m_hotkeyRef(0)
    {
    }

    ~MacHotkey() override { unregisterHotkey(); }

signals:
    void activated();
    void released();

protected:
    bool registerHotkey() override
    {
        // Parse hotkey string
        UInt32 keyCode = 0;
        UInt32 modifiers = 0;
        if (!parseHotkey(m_hotkeyString, keyCode, modifiers)) return false;

        m_virtualKey = keyCode;
        m_modifiers = modifiersToQt(modifiers);

        // Register global hotkey using Carbon (deprecated but still works)
        // For modern macOS, we'd use CGEventTap with accessibility permissions
        EventHotKeyID hotKeyID = {0, 0};
        hotKeyID.signature = 'MCWH';
        hotKeyID.id = 1;
        
        OSStatus status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &m_hotkeyRef);
        if (status != noErr) {
            qWarning() << "Failed to register hotkey:" << status;
            return false;
        }

        // Install event handler
        EventTypeSpec eventSpec = {kEventClassKeyboard, kEventHotKeyPressed};
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventHandler, 1, &eventSpec, this, nullptr);

        eventSpec.eventKind = kEventHotKeyReleased;
        InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventHandler, 1, &eventSpec, this, nullptr);

        m_active = true;
        return true;
    }

    void unregisterHotkey() override
    {
        if (m_hotkeyRef) {
            UnregisterEventHotKey(m_hotkeyRef);
            m_hotkeyRef = 0;
        }
        m_active = false;
    }

    void nativeEventFilter(void* message, long* result) override
    {
        // On macOS, we use event handlers instead of native event filter
        Q_UNUSED(message);
        Q_UNUSED(result);
    }

    void onConfigurationChanged(const QString& newHotkey)
    {
        if (m_hotkeyString != newHotkey) {
            m_hotkeyString = newHotkey;
            unregisterHotkey();
            registerHotkey();
        }
    }

private:
    static OSStatus hotkeyEventHandler(EventHandlerCallRef nextHandler, EventRef event, void* userData)
    {
        MacHotkey* self = static_cast<MacHotkey*>(userData);
        UInt32 eventKind = GetEventKind(event);
        
        if (eventKind == kEventHotKeyPressed) {
            if (!self->m_pressed) {
                self->m_pressed = true;
                emit self->activated();
            }
        } else if (eventKind == kEventHotKeyReleased) {
            if (self->m_pressed) {
                self->m_pressed = false;
                emit self->released();
            }
        }
        return noErr;
    }

    bool parseHotkey(const QString& hotkey, UInt32& keyCode, UInt32& modifiers)
    {
        modifiers = 0;
        QStringList parts = hotkey.split('+', Qt::SkipEmptyParts);
        
        for (const QString& part : parts) {
            QString key = part.toLower().trimmed();
            if (key == "ctrl") modifiers |= cmdKey; // macOS: Ctrl -> Command for typical shortcuts
            else if (key == "shift") modifiers |= shiftKey;
            else if (key == "alt") modifiers |= optionKey;
            else if (key == "cmd" || key == "meta" || key == "win") modifiers |= cmdKey;
            else {
                keyCode = keyStringToMacKeyCode(key);
            }
        }
        return keyCode != 0;
    }

    UInt32 keyStringToMacKeyCode(const QString& key)
    {
        // Virtual key codes for macOS
        if (key == "space") return 0x31;
        if (key == "enter") return 0x24;
        if (key == "tab") return 0x30;
        if (key == "esc") return 0x35;
        if (key == "up") return 0x7E;
        if (key == "down") return 0x7D;
        if (key == "left") return 0x7B;
        if (key == "right") return 0x7C;
        if (key.length() == 1) {
            QChar c = key.toUpper().at(0);
            // Letter keys
            if (c >= 'A' && c <= 'Z') return 0x00 + (c - 'A');
            // Number keys
            if (c >= '0' && c <= '9') return 0x1D + (c - '0');
        }
        return 0;
    }

    Qt::KeyboardModifiers modifiersToQt(UInt32 modifiers)
    {
        Qt::KeyboardModifiers qtMod = Qt::NoModifier;
        if (modifiers & cmdKey) qtMod |= Qt::MetaModifier;
        if (modifiers & shiftKey) qtMod |= Qt::ShiftModifier;
        if (modifiers & optionKey) qtMod |= Qt::AltModifier;
        if (modifiers & controlKey) qtMod |= Qt::ControlModifier;
        return qtMod;
    }

    EventHotKeyRef m_hotkeyRef = 0;
};
#endif