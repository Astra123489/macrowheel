#include "GlobalHotkey.h"
#include <QDebug>

#ifdef Q_OS_LINUX
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/record.h>
#include <pthread.h>

class LinuxHotkey : public GlobalHotkey
{
    Q_OBJECT

public:
    explicit LinuxHotkey(const QString& hotkeyString, QObject* parent = nullptr)
        : GlobalHotkey(hotkeyString, parent), m_display(nullptr), m_recordContext(0), m_thread(0)
    {
    }

    ~LinuxHotkey() override { unregisterHotkey(); }

signals:
    void activated();
    void released();

protected:
    bool registerHotkey() override
    {
        m_display = XOpenDisplay(nullptr);
        if (!m_display) {
            qWarning() << "Failed to open X display";
            return false;
        }

        // Parse hotkey
        unsigned int modifiers = 0;
        KeyCode keyCode = parseHotkey(m_hotkeyString, modifiers);
        if (keyCode == 0) {
            XCloseDisplay(m_display);
            m_display = nullptr;
            return false;
        }

        m_virtualKey = keyCode;
        m_modifiers = modifiersToQt(modifiers);

        // Grab the key combination globally
        Window root = DefaultRootWindow(m_display);
        if (XGrabKey(m_display, keyCode, modifiers, root, True, GrabModeAsync, GrabModeAsync) != GrabSuccess) {
            qWarning() << "Failed to grab key";
            XCloseDisplay(m_display);
            m_display = nullptr;
            return false;
        }

        // Also grab with numlock/capslock variations
        unsigned int modMasks[] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};
        for (unsigned int mask : modMasks) {
            XGrabKey(m_display, keyCode, modifiers | mask, root, True, GrabModeAsync, GrabModeAsync);
        }

        // Start event listening thread
        m_running = true;
        pthread_create(&m_thread, nullptr, eventThread, this);

        m_active = true;
        return true;
    }

    void unregisterHotkey() override
    {
        m_running = false;
        if (m_thread) {
            pthread_join(m_thread, nullptr);
            m_thread = 0;
        }

        if (m_display) {
            Window root = DefaultRootWindow(m_display);
            XUngrabKey(m_display, m_virtualKey, AnyModifier, root);
            XCloseDisplay(m_display);
            m_display = nullptr;
        }

        if (m_recordContext) {
            XRecordFreeContext(m_display, m_recordContext);
            m_recordContext = 0;
        }

        m_active = false;
    }

    void nativeEventFilter(void* message, long* result) override
    {
        // On Linux with X11, we use a separate thread for event listening
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
    static void* eventThread(void* arg)
    {
        LinuxHotkey* self = static_cast<LinuxHotkey*>(arg);
        self->runEventLoop();
        return nullptr;
    }

    void runEventLoop()
    {
        XEvent event;
        while (m_running && m_display) {
            XNextEvent(m_display, &event);
            if (event.type == KeyPress || event.type == KeyRelease) {
                XKeyEvent* keyEvent = &event.xkey;
                if (keyEvent->keycode == m_virtualKey) {
                    bool isPress = (event.type == KeyPress);
                    unsigned int state = keyEvent->state;
                    
                    // Check if modifiers match (ignore lock modifiers)
                    unsigned int cleanState = state & ~(LockMask | Mod2Mask);
                    unsigned int cleanModifiers = m_modifiers & ~(LockMask | Mod2Mask);
                    
                    if (cleanState == cleanModifiers) {
                        if (isPress && !m_pressed) {
                            m_pressed = true;
                            emit activated();
                        } else if (!isPress && m_pressed) {
                            m_pressed = false;
                            emit released();
                        }
                    }
                }
            }
        }
    }

    KeyCode parseHotkey(const QString& hotkey, unsigned int& modifiers)
    {
        modifiers = 0;
        QStringList parts = hotkey.split('+', Qt::SkipEmptyParts);
        KeyCode keyCode = 0;

        for (const QString& part : parts) {
            QString key = part.toLower().trimmed();
            if (key == "ctrl") modifiers |= ControlMask;
            else if (key == "shift") modifiers |= ShiftMask;
            else if (key == "alt") modifiers |= Mod1Mask; // Usually Alt
            else if (key == "meta" || key == "win" || key == "super") modifiers |= Mod4Mask;
            else {
                keyCode = keyStringToXKeyCode(key);
            }
        }
        return keyCode;
    }

    KeyCode keyStringToXKeyCode(const QString& key)
    {
        Display* display = m_display;
        KeySym keysym = 0;
        
        if (key == "space") keysym = XK_space;
        else if (key == "enter") keysym = XK_Return;
        else if (key == "tab") keysym = XK_Tab;
        else if (key == "esc") keysym = XK_Escape;
        else if (key == "up") keysym = XK_Up;
        else if (key == "down") keysym = XK_Down;
        else if (key == "left") keysym = XK_Left;
        else if (key == "right") keysym = XK_Right;
        else if (key.length() == 1) {
            QChar c = key.toUpper().at(0);
            if (c >= 'A' && c <= 'Z') keysym = XK_A + (c - 'A');
            else if (c >= '0' && c <= '9') keysym = XK_0 + (c - '0');
        }
        
        if (keysym == 0) return 0;
        return XKeysymToKeycode(display, keysym);
    }

    Qt::KeyboardModifiers modifiersToQt(unsigned int modifiers)
    {
        Qt::KeyboardModifiers qtMod = Qt::NoModifier;
        if (modifiers & ControlMask) qtMod |= Qt::ControlModifier;
        if (modifiers & ShiftMask) qtMod |= Qt::ShiftModifier;
        if (modifiers & Mod1Mask) qtMod |= Qt::AltModifier;
        if (modifiers & Mod4Mask) qtMod |= Qt::MetaModifier;
        return qtMod;
    }

    Display* m_display = nullptr;
    XRecordContext m_recordContext = 0;
    pthread_t m_thread = 0;
    bool m_running = false;
};
#endif