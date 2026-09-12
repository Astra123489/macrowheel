#pragma once

#include <QObject>
#include <QAbstractNativeEventFilter>
#include <QString>

#include "config/generated/ConfigTypes.h"

// Cross-platform press-and-hold global hotkey.
//
// Windows : RegisterHotKey + WM_HOTKEY via QAbstractNativeEventFilter
// macOS   : Carbon RegisterEventHotKey (press + release callbacks)
// Linux   : X11 XGrabKey on a dedicated thread reading XNextEvent
//
// Wayland has no standard global-hotkey portal; on Wayland start() will fail
// and emit errorOccurred(). Documented limitation.
class GlobalHotkey : public QObject, public QAbstractNativeEventFilter
{
    Q_OBJECT

public:
    explicit GlobalHotkey(const QString& hotkeyString, QObject* parent = nullptr);
    ~GlobalHotkey() override;

    void start();
    void stop();
    bool isActive() const { return m_active; }

    // Accepts "Ctrl+Shift+Space", "Alt+M", "F9", ...
    // Unregister/re-register if currently running.
    void setHotkey(const QString& hotkeyString);
    QString hotkey() const { return m_hotkeyString; }

    // Re-read the activation hotkey from the configuration after a reload
    // (Studio Settings writes it into configuration.json).
    void onConfigurationChanged(const InteractionSettings& settings);

    // QAbstractNativeEventFilter
    bool nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result) override;

    // Called by the platform hooks when the hotkey changes state.
    // Public so free-function platform callbacks can reach it.
    void handlePlatformHotkeyEvent(bool pressed);

signals:
    void activated();           // hotkey pressed  (hold started)
    void released();            // hotkey released (hold ended)
    void errorOccurred(const QString& message);

private:
    struct Impl;                // platform state, defined in the .cpp
    Impl* m_impl = nullptr;

    QString m_hotkeyString;
    bool m_active = false;
    bool m_pressed = false;

    bool parseHotkey(int& virtualKey, unsigned int& modifiers) const;
};