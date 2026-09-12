#include "GlobalHotkey.h"
#include <QDebug>

#ifdef Q_OS_WIN
#include <windows.h>

class WindowsHotkey : public GlobalHotkey
{
    Q_OBJECT

public:
    explicit WindowsHotkey(const QString& hotkeyString, QObject* parent = nullptr)
        : GlobalHotkey(hotkeyString, parent), m_hotkeyId(0)
    {
    }

    ~WindowsHotkey() override { unregisterHotkey(); }

signals:
    void activated();
    void released();

protected:
    bool registerHotkey() override
    {
        // Parse hotkey string (e.g., "Ctrl+Shift+Space")
        UINT modifiers = 0;
        int vk = parseHotkey(m_hotkeyString, modifiers);
        if (vk == 0) return false;

        m_virtualKey = vk;
        m_modifiers = modifiersToQt(modifiers);

        // Generate unique ID for this hotkey
        m_hotkeyId = GlobalAddAtom("MacroWheelHotkey");
        if (m_hotkeyId == 0) return false;

        // Register the hotkey
        if (!RegisterHotKey(nullptr, m_hotkeyId, modifiers, vk)) {
            GlobalDeleteAtom(m_hotkeyId);
            m_hotkeyId = 0;
            return false;
        }

        m_active = true;
        return true;
    }

    void unregisterHotkey() override
    {
        if (m_hotkeyId != 0) {
            UnregisterHotKey(nullptr, m_hotkeyId);
            GlobalDeleteAtom(m_hotkeyId);
            m_hotkeyId = 0;
        }
        m_active = false;
    }

    void nativeEventFilter(void* message, long* result) override
    {
        MSG* msg = static_cast<MSG*>(message);
        if (msg->message == WM_HOTKEY && msg->wParam == m_hotkeyId) {
            if (msg->lParam & 0x40000000) { // Key up (release)
                if (m_pressed) {
                    m_pressed = false;
                    emit released();
                }
            } else { // Key down (press)
                if (!m_pressed) {
                    m_pressed = true;
                    emit activated();
                }
            }
            *result = 0;
        }
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
    int parseHotkey(const QString& hotkey, UINT& modifiers)
    {
        modifiers = 0;
        QStringList parts = hotkey.split('+', Qt::SkipEmptyParts);
        int vk = 0;

        for (const QString& part : parts) {
            QString key = part.toLower().trimmed();
            if (key == "ctrl") modifiers |= MOD_CONTROL;
            else if (key == "shift") modifiers |= MOD_SHIFT;
            else if (key == "alt") modifiers |= MOD_ALT;
            else if (key == "win") modifiers |= MOD_WIN;
            else {
                // Main key
                vk = keyStringToVk(key);
            }
        }
        return vk;
    }

    int keyStringToVk(const QString& key)
    {
        if (key == "space") return VK_SPACE;
        if (key == "enter") return VK_RETURN;
        if (key == "tab") return VK_TAB;
        if (key == "esc") return VK_ESCAPE;
        if (key == "up") return VK_UP;
        if (key == "down") return VK_DOWN;
        if (key == "left") return VK_LEFT;
        if (key == "right") return VK_RIGHT;
        if (key.length() == 1) return VkKeyScan(key.toLatin1());
        return 0;
    }

    Qt::KeyboardModifiers modifiersToQt(UINT modifiers)
    {
        Qt::KeyboardModifiers qtMod = Qt::NoModifier;
        if (modifiers & MOD_CONTROL) qtMod |= Qt::ControlModifier;
        if (modifiers & MOD_SHIFT) qtMod |= Qt::ShiftModifier;
        if (modifiers & MOD_ALT) qtMod |= Qt::AltModifier;
        if (modifiers & MOD_WIN) qtMod |= Qt::MetaModifier;
        return qtMod;
    }

    ATOM m_hotkeyId = 0;
};
#endif