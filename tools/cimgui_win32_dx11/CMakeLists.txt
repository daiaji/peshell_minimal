cmake_minimum_required(VERSION 3.15)
project(cimgui_win32_dx11 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CIMGUI_ROOT "" CACHE PATH "Path to a cimgui checkout with imgui submodule initialized")
if(NOT CIMGUI_ROOT)
    message(FATAL_ERROR "CIMGUI_ROOT is required")
endif()

if(NOT EXISTS "${CIMGUI_ROOT}/imgui/imgui.cpp")
    message(FATAL_ERROR "CIMGUI_ROOT/imgui is missing. Clone cimgui with --recursive.")
endif()

set(CIMGUI_SOURCES
    "${CIMGUI_ROOT}/cimgui.cpp"
    "${CIMGUI_ROOT}/imgui/imgui.cpp"
    "${CIMGUI_ROOT}/imgui/imgui_draw.cpp"
    "${CIMGUI_ROOT}/imgui/imgui_demo.cpp"
    "${CIMGUI_ROOT}/imgui/imgui_widgets.cpp"
    "${CIMGUI_ROOT}/imgui/backends/imgui_impl_win32.cpp"
    "${CIMGUI_ROOT}/imgui/backends/imgui_impl_dx11.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/cimgui_win32_dx11_exports.cpp"
)

if(EXISTS "${CIMGUI_ROOT}/imgui/imgui_tables.cpp")
    list(APPEND CIMGUI_SOURCES "${CIMGUI_ROOT}/imgui/imgui_tables.cpp")
endif()

string(REPLACE "\\" "/" CIMCONFIG_PATH "${CIMGUI_ROOT}/cimconfig.h")

add_library(cimgui SHARED ${CIMGUI_SOURCES})
target_include_directories(cimgui PRIVATE
    "${CIMGUI_ROOT}"
    "${CIMGUI_ROOT}/imgui"
    "${CIMGUI_ROOT}/imgui/backends"
)
target_compile_definitions(cimgui PRIVATE
    IMGUI_USER_CONFIG="${CIMCONFIG_PATH}"
    IMGUI_DISABLE_OBSOLETE_FUNCTIONS=1
    IMGUI_IMPL_API=extern\ \"C\"\ __declspec\(dllexport\)
)
target_link_libraries(cimgui PRIVATE
    d3d11.lib
    dxgi.lib
    imm32.lib
)
set_target_properties(cimgui PROPERTIES PREFIX "")
