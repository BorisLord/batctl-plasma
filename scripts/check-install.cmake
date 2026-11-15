# Exercise the real install rules without touching the host system.
set(stage "${BUILD_DIR}/install-check")
file(REMOVE_RECURSE "${stage}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E env "DESTDIR=${stage}"
    "${CMAKE_COMMAND}" --install "${BUILD_DIR}"
    RESULT_VARIABLE result OUTPUT_QUIET)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Staged installation failed: ${result}")
endif()
foreach(path IN ITEMS
    "${QML_PLUGIN_DIR}/libbatctlbackend.so"
    "${QML_PLUGIN_DIR}/qmldir"
    "${QML_PLUGIN_DIR}/batctlbackend.qmltypes"
    /usr/share/polkit-1/actions/org.batctl.plasma.policy
    /usr/share/plasma/plasmoids/org.batctl.plasma/metadata.json
    /usr/share/plasma/plasmoids/org.batctl.plasma/contents/ui/main.qml
    /usr/share/batctl-plasma/uninstall.sh
    /usr/share/doc/batctl-plasma/LICENSE
    /usr/share/doc/batctl-plasma/THIRD_PARTY_LICENSES.md)
    if(NOT EXISTS "${stage}${path}")
        message(FATAL_ERROR "Installation missing ${path}")
    endif()
endforeach()
file(REMOVE_RECURSE "${stage}")
