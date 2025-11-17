@echo off
setlocal

:: ==================================================================
:: PEShell Main Mode Starter (v2.0 - Self-Contained Package)
:: ------------------------------------------------------------------
:: 作用:
::   以 "main" (守护) 模式启动 PEShell，并执行 share/lua/5.1/init.lua 脚本。
::   此模式模拟 PECMD.exe MAIN ... 的核心功能，用于 PE 环境的自动初始化。
::
:: 用法:
::   将整个包复制到目标位置，然后双击运行此文件。
:: ==================================================================

:: 获取此批处理文件所在的目录，即包的根目录
set "PACKAGE_ROOT=%~dp0"

:: 构建 peshell.exe 和 init.lua 脚本的完整路径
set "PESHELL_EXE=%PACKAGE_ROOT%bin\peshell.exe"
set "INIT_SCRIPT=%PACKAGE_ROOT%share\lua\5.1\init.lua"

:: 检查 peshell.exe 是否存在
if not exist "%PESHELL_EXE%" (
    echo [ERROR] Cannot find peshell.exe at:
    echo %PESHELL_EXE%
    echo Make sure this batch file is in the root of the extracted package.
    pause
    exit /b 1
)

:: 检查 init.lua 脚本是否存在
if not exist "%INIT_SCRIPT%" (
    echo [ERROR] Cannot find the main script at:
    echo %INIT_SCRIPT%
    pause
    exit /b 1
)

:: 执行命令
echo [INFO] Starting PEShell in main (guardian) mode...
echo [INFO] Command: "%PESHELL_EXE%" main "%INIT_SCRIPT%"
echo.

"%PESHELL_EXE%" main "%INIT_SCRIPT%"

echo.
echo [INFO] PEShell process has exited.
pause

endlocal