@echo off
rem --- 'zz3_compile_multi_release.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
set SRC=c:\Altera\multi_release\
if "%1"=="" color 87&title Multi-Release compiler tool
if not exist %SRC%compile_multi_release.cmd goto err_msg
start "%SRC%" /d %SRC% /min compile_multi_release.cmd
goto quit

:err_msg
if "%1"=="" color f0
echo.&echo '%SRC%compile_multi_release.cmd' not found!

:timer
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul

:quit
