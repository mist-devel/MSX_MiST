@echo off
rem --- '3_finalize.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
if "%1"=="" color 1f&title FINALIZE
rd /s /q db >nul 2>nul
rd /s /q incremental_db >nul 2>nul
del *.done >nul 2>nul
del *.map >nul 2>nul
del *.pin >nul 2>nul
rem.>emsx_top.qpf
del *.rpt >nul 2>nul
del *.map.summary >nul 2>nul
del *.sta.summary >nul 2>nul
del *.qdf >nul 2>nul
del /s *.bak >nul 2>nul
if "%1"=="" if not exist emsx_top.pof goto err_msg
pof2pld emsx_top.pof emsx_top.pld >nul 2>nul
del recovery.pof >nul 2>nul
ren emsx_top.pof recovery.pof >nul 2>nul
if "%1"=="" echo.&echo Done!
goto timer

:err_msg
if "%1"=="" color f0
echo.&echo 'emsx_top.pof' not found!

:timer
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul

:quit
