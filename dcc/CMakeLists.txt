
# Polaris dock system-monitor control-center plugin (V25 QML plugin architecture).
# Added as a subdirectory by the root CMakeLists.txt only when the dde-control-center
# development files are installed, so this file is never configured on its own.
cmake_minimum_required(VERSION 3.23)

# PLUGIN_NAME is what the control center sees: install directory, QML module URI
# and qmldir all use it. The CMake target cannot be called "polaris" as well
# because the dock applet in the root project already owns that target name;
# dcc_install_plugin() renames the output to ${PLUGIN_NAME}.so regardless.
set(PLUGIN_NAME "polaris")
set(PLUGIN_TARGET "polaris_dcc")

find_package(Qt6 COMPONENTS Core REQUIRED)
find_package(DdeControlCenter REQUIRED)
find_package(Dtk6Core REQUIRED)

file(GLOB_RECURSE PLUGIN_SRCS
    "src/*.cpp"
    "src/*.h"
)

add_library(${PLUGIN_TARGET} MODULE ${PLUGIN_SRCS})

target_link_libraries(${PLUGIN_TARGET} PRIVATE
    Dde::Control-Center
    Qt6::Core
    Dtk6::Core
)

# Builds the QML module (lib${PLUGIN_NAME}_qml.so) and installs the plugin into
# plugins_v1.1/${PLUGIN_NAME}/ alongside the .so and qmldir.
dcc_install_plugin(NAME ${PLUGIN_NAME} TARGET ${PLUGIN_TARGET})
