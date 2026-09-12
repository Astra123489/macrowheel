cmake_minimum_required(VERSION 3.22)

# Product version. Declared as a cache variable so the release workflow can
# pass the git tag on the command line while a plain local configure still
# gets a default. PROJECT_VERSION derives from it and CPack inherits it
# further down, so the tag is the single source of truth for the version the
# application reports, the version CPack stamps into the installer, and the
# version latest.json advertises to the updater.
set(MACROWHEEL_VERSION "1.0.0" CACHE STRING "Macro Wheel Menu version")

project(MacroWheelMenu VERSION ${MACROWHEEL_VERSION} LANGUAGES CXX)

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

# Compiled-in version. Exposed as a string literal so the running application
# reports the same value the installer carries and the updater compares
# against; without a shared source those three can disagree and the updater
# either loops forever or never fires at all.
target_compile_definitions(MacroWheelMenu PRIVATE
    MACROWHEEL_VERSION="${PROJECT_VERSION}"
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
#
# The installer has to be self-contained: the Menu binary, its Qt runtime, and
# both embedded Python runtimes. Anything missing here means the installed
# application cannot execute built-in commands or user scripts.
# ---------------------------------------------------------------------------
install(TARGETS MacroWheelMenu
    RUNTIME DESTINATION bin
    BUNDLE DESTINATION .
)

# Qt libraries and plugins, deployed with the platform's official tool
# (windeployqt on Windows, macdeployqt on macOS). Without this the installed
# executable cannot start: it has no Qt DLLs and no platform plugin beside it.
qt_generate_deploy_app_script(
    TARGET MacroWheelMenu
    OUTPUT_SCRIPT qt_deploy_script
    NO_UNSUPPORTED_PLATFORM_ERROR
)
install(SCRIPT ${qt_deploy_script})

# QML modules.
#
# The QML sources are compiled into the binary through resources.qrc, so
# windeployqt cannot discover the imports by inspecting the executable. The
# documented way to tell it is `--qmldir` via DEPLOY_TOOL_OPTIONS, but that
# option cannot be used here: the generated deploy script writes each list
# element as-is, so a source path containing a space is split at the space and
# windeployqt fails with "<path> does not exist". This workspace lives under
# ".../macro wheel/...", so that path always fails.
#
# Installing the module trees explicitly avoids the argument-passing problem
# entirely and is deterministic across Qt versions and build directories. The
# modules listed are exactly what Main.qml and WheelCanvas.qml import:
#   QtQuick           -> QtQuick 2.15          (Main.qml, WheelCanvas.qml)
#   QtQuick/Window    -> QtQuick.Window 2.15   (Main.qml, inside QtQuick)
#   QtQml             -> runtime dependency of QtQuick
#   Qt/labs/platform  -> Qt.labs.platform 1.1  (Main.qml tray)
get_filename_component(QT_PREFIX "${Qt6_DIR}/../../.." ABSOLUTE)
set(QT_QML_SOURCE_DIR "${QT_PREFIX}/qml")

# install(DIRECTORY <src> DESTINATION <dst>) appends the LAST path component
# of <src> to <dst> when <src> has no trailing slash. Writing the module's own
# import path as the destination therefore nests it one level too deep:
#   src ".../qml/QtQuick" + dst "qml/QtQuick"  -> qml/QtQuick/QtQuick
# Qt then fails to find the module and reports it as not installed.
#
# A trailing slash on <src> changes the meaning to "copy the *contents* of
# <src> into <dst>", which is what is wanted here: the destination in the
# table below then reads exactly as the module's import path.
set(QML_MODULES
    "QtQml=qml/QtQml"
    "QtQuick=qml/QtQuick"
    "Qt/labs/platform=qml/Qt/labs/platform")

foreach(entry IN LISTS QML_MODULES)
    string(REPLACE "=" ";" parts "${entry}")
    list(GET parts 0 qml_module)
    list(GET parts 1 qml_destination)

    if(EXISTS "${QT_QML_SOURCE_DIR}/${qml_module}")
        install(DIRECTORY "${QT_QML_SOURCE_DIR}/${qml_module}/"
            DESTINATION "${qml_destination}"
            USE_SOURCE_PERMISSIONS)
    else()
        message(WARNING "QML module not found, installer will be incomplete: "
                        "${QT_QML_SOURCE_DIR}/${qml_module}")
    endif()
endforeach()

# Embedded Python runtimes. Populated out-of-band by
# tools/fetch-python-runtimes.ps1, and gitignored, so they are absent on a
# plain checkout. Warn rather than fail: the Menu still builds and runs, it
# just cannot execute scripts until the runtimes are fetched.
#
# The trailing slash on the source copies the directory *contents* into the
# destination, so the tree lands at bin/command_runtime/python.exe, which is
# where QCoreApplication::applicationDirPath() looks for it.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/command_runtime")
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/command_runtime/"
        DESTINATION bin/command_runtime
        USE_SOURCE_PERMISSIONS)
else()
    message(WARNING "resources/python/command_runtime is missing; the installer "
                    "will ship without the locked Command Runtime.")
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/script_runtime")
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/resources/python/script_runtime/"
        DESTINATION bin/script_runtime
        USE_SOURCE_PERMISSIONS)
else()
    message(WARNING "resources/python/script_runtime is missing; the installer "
                    "will ship without the Script Runtime.")
endif()

set(CPACK_PACKAGE_NAME "MacroWheelMenu")

# Honour an externally supplied version. The release workflow passes the git
# tag, so a tagged build is not stuck on the hardcoded project version.
if(NOT DEFINED CPACK_PACKAGE_VERSION)
    set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
endif()

if(WIN32)
    set(CPACK_GENERATOR "NSIS")
    # CPACK_NSIS_INSTALL_ROOT is the root the installer defaults to, not the
    # application folder, and NSIS expects an absolute path constant there. A
    # bare name produced a relative InstallDir. The application folder comes
    # from CPACK_PACKAGE_INSTALL_DIRECTORY, giving C:\Program Files\MacroWheel.
    set(CPACK_NSIS_INSTALL_ROOT "$PROGRAMFILES64")
    set(CPACK_PACKAGE_INSTALL_DIRECTORY "MacroWheel")
elseif(APPLE)
    set(CPACK_GENERATOR "DragNDrop")
else()
    set(CPACK_GENERATOR "TGZ")
endif()

include(CPack)