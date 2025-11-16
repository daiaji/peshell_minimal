@echo off
setlocal

:: ==================================================================
:: PEShell Main Mode Starter
:: ------------------------------------------------------------------
:: 作用:
::   以 "main" (守护) 模式启动 PEShell，并执行 scripts\init.lua 脚本。
::   此模式模拟 PECMD.exe MAIN ... 的核心功能，用于 PE 环境的自动初始化。
::
:: 用法:
::   直接双击运行此文件即可。
:: ==================================================================

:: 获取此批处理文件所在的目录，该目录也应该是 peshell.exe 所在的目录
set "PESHELL_DIR=%~dp0"

:: 构建 peshell.exe 和 init.lua 脚本的完整路径
:: %~dp0 包含一个结尾的反斜杠，所以可以直接拼接文件名
set "PESHELL_EXE=%PESHELL_DIR%peshell.exe"
set "INIT_SCRIPT=%PESHELL_DIR%scripts\init.lua"

:: 检查 peshell.exe 是否存在
if not exist "%PESHELL_EXE%" (
    echo [ERROR] Cannot find peshell.exe at:
    echo %PESHELL_EXE%
    echo Make sure this batch file is in the same directory as peshell.exe.
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