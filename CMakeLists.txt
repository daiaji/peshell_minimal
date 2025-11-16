# 设置所需的最低 CMake 版本
cmake_minimum_required(VERSION 3.15)

# 定义项目名称和所用语言 (C++ 和 C)
project(peshell CXX C)

# 设置 C++ 标准为 C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 全局设置 MSVC 动态运行时库 (/MD) - 仅限 Release
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL" CACHE STRING "MSVC Runtime Library" FORCE)
endif()

# 全局设置构建共享库 (DLL)
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries" FORCE)

# 添加 vendor 子目录
set(VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor)

# --- 0. spdlog (作为子项目，编译为 DLL) ---
add_subdirectory(${VENDOR_DIR}/spdlog)

# --- 0.5. CTPL (线程池, header-only) ---
add_library(ctpl INTERFACE)
target_include_directories(ctpl INTERFACE ${VENDOR_DIR}/ctpl)

# --- 1. LuaJIT (外部构建, 生成 DLL) ---
set(LUAJIT_SOURCE_DIR ${VENDOR_DIR}/luajit2/src)
set(LUAJIT_INSTALL_DIR ${CMAKE_BINARY_DIR}/luajit-install)
set(LUAJIT_INCLUDE_DIR ${LUAJIT_INSTALL_DIR}/include)
set(LUAJIT_LIBRARY ${LUAJIT_INSTALL_DIR}/lib/lua51.lib)
set(LUAJIT_DLL ${LUAJIT_INSTALL_DIR}/bin/lua51.dll)
set(LUAJIT_REQUIRED_HEADERS
    "${LUAJIT_SOURCE_DIR}/lua.h" "${LUAJIT_SOURCE_DIR}/lualib.h" "${LUAJIT_SOURCE_DIR}/lauxlib.h"
    "${LUAJIT_SOURCE_DIR}/luaconf.h" "${LUAJIT_SOURCE_DIR}/lua.hpp" "${LUAJIT_SOURCE_DIR}/luajit.h"
)
add_custom_command(
    OUTPUT ${LUAJIT_LIBRARY} ${LUAJIT_DLL}
    WORKING_DIRECTORY ${LUAJIT_SOURCE_DIR}
    COMMAND cmd.exe /c "msvcbuild.bat"
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_INSTALL_DIR}/lib
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_INSTALL_DIR}/bin
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua51.lib ${LUAJIT_INSTALL_DIR}/lib/
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua51.dll ${LUAJIT_INSTALL_DIR}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_REQUIRED_HEADERS} ${LUAJIT_INCLUDE_DIR}/
    DEPENDS ${VENDOR_DIR}/luajit2/src/msvcbuild.bat
    COMMENT "Building and packaging LuaJIT DLL and artifacts..."
    VERBATIM
)
add_custom_target(luajit_build ALL DEPENDS ${LUAJIT_LIBRARY} ${LUAJIT_DLL})
add_library(luajit INTERFACE)
target_include_directories(luajit INTERFACE ${LUAJIT_INCLUDE_DIR})
target_link_libraries(luajit INTERFACE ${LUAJIT_LIBRARY})
add_dependencies(luajit luajit_build)

# --- 2. proc_utils (作为子项目，编译为 DLL) ---
add_subdirectory(${VENDOR_DIR}/proc_utils)

# --- 3. luafilesystem (lfs) (手动从源文件构建为 DLL) ---
add_library(lfs SHARED
    ${VENDOR_DIR}/lfs/src/lfs.c
)
target_link_libraries(lfs PRIVATE luajit)
target_include_directories(lfs PUBLIC
    ${LUAJIT_INCLUDE_DIR}
)
target_compile_definitions(lfs PRIVATE LUA_BUILD_AS_DLL)

# 创建主可执行文件目标
add_executable(peshell src/main.cpp)

# 链接所有依赖项到主目标
target_link_libraries(peshell PRIVATE
    proc_utils
    lfs
    luajit
    user32.lib
    psapi.lib
    shell32.lib
    ole32.lib
    advapi32.lib
    spdlog::spdlog # <--- 这是 spdlog 的链接目标
    winmm.lib
    ctpl
)

# 构建后事件
set(OUTPUT_DIR "$<TARGET_FILE_DIR:peshell>")

add_custom_command(TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/scripts" "${OUTPUT_DIR}/scripts"
    COMMENT "Copying scripts to output directory..."
)

add_custom_command(TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${OUTPUT_DIR}/lib"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/vendor/penlight/lua/pl" "${OUTPUT_DIR}/lib/pl"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/vendor/luaunit/luaunit.lua" "${OUTPUT_DIR}/lib/luaunit.lua"
    COMMENT "Copying Penlight and LuaUnit to lib directory..."
)

# ==================== 修正点 ====================
add_custom_command(TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:proc_utils>" "${OUTPUT_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:lfs>" "${OUTPUT_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:spdlog>" "${OUTPUT_DIR}" # <-- 新增这一行
    COMMAND ${CMAKE_COMMAND} -E copy "${LUAJIT_DLL}" "${OUTPUT_DIR}"
    COMMENT "Copying required DLLs to output directory..."
)
# ===============================================