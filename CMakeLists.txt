cmake_minimum_required(VERSION 3.16)

project(polaris VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

if (CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX /usr)
endif ()

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(DDEShell REQUIRED)
find_package(Dtk6Core REQUIRED)
find_package(Dtk6DConfig REQUIRED)

add_library(polaris SHARED
    src/polarisapplet.h
    src/polarisapplet.cpp
    src/systemreader.h
)

target_link_libraries(polaris PRIVATE
    Dde::Shell
    Qt6::Core
    Dtk6::Core
)

ds_install_package(PACKAGE org.deepin.ds.dock.polaris TARGET polaris)

# Settings shared by the dock applet and the control centre plugin: both sides
# talk to the same DConfig schema, so a change applies without any IPC of ours.
dtk_add_config_meta_files(APPID org.deepin.ds.dock.polaris
    FILES configs/org.deepin.ds.dock.polaris.json)

# The control centre plugin only builds where its development files are
# installed; the dock applet on its own stays buildable without them.
option(BUILD_DCC_PLUGIN "Build the dde-control-center plugin" ON)
if (BUILD_DCC_PLUGIN)
    find_package(DdeControlCenter QUIET)
    if (DdeControlCenter_FOUND)
        add_subdirectory(dcc)
    else ()
        message(WARNING "DdeControlCenter not found: skipping the control centre plugin")
    endif ()
endif ()

# The privileged helper, shipped in its own package: the dock item works without
# it and falls back to whatever it can read itself.
add_executable(polaris-sensord
    src/sensord/main.cpp
    src/systemreader.h
)
target_include_directories(polaris-sensord PRIVATE src)
target_link_libraries(polaris-sensord PRIVATE Qt6::Core)

install(TARGETS polaris-sensord RUNTIME DESTINATION ${CMAKE_INSTALL_LIBEXECDIR})
install(FILES data/polaris-sensord.service DESTINATION lib/systemd/system)
install(FILES data/polaris-sensord.8 DESTINATION ${CMAKE_INSTALL_MANDIR}/man8)

include(CTest)
if (BUILD_TESTING)
    add_executable(test_systemreader tests/test_systemreader.cpp)
    target_link_libraries(test_systemreader PRIVATE Qt6::Core)
    target_include_directories(test_systemreader PRIVATE src)
    add_test(NAME systemreader COMMAND test_systemreader)

    # The layout test needs the Qt QML runtime. /usr/bin/qml is a qtchooser
    # wrapper that fails without a selected Qt, so only look next to Qt itself
    # and skip the test when there is no runtime there.
    if (IS_ABSOLUTE "${QT6_INSTALL_BINS}")
        set(_qt_bin_dir "${QT6_INSTALL_BINS}")
    else ()
        set(_qt_bin_dir "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_BINS}")
    endif ()
    find_program(QML_RUNTIME NAMES qml6 qml HINTS "${_qt_bin_dir}" NO_DEFAULT_PATH)

    # The helper's publish guarantees: it keeps updating its file, and it never
    # writes through a symlink planted at the temporary path.
    find_program(PYTHON3 NAMES python3)
    if (PYTHON3)
        add_test(NAME sensord_publish
                 COMMAND ${PYTHON3} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_sensord_publish.py
                         $<TARGET_FILE:polaris-sensord>)

        # The QML side binds every reading to the applet by name, and a name the
        # applet does not declare is not an error in QML — the binding is simply
        # undefined and the surface shows nothing — so the names are checked
        # against the applet's own declarations here.
        add_test(NAME applet_bindings
                 COMMAND ${PYTHON3} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_applet_bindings.py)
        set_tests_properties(applet_bindings PROPERTIES
            PASS_REGULAR_EXPRESSION "binding checks passed"
            FAIL_REGULAR_EXPRESSION "FAILED")
    else ()
        message(STATUS "No python3 found, skipping the sensord publish test")
    endif ()

    if (QML_RUNTIME)
        # The QML checks report by printing a marker: the runtime ignores the
        # status passed to Qt.exit(), so the exit code alone proves nothing.
        add_test(NAME no_jitter
                 COMMAND ${QML_RUNTIME} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_no_jitter.qml)
        set_tests_properties(no_jitter PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
            PASS_REGULAR_EXPRESSION "no jitter checks passed"
            FAIL_REGULAR_EXPRESSION "FAILED")

        add_test(NAME chart_checks
                 COMMAND ${QML_RUNTIME} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_charts.qml)
        set_tests_properties(chart_checks PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
            PASS_REGULAR_EXPRESSION "chart checks passed"
            FAIL_REGULAR_EXPRESSION "FAILED")
    else ()
        message(STATUS "No Qt QML runtime found, skipping the no_jitter test")
    endif ()
endif ()
