#include "GlobalHotkey.h"
#include <QCoreApplication>
#include <QCursor>
#include <QDebug>
#include <QHash>
#include <QPointF>
#include <QStringList>

// ---------------------------------------------------------------------------
// Platform state
// ---------------------------------------------------------------------------

#if defined(Q_OS_WIN)
#  include <windows.h>

struct GlobalHotkey::Impl {
    ATOM id = 0;
};
static const int kHotkeyIdBase = 0xB000;

#elif defined(Q_OS_MACOS)
#  include <Carbon/Carbon.h>
#  include <HIToolbox/Events.h>

struct GlobalHotkey::Impl {
    EventHotKeyRef ref = nullptr;
    EventHandlerRef handler = nullptr;
};
static const EventHotKeyID kMacHotkeyId = { 'MCWH', 1 };

static OSStatus macHotkeyHandler(EventHandlerCallRef, EventRef event, void* userData)
{
    auto* self = static_cast<GlobalHotkey*>(userData);
    if (!self) return noErr;

    const bool pressed = (GetEventKind(event) == kEventHotKeyPressed);
    QMetaObject::invokeMethod(self, [self, pressed]() {
        self->handlePlatformHotkeyEvent(pressed);
    }, Qt::QueuedConnection);
    return noErr;
}

#elif defined(Q_OS_LINUX)
#  include <X11/Xlib.h>
#  include <X11/keysym.h>
#  include <QThread>
#  include <atomic>
#  include <chrono>
#  include <thread>

struct GlobalHotkey::Impl {
    Display* display = nullptr;
    Window root = 0;
    KeyCode keyCode = 0;
    unsigned int modifiers = 0;
    std::atomic<bool> running{false};
    QThread* thread = nullptr;
};

#else
struct GlobalHotkey::Impl {};
#endif

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Maps a key name ("space", "f9", "a", "3") to a platform key code.
static int keyStringToKeyCode(const QString& key);

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

GlobalHotkey::GlobalHotkey(const QString& hotkeyString, QObject* parent)
    : QObject(parent)
    , m_impl(new Impl)
    , m_hotkeyString(hotkeyString)
{
    QCoreApplication::instance()->installNativeEventFilter(this);
}

GlobalHotkey::~GlobalHotkey()
{
    stop();
    QCoreApplication::instance()->removeNativeEventFilter(this);
    delete m_impl;
    m_impl = nullptr;
}

void GlobalHotkey::setHotkey(const QString& hotkeyString)
{
    if (hotkeyString.isEmpty() || hotkeyString == m_hotkeyString)
        return;

    const bool wasActive = m_active;
    if (wasActive)
        stop();

    m_hotkeyString = hotkeyString;

    if (wasActive)
        start();
}

void GlobalHotkey::onConfigurationChanged(const InteractionSettings& settings)
{
    setHotkey(settings.wheelActivationHotkey);
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

bool GlobalHotkey::parseHotkey(int& virtualKey, unsigned int& modifiers) const
{
    modifiers = 0;
    virtualKey = 0;

    const QStringList parts = m_hotkeyString.split('+', Qt::SkipEmptyParts);
    if (parts.isEmpty()) return false;

    for (const QString& raw : parts) {
        const QString key = raw.trimmed().toLower();

        if (key == "ctrl" || key == "control") {
#if defined(Q_OS_MACOS)
            modifiers |= controlKey;
#else
            modifiers |= 0x0002; // MOD_CONTROL
#endif
        } else if (key == "shift") {
#if defined(Q_OS_MACOS)
            modifiers |= shiftKey;
#else
            modifiers |= 0x0004; // MOD_SHIFT
#endif
        } else if (key == "alt" || key == "option") {
#if defined(Q_OS_MACOS)
            modifiers |= optionKey;
#else
            modifiers |= 0x0001; // MOD_ALT
#endif
        } else if (key == "cmd" || key == "meta" || key == "super" || key == "win") {
#if defined(Q_OS_MACOS)
            modifiers |= cmdKey;
#else
            modifiers |= 0x0008; // MOD_WIN
#endif
        } else {
            virtualKey = keyStringToKeyCode(key);
        }
    }
    return virtualKey != 0;
}

// ---------------------------------------------------------------------------
// Key name -> platform key code
// ---------------------------------------------------------------------------

static int keyStringToKeyCode(const QString& key)
{
#if defined(Q_OS_WIN)
    if (key == "space")  return VK_SPACE;
    if (key == "enter")  return VK_RETURN;
    if (key == "tab")    return VK_TAB;
    if (key == "esc" || key == "escape") return VK_ESCAPE;
    if (key == "up")     return VK_UP;
    if (key == "down")   return VK_DOWN;
    if (key == "left")   return VK_LEFT;
    if (key == "right")  return VK_RIGHT;
    if (key.startsWith('f')) {
        bool ok = false;
        const int n = key.mid(1).toInt(&ok);
        if (ok && n >= 1 && n <= 24) return VK_F1 + (n - 1);
    }
    if (key.length() == 1) {
        const SHORT vk = VkKeyScanA(key.at(0).toLatin1());
        if (vk != -1) return vk & 0xFF;
    }
    return 0;
#elif defined(Q_OS_MACOS)
    if (key == "space")  return kVK_ANSI_Space;
    if (key == "enter")  return kVK_Return;
    if (key == "tab")    return kVK_Tab;
    if (key == "esc" || key == "escape") return kVK_Escape;
    if (key == "up")     return kVK_UpArrow;
    if (key == "down")   return kVK_DownArrow;
    if (key == "left")   return kVK_LeftArrow;
    if (key == "right")  return kVK_RightArrow;
    static const int letterKeys[26] = {
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
        kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
        kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z };
    static const int digitKeys[10] = {
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9 };
    if (key.length() == 1) {
        const QChar c = key.at(0).toUpper();
        if (c >= 'A' && c <= 'Z') return letterKeys[c.unicode() - 'A'];
        if (c >= '0' && c <= '9') return digitKeys[c.unicode() - '0'];
    }
    return 0;
#elif defined(Q_OS_LINUX)
    KeySym sym = 0;
    if (key == "space")  sym = XK_space;
    else if (key == "enter") sym = XK_Return;
    else if (key == "tab")   sym = XK_Tab;
    else if (key == "esc" || key == "escape") sym = XK_Escape;
    else if (key == "up")    sym = XK_Up;
    else if (key == "down")  sym = XK_Down;
    else if (key == "left")  sym = XK_Left;
    else if (key == "right") sym = XK_Right;
    else if (key.length() == 1) {
        const QChar c = key.at(0).toUpper();
        if (c >= 'A' && c <= 'Z') sym = XK_A + (c.unicode() - 'A');
        else if (c >= '0' && c <= '9') sym = XK_0 + (c.unicode() - '0');
    }
    if (sym == 0) return 0;
    return static_cast<int>(sym); // keysym, converted to keycode in start()
#else
    Q_UNUSED(key);
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// State changes reported by the platform hooks
// ---------------------------------------------------------------------------

QPointF GlobalHotkey::cursorPosition() const
{
    return QCursor::pos();
}

void GlobalHotkey::handlePlatformHotkeyEvent(bool pressed)
{
    if (pressed && !m_pressed) {
        m_pressed = true;
        emit activated();
    } else if (!pressed && m_pressed) {
        m_pressed = false;
        emit released();
    }
}

// ---------------------------------------------------------------------------
// start / stop
// ---------------------------------------------------------------------------

void GlobalHotkey::start()
{
    if (m_active) return;

    int virtualKey = 0;
    unsigned int modifiers = 0;
    if (!parseHotkey(virtualKey, modifiers)) {
        emit errorOccurred(QString("Invalid hotkey: %1").arg(m_hotkeyString));
        return;
    }

#if defined(Q_OS_WIN)
    m_impl->id = static_cast<ATOM>(kHotkeyIdBase + (qHash(m_hotkeyString) % 0x1000));
    if (!RegisterHotKey(nullptr, m_impl->id, modifiers, static_cast<UINT>(virtualKey))) {
        emit errorOccurred(QString("Failed to register global hotkey: %1").arg(m_hotkeyString));
        m_impl->id = 0;
        return;
    }
    m_active = true;

#elif defined(Q_OS_MACOS)
    if (RegisterEventHotKey(static_cast<UInt32>(virtualKey), modifiers, kMacHotkeyId,
                            GetEventDispatcherTarget(), 0, &m_impl->ref) != noErr) {
        emit errorOccurred(QString("Failed to register global hotkey: %1").arg(m_hotkeyString));
        m_impl->ref = nullptr;
        return;
    }
    const EventTypeSpec specs[2] = {
        { kEventClassKeyboard, kEventHotKeyPressed },
        { kEventClassKeyboard, kEventHotKeyReleased }
    };
    InstallEventHandler(GetEventDispatcherTarget(), macHotkeyHandler, 2, specs, this,
                        &m_impl->handler);
    m_active = true;

#elif defined(Q_OS_LINUX)
    m_impl->display = XOpenDisplay(nullptr);
    if (!m_impl->display) {
        emit errorOccurred("Failed to open X display (Wayland is not supported)");
        return;
    }
    m_impl->root = DefaultRootWindow(m_impl->display);
    m_impl->keyCode = XKeysymToKeycode(m_impl->display, static_cast<KeySym>(virtualKey));
    m_impl->modifiers = modifiers;
    if (m_impl->keyCode == 0) {
        XCloseDisplay(m_impl->display);
        m_impl->display = nullptr;
        emit errorOccurred(QString("Unknown key in hotkey: %1").arg(m_hotkeyString));
        return;
    }

    const unsigned int lockMasks[4] = { 0, LockMask, Mod2Mask, LockMask | Mod2Mask };
    bool grabbed = false;
    for (int i = 0; i < 4; ++i) {
        if (XGrabKey(m_impl->display, m_impl->keyCode, modifiers | lockMasks[i],
                     m_impl->root, True, GrabModeAsync, GrabModeAsync) == GrabSuccess) {
            grabbed = true;
        }
    }
    if (!grabbed) {
        XCloseDisplay(m_impl->display);
        m_impl->display = nullptr;
        emit errorOccurred(QString("Global hotkey already in use: %1").arg(m_hotkeyString));
        return;
    }

    m_impl->running = true;
    auto* impl = m_impl;
    auto* self = this;
    impl->thread = QThread::create([impl, self]() {
        XEvent event;
        while (impl->running.load()) {
            while (impl->display && XPending(impl->display) > 0) {
                XNextEvent(impl->display, &event);
                if (event.type != KeyPress && event.type != KeyRelease) continue;
                const XKeyEvent& ke = event.xkey;
                if (ke.keycode != impl->keyCode) continue;
                const unsigned int state = ke.state & ~(LockMask | Mod2Mask);
                if (state != (impl->modifiers & ~(LockMask | Mod2Mask))) continue;
                self->handlePlatformHotkeyEvent(event.type == KeyPress);
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    });
    impl->thread->start();
    m_active = true;

#else
    emit errorOccurred("Global hotkeys are not supported on this platform");
#endif
}

void GlobalHotkey::stop()
{
    if (!m_active) return;

#if defined(Q_OS_WIN)
    if (m_impl->id) {
        UnregisterHotKey(nullptr, m_impl->id);
        m_impl->id = 0;
    }

#elif defined(Q_OS_MACOS)
    if (m_impl->handler) {
        RemoveEventHandler(m_impl->handler);
        m_impl->handler = nullptr;
    }
    if (m_impl->ref) {
        UnregisterEventHotKey(m_impl->ref);
        m_impl->ref = nullptr;
    }

#elif defined(Q_OS_LINUX)
    m_impl->running = false;
    if (m_impl->thread) {
        m_impl->thread->wait(1000);
        delete m_impl->thread;
        m_impl->thread = nullptr;
    }
    if (m_impl->display) {
        XUngrabKey(m_impl->display, m_impl->keyCode, AnyModifier, m_impl->root);
        XCloseDisplay(m_impl->display);
        m_impl->display = nullptr;
    }
#endif

    m_active = false;
    m_pressed = false;
}

// ---------------------------------------------------------------------------
// Native event filter (Windows WM_HOTKEY)
// ---------------------------------------------------------------------------

bool GlobalHotkey::nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result)
{
    Q_UNUSED(eventType);

#if defined(Q_OS_WIN)
    MSG* msg = static_cast<MSG*>(message);
    if (msg && msg->message == WM_HOTKEY && m_active
        && msg->wParam == static_cast<WPARAM>(m_impl->id)) {
        const bool released = (msg->lParam & 0x40000000) != 0; // bit 30 == key up
        handlePlatformHotkeyEvent(!released);
        if (result) *result = 0;
        return true;
    }
#else
    Q_UNUSED(message);
    Q_UNUSED(result);
#endif

    return false;
}