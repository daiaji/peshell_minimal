cmake_minimum_required(VERSION 3.15)
project(peshell CXX C)

# 1. 基础设置
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 动态链接 C++ 运行时 (/MD)，适配 PE 环境
if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL$<$<CONFIG:Debug>:Debug>" CACHE STRING "" FORCE)
endif()

set(VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# --- 2. 依赖库 (Header-Only) ---

# [CTPL]
add_library(ctpl INTERFACE)
target_include_directories(ctpl INTERFACE ${VENDOR_DIR}/ctpl)

# [spdlog]
add_library(spdlog INTERFACE)
target_include_directories(spdlog INTERFACE ${VENDOR_DIR}/spdlog/include)
target_compile_definitions(spdlog INTERFACE SPDLOG_HEADER_ONLY)

# [LuaJIT]
set(LUA_INSTALL_DIR ${CMAKE_SOURCE_DIR}/.lua) 
set(LUAJIT_LIBRARY ${LUA_INSTALL_DIR}/lib/lua51.lib)
set(LUAJIT_DLL ${LUA_INSTALL_DIR}/bin/lua51.dll)

add_library(luajit INTERFACE)
target_include_directories(luajit INTERFACE ${LUA_INSTALL_DIR}/include)
target_link_libraries(luajit INTERFACE ${LUAJIT_LIBRARY})

# --- 3. 主程序 ---
add_executable(peshell src/main.cpp src/logging.cpp)

if(MSVC)
    # [修正] 增加 /utf-8 以解决 spdlog/fmt 的静态断言错误
    target_compile_options(peshell PRIVATE /W4 /wd4100 /utf-8)
endif()

target_link_libraries(peshell PRIVATE 
    luajit 
    spdlog 
    ctpl 
    user32.lib 
    psapi.lib 
    shell32.lib 
    ole32.lib 
    advapi32.lib 
    winmm.lib
)

# 复制 lua51.dll
add_custom_command(TARGET peshell POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${LUAJIT_DLL}
    $<TARGET_FILE_DIR:peshell>
    COMMENT "Copying LuaJIT DLL..."
)

# --- 4. 安装规则 ---
install(TARGETS peshell RUNTIME DESTINATION bin)
install(FILES ${LUAJIT_DLL} DESTINATION bin)
install(DIRECTORY scripts/ DESTINATION share/lua/5.1)
install(FILES start_peshell_main.bat DESTINATION .)