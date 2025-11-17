# CMakeLists.txt

cmake_minimum_required(VERSION 3.15)
project(peshell CXX C)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries" FORCE)

# 为不同类型的产物设置独立的、结构化的输出目录
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin) # .exe 和运行时 .dll
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib) # .dll 库
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib) # .lib 文件

set(VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor)

# --- C++ 依赖 ---
# 将 spdlog 设置为非头文件库，以便我们可以统一处理 DLL
set(SPDLOG_BUILD_SHARED ON CACHE BOOL "" FORCE) # 强制构建动态库
add_subdirectory(${VENDOR_DIR}/spdlog)

add_library(ctpl INTERFACE)
target_include_directories(ctpl INTERFACE ${VENDOR_DIR}/ctpl)
add_subdirectory(${VENDOR_DIR}/proc_utils)

# --- LuaJIT 构建与安装逻辑 ---
set(LUAJIT_SOURCE_DIR ${VENDOR_DIR}/luajit2/src)
set(LUA_INSTALL_DIR ${CMAKE_SOURCE_DIR}/.lua) 
set(LUAJIT_LIBRARY ${LUA_INSTALL_DIR}/lib/lua51.lib)
set(LUAJIT_DLL ${LUA_INSTALL_DIR}/bin/lua51.dll)

add_custom_target(luajit_compile
    COMMAND cmd.exe /c "msvcbuild.bat"
    WORKING_DIRECTORY ${LUAJIT_SOURCE_DIR}
    COMMENT "Building LuaJIT with MSVC..."
)

add_custom_target(install_luajit
    DEPENDS luajit_compile
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUA_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUA_INSTALL_DIR}/bin
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUA_INSTALL_DIR}/lib
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua.h ${LUA_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lualib.h ${LUA_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lauxlib.h ${LUA_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/luaconf.h ${LUA_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua.hpp ${LUA_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/luajit.h ${LUA_INSTALL_DIR}/include
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua51.dll ${LUA_INSTALL_DIR}/bin
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua51.lib ${LUA_INSTALL_DIR}/lib
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/luajit.exe ${LUA_INSTALL_DIR}/bin
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/luajit.exe ${LUA_INSTALL_DIR}/bin/lua.exe
    COMMENT "Installing MSVC-built LuaJIT to ${LUA_INSTALL_DIR}"
)

add_library(luajit INTERFACE)
# 确保 install_luajit 在 luajit 目标被使用前完成
add_dependencies(luajit install_luajit)
target_include_directories(luajit INTERFACE ${LUA_INSTALL_DIR}/include)
target_link_libraries(luajit INTERFACE ${LUAJIT_LIBRARY})

# --- 主目标定义 ---
add_executable(peshell src/main.cpp)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL" CACHE STRING "MSVC Runtime Library" FORCE)
  if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    target_compile_options(peshell PRIVATE -Wall -Wextra -Wno-unused-parameter)
    message(STATUS "Compiler: Clang (clang-cl mode)")
  else()
    target_compile_options(peshell PRIVATE /W4)
    message(STATUS "Compiler: MSVC")
  endif()
endif()

target_link_libraries(peshell PRIVATE 
    proc_utils 
    luajit 
    spdlog::spdlog 
    ctpl 
    user32.lib 
    psapi.lib 
    shell32.lib 
    ole32.lib 
    advapi32.lib 
    winmm.lib
)

# [[ 核心修正 ]]
# 添加一个构建后事件，将 lua51.dll 复制到 peshell.exe 所在的目录 (build/bin)
# 这样在 CI 流程中，我们可以直接从 build/bin 复制所有运行时需要的文件。
add_custom_command(TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${LUAJIT_DLL}
    $<TARGET_FILE_DIR:peshell>
    COMMENT "Copying LuaJIT DLL to output directory"
)

# ==================================================================
#  安装规则 (Installation Rules) - 简化版
# ==================================================================
# 这部分现在主要是为了本地开发方便，CI流程不再直接依赖它。
# 它会创建一个与我们手动组装的 package 目录类似的结构。

# 安装可执行文件和所有运行时动态库到 <prefix>/bin
install(TARGETS peshell proc_utils spdlog
        RUNTIME DESTINATION bin
        LIBRARY DESTINATION bin  # 将 .dll 也安装到 bin
        ARCHIVE DESTINATION lib
)

# 安装 LuaJIT DLL
install(FILES ${LUAJIT_DLL} DESTINATION bin)

# 安装所有 Lua 脚本
install(DIRECTORY scripts/ DESTINATION share/lua/5.1)

# 安装启动脚本
install(FILES start_peshell_main.bat DESTINATION .)