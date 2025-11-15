# 设置所需的最低 CMake 版本
cmake_minimum_required(VERSION 3.15)

# 定义项目名称和所用语言 (C++ 和 C)
project(peshell CXX C)

# 设置 C++ 标准为 C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# -------------------------------------------------------------------------
# [关键修复 1] 全局设置 MSVC 静态运行时库 (/MT)
# -------------------------------------------------------------------------
# 这会确保本项目以及所有子项目都使用静态链接的C++运行时库，
# 从而消除对 vcruntime140.dll 等外部DLL的依赖。
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "MSVC Runtime Library" FORCE)
endif()


# -------------------------------------------------------------------------
# 添加 vendor 子目录
# -------------------------------------------------------------------------
set(VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor)

# --- 0. spdlog (作为 header-only 库添加) ---
add_subdirectory(${VENDOR_DIR}/spdlog)


# --- 1. LuaJIT (外部构建) ---
# ... (这部分逻辑不变，保持原样) ...
set(LUAJIT_SOURCE_DIR ${VENDOR_DIR}/luajit2/src)
set(LUAJIT_INSTALL_DIR ${CMAKE_BINARY_DIR}/luajit-install)
set(LUAJIT_INCLUDE_DIR ${LUAJIT_INSTALL_DIR}/include)
set(LUAJIT_LIBRARY ${LUAJIT_INSTALL_DIR}/lib/lua51.lib)

set(LUAJIT_REQUIRED_HEADERS
    "${LUAJIT_SOURCE_DIR}/lua.h"
    "${LUAJIT_SOURCE_DIR}/lualib.h"
    "${LUAJIT_SOURCE_DIR}/lauxlib.h"
    "${LUAJIT_SOURCE_DIR}/luaconf.h"
    "${LUAJIT_SOURCE_DIR}/lua.hpp"
    "${LUAJIT_SOURCE_DIR}/luajit.h"
)

add_custom_command(
    OUTPUT ${LUAJIT_LIBRARY}
    WORKING_DIRECTORY ${LUAJIT_SOURCE_DIR}
    COMMAND cmd.exe /c "msvcbuild.bat" static
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_INSTALL_DIR}/lib
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_INCLUDE_DIR}
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua51.lib ${LUAJIT_INSTALL_DIR}/lib/
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_REQUIRED_HEADERS} ${LUAJIT_INCLUDE_DIR}/
    DEPENDS ${VENDOR_DIR}/luajit2/src/msvcbuild.bat
    COMMENT "Building and packaging required LuaJIT artifacts from 'luajit2'..."
    VERBATIM
)
add_custom_target(luajit_build ALL DEPENDS ${LUAJIT_LIBRARY})
add_library(luajit INTERFACE)
target_include_directories(luajit INTERFACE ${LUAJIT_INCLUDE_DIR})
target_link_libraries(luajit INTERFACE ${LUAJIT_LIBRARY})
add_dependencies(luajit luajit_build)


# --- 2. proc_utils (作为子项目，编译为静态库) ---
# -------------------------------------------------------------------------
# [关键修复 2] 在包含子目录之前，设置其构建选项
# -------------------------------------------------------------------------
# 这会确保当 CMake 处理 proc_utils 的 CMakeLists.txt 时，
# BUILD_SHARED_LIBS 选项已经被设为 OFF，从而从一开始就将其配置为静态库。
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries for subprojects" FORCE)
add_subdirectory(${VENDOR_DIR}/proc_utils)


# --- 3. LuaFileSystem (lfs) (作为静态库编译) ---
add_library(lfs STATIC ${VENDOR_DIR}/lfs/src/lfs.c)
target_link_libraries(lfs PUBLIC luajit)
target_include_directories(lfs PUBLIC "$<BUILD_INTERFACE:${VENDOR_DIR}/lfs/src>")
set_source_files_properties(${VENDOR_DIR}/lfs/src/lfs.c PROPERTIES
    COMPILE_DEFINITIONS _CRT_SECURE_NO_WARNINGS
)


# ----------------------------------------------------
# 创建主可执行文件目标
# ----------------------------------------------------
add_executable(peshell src/main.cpp)


# ----------------------------------------------------
# 链接所有依赖项到主目标
# ----------------------------------------------------
target_link_libraries(peshell PRIVATE
    lfs
    proc_utils
    user32.lib
    psapi.lib
    spdlog::spdlog
)

# ----------------------------------------------------
# 构建后事件 (保持不变)
# ----------------------------------------------------
add_custom_command(
    TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/scripts"
            "$<TARGET_FILE_DIR:peshell>/scripts"
    COMMENT "Copying scripts to output directory..."
)
add_custom_command(
    TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_CURRENT_SOURCE_DIR}/vendor/luaunit/luaunit.lua"
            "$<TARGET_FILE_DIR:peshell>/scripts/luaunit.lua"
    COMMENT "Copying luaunit.lua to scripts directory..."
)
add_custom_command(
    TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:peshell>/modules"
    COMMENT "Creating modules directory..."
)