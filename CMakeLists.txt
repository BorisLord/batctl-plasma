cmake_minimum_required(VERSION 3.21...4.0)

project(batctl-plasma VERSION 0.1.5 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Produce compile_commands.json so clangd-based editors (Zed, VS Code, Neovim)
# get the exact Qt6 flags the build uses.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Qml Test)
qt_standard_project_setup(REQUIRES 6.6)

# Use the Qt installation that CMake found, including multiarch library paths.
get_target_property(QMAKE_EXECUTABLE Qt6::qmake IMPORTED_LOCATION)
execute_process(
    COMMAND "${QMAKE_EXECUTABLE}" -query QT_INSTALL_QML
    OUTPUT_VARIABLE QT_INSTALL_QML
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
if(NOT QT_INSTALL_QML)
    message(FATAL_ERROR "Qt did not report its QML installation directory")
endif()
set(QML_PLUGIN_DIR "${QT_INSTALL_QML}/org/batctl/plasma")

# URI of the C++ QML module. Must match the QML import line.
set(QML_MODULE_URI "org.batctl.plasma")

set(BACKEND_SOURCES
    plugin/batctlbackend.cpp
    plugin/batctlbackend.h
)

set(STAGED_PLUGIN "${CMAKE_BINARY_DIR}/qml/org/batctl/plasma")
qt_add_qml_module(batctlbackend
    PLUGIN_TARGET batctlbackend
    URI "${QML_MODULE_URI}"
    VERSION 1.0
    OUTPUT_DIRECTORY "${STAGED_PLUGIN}"
    SOURCES ${BACKEND_SOURCES}
)

target_link_libraries(batctlbackend PRIVATE Qt6::Core Qt6::Qml)
target_include_directories(batctlbackend PRIVATE plugin)
target_compile_options(batctlbackend PRIVATE -Wall -Wextra -Wpedantic -Werror)

enable_testing()
qt_add_executable(batctlbackend_test
    tests/batctlbackend_test.cpp
    ${BACKEND_SOURCES}
)
target_link_libraries(batctlbackend_test PRIVATE Qt6::Core Qt6::QmlIntegration Qt6::Test)
target_include_directories(batctlbackend_test PRIVATE plugin)
target_compile_options(batctlbackend_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
add_test(NAME batctlbackend_test COMMAND batctlbackend_test)
add_test(NAME install_layout COMMAND "${CMAKE_COMMAND}"
    "-DBUILD_DIR=${CMAKE_BINARY_DIR}" "-DQML_PLUGIN_DIR=${QML_PLUGIN_DIR}"
    -P "${CMAKE_SOURCE_DIR}/scripts/check-install.cmake")

# Reproducible install. Used by scripts/install.sh and the CI packaging step.
# DESTDIR redirects everything for tarball assembly.
install(TARGETS batctlbackend DESTINATION "${QML_PLUGIN_DIR}")
install(FILES
    "${STAGED_PLUGIN}/qmldir"
    "${STAGED_PLUGIN}/batctlbackend.qmltypes"
    DESTINATION "${QML_PLUGIN_DIR}"
)
install(DIRECTORY package/
        DESTINATION /usr/share/plasma/plasmoids/org.batctl.plasma)
install(FILES "polkit/org.batctl.plasma.policy"
        DESTINATION /usr/share/polkit-1/actions)
install(PROGRAMS scripts/uninstall.sh DESTINATION /usr/share/batctl-plasma)
install(FILES LICENSE THIRD_PARTY_LICENSES.md DESTINATION /usr/share/doc/batctl-plasma)
