# 设置所需的最低 CMake 版本
cmake_minimum_required(VERSION 3.15)

# 定义项目名称和所用语言 (C++ 和 C)
project(peshell CXX C)

# 设置 C++ 标准为 C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ----------------------------------------------------
# 设置 MSVC 运行时库为静态 (/MTd, /MT)
# ----------------------------------------------------
if(MSVC)
  # 这个设置会自动为 Release 配置选择 /MT，为 Debug 配置选择 /MTd
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# ----------------------------------------------------
# 添加 vendor 子目录
# ----------------------------------------------------
set(VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor)

# --- 1. LuaJIT (外部构建，并精确拷贝所需产物) ---
set(LUAJIT_SOURCE_DIR ${VENDOR_DIR}/luajit2/src)
set(LUAJIT_INSTALL_DIR ${CMAKE_BINARY_DIR}/luajit-install)
set(LUAJIT_INCLUDE_DIR ${LUAJIT_INSTALL_DIR}/include)
set(LUAJIT_LIBRARY ${LUAJIT_INSTALL_DIR}/lib/lua51.lib)

# 根据你的批处理脚本，明确列出需要拷贝的头文件
set(LUAJIT_REQUIRED_HEADERS
    "${LUAJIT_SOURCE_DIR}/lua.h"
    "${LUAJIT_SOURCE_DIR}/lualib.h"
    "${LUAJIT_SOURCE_DIR}/lauxlib.h"
    "${LUAJIT_SOURCE_DIR}/luaconf.h"
    "${LUAJIT_SOURCE_DIR}/lua.hpp"
    "${LUAJIT_SOURCE_DIR}/luajit.h"
)

# 添加自定义命令来构建 LuaJIT 并整理其产物
add_custom_command(
    OUTPUT ${LUAJIT_LIBRARY}

    # 1. 设置工作目录并执行编译
    WORKING_DIRECTORY ${LUAJIT_SOURCE_DIR}
    COMMAND cmd.exe /c "msvcbuild.bat" static

    # 2. [调试] 打印编译后的目录内容
    COMMAND ${CMAKE_COMMAND} -E echo "--- Listing contents of ${LUAJIT_SOURCE_DIR} after build ---"
    COMMAND cmd.exe /c dir
    COMMAND ${CMAKE_COMMAND} -E echo "--------------------------------------------------------"

    # 3. 创建我们的"安装"目录结构
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_INSTALL_DIR}/lib
    COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_INCLUDE_DIR}

    # 4. 拷贝编译好的库文件
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_SOURCE_DIR}/lua51.lib ${LUAJIT_INSTALL_DIR}/lib/

    # 5. 拷贝所有必需的头文件
    COMMAND ${CMAKE_COMMAND} -E copy ${LUAJIT_REQUIRED_HEADERS} ${LUAJIT_INCLUDE_DIR}/

    # 当 msvcbuild.bat 变化时，重新运行此命令
    DEPENDS ${VENDOR_DIR}/luajit2/src/msvcbuild.bat

    COMMENT "Building and packaging required LuaJIT artifacts from 'luajit2'..."
    # 使用 VERBATIM 确保命令字符串被正确传递
    VERBATIM
)

# 创建一个目标来触发 LuaJIT 的构建
add_custom_target(luajit_build ALL DEPENDS ${LUAJIT_LIBRARY})

# 创建一个 INTERFACE 库来代表 LuaJIT，它会“携带”头文件和库文件的信息
add_library(luajit INTERFACE)
target_include_directories(luajit INTERFACE ${LUAJIT_INCLUDE_DIR})
target_link_libraries(luajit INTERFACE ${LUAJIT_LIBRARY})
add_dependencies(luajit luajit_build)


# --- 2. proc_utils (作为子项目，编译为静态库) ---
add_subdirectory(${VENDOR_DIR}/proc_utils)
set_target_properties(proc_utils PROPERTIES BUILD_SHARED_LIBS OFF)


# --- 3. LuaFileSystem (lfs) (作为静态库编译) ---
add_library(lfs STATIC ${VENDOR_DIR}/lfs/src/lfs.c)

# lfs.c 需要 LuaJIT 的头文件，所以链接 luajit 接口库
target_link_libraries(lfs PUBLIC luajit)

# lfs 的公共头文件 lfs.h 在 vendor/lfs/src 目录中
# 任何链接到 lfs 的目标（比如 peshell）都应该能自动找到这个目录
target_include_directories(lfs PUBLIC
    "$<BUILD_INTERFACE:${VENDOR_DIR}/lfs/src>"
)

# 为 lfs.c 单独设置编译定义以避免警告
set_source_files_properties(${VENDOR_DIR}/lfs/src/lfs.c PROPERTIES
    COMPILE_DEFINITIONS _CRT_SECURE_NO_WARNINGS
)

# ----------------------------------------------------
# 创建主可执行文件目标
# ----------------------------------------------------
# 添加 WIN32 关键字，自动处理 main/WinMain 入口点和链接器子系统
add_executable(peshell WIN32 src/main.cpp)

# ----------------------------------------------------
# 链接所有依赖项到主目标
# ----------------------------------------------------
target_link_libraries(peshell PRIVATE
    # 链接 lfs 会自动带来 luajit 的依赖 (头文件和库)
    lfs
    # 链接 proc_utils
    proc_utils
    # 链接 Windows 平台必需的库
    user32.lib
    psapi.lib
)

# ----------------------------------------------------
# 构建后事件：拷贝 scripts 目录
# ----------------------------------------------------
add_custom_command(
    TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/scripts"
            "$<TARGET_FILE_DIR:peshell>/scripts"
    COMMENT "Copying scripts to output directory..."
)
