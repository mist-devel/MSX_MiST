@echo off
rem --- '2_compile.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
if "%1"=="" color 87&title COMPILE
if not exist emsx_top.qpf goto err_msg
explorer emsx_top.qpf
goto quit

:err_msg
if "%1"=="" color f0
echo.&echo 'emsx_top.qpf' not found!

:timer
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul

:quit
