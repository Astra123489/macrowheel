cmake_minimum_required(VERSION 3.22)
project(MacroWheelMenu VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# ---------------------------------------------------------------------------
# Qt 6
#
# Widgets is required by Qt.labs.platform's SystemTrayIcon (which wraps
# QSystemTrayIcon). The application object itself is still QGuiApplication;
# the wheel must never be a QtWidgets window.
# ---------------------------------------------------------------------------
find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick Network Widgets)

# ---------------------------------------------------------------------------
# Platform libraries
# ---------------------------------------------------------------------------
if(UNIX AND NOT APPLE)
    find_package(X11 REQUIRED)
    find_package(XTest REQUIRED)
endif()

# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
set(MENU_SOURCES
    resources/resources.qrc

    src/main.cpp

    src/config/ConfigService.cpp
    src/config/SchemaValidator.cpp

    src/resolve/ResolveConnection.cpp

    src/profile/ProfileResolver.cpp

    src/wheel/WheelGeometry.cpp

    src/commands/CommandExecutor.cpp
    src/commands/CommandRegistry.cpp
    src/commands/ShortcutResolver.cpp
    src/commands/SendKeys.cpp

    src/script/ScriptRuntimeManager.cpp
    src/script/ScriptLauncher.cpp

    src/hotkey/GlobalHotkey.cpp

    src/updater/Updater.cpp

    src/tray/TrayIcon.cpp
)

# NOTE: platform-specific hotkey code is compiled into GlobalHotkey.cpp via
# #ifdef. The files under src/hotkey/platform/ are reference implementations
# only and are intentionally NOT part of the build.

add_executable(MacroWheelMenu ${MENU_SOURCES})

target_include_directories(MacroWheelMenu PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(MacroWheelMenu PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::Network
    Qt6::Widgets
)

if(WIN32)
    target_link_libraries(MacroWheelMenu PRIVATE user32 shell32)
elseif(APPLE)
    target_link_libraries(MacroWheelMenu PRIVATE
        "-framework Cocoa"
        "-framework Carbon"
        "-framework ApplicationServices"
    )
elseif(UNIX)
    target_link_libraries(MacroWheelMenu PRIVATE
        ${X11_LIBRARIES}
        ${X11_XTest_LIB}
    )
endif()

# ---------------------------------------------------------------------------
# Embedded Python runtimes
#
# The runtime trees are populated out-of-band (see resources/python/README.md).
# Copy them next to the binary when they exist so a clean checkout still
# configures and builds before the runtimes have been fetched.
# ---------------------------------------------------------------------------
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/command_runtime")
    add_custom_command(TARGET MacroWheelMenu POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/command_runtime"
            "$<TARGET_FILE_DIR:MacroWheelMenu>/command_runtime"
    )
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/script_runtime")
    add_custom_command(TARGET MacroWheelMenu POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/script_runtime"
            "$<TARGET_FILE_DIR:MacroWheelMenu>/script_runtime"
    )
endif()

# ---------------------------------------------------------------------------
# Install / packaging
# ---------------------------------------------------------------------------
install(TARGETS MacroWheelMenu
    RUNTIME DESTINATION bin
    BUNDLE DESTINATION .
)

set(CPACK_PACKAGE_NAME "MacroWheelMenu")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")

if(WIN32)
    set(CPACK_GENERATOR "NSIS")
    set(CPACK_NSIS_INSTALL_ROOT "MacroWheel")
elseif(APPLE)
    set(CPACK_GENERATOR "DragNDrop")
else()
    set(CPACK_GENERATOR "TGZ")
endif()

include(CPack)