@echo off
rem --- '4_collect.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
if "%1"=="" color 1f&title COLLECT
if exist emsx_top.pld.1chipmsx goto collect
if exist emsx_top.pld.zemmixneo goto collect
if "%1"=="" if not exist emsx_top.pld goto err_msg

:collect
if exist old_fw rd /S /Q old_fw >nul 2>nul
if exist fw ren fw old_fw >nul 2>nul
if exist emsx_top.pld.1chipmsx md fw\1chipmsx >nul 2>nul
move /y emsx_top.pld.1chipmsx fw\1chipmsx >nul 2>nul
move /y recovery.pof.1chipmsx fw\1chipmsx >nul 2>nul
move /y emsx_top.fit.summary.1chipmsx fw\1chipmsx >nul 2>nul
ren fw\1chipmsx\emsx_top.pld.1chipmsx emsx_top.pld >nul 2>nul
ren fw\1chipmsx\recovery.pof.1chipmsx recovery.pof >nul 2>nul
ren fw\1chipmsx\emsx_top.fit.summary.1chipmsx fit_summary.log >nul 2>nul
if exist emsx_top.pld.zemmixneo md fw\zemmixneo >nul 2>nul
move /y emsx_top.pld.zemmixneo fw\zemmixneo >nul 2>nul
move /y recovery.pof.zemmixneo fw\zemmixneo >nul 2>nul
move /y emsx_top.fit.summary.zemmixneo fw\zemmixneo >nul 2>nul
ren fw\zemmixneo\emsx_top.pld.zemmixneo emsx_top.pld >nul 2>nul
ren fw\zemmixneo\recovery.pof.zemmixneo recovery.pof >nul 2>nul
ren fw\zemmixneo\emsx_top.fit.summary.zemmixneo fit_summary.log >nul 2>nul
if exist emsx_top.pld md fw >nul 2>nul
move /y emsx_top.pld fw >nul 2>nul
move /y recovery.pof fw >nul 2>nul
move /y emsx_top.fit.summary fw >nul 2>nul
del fw\fit_summary.log >nul 2>nul
ren fw\emsx_top.fit.summary fit_summary.log >nul 2>nul
if "%1"=="" cls&echo.&echo Done!
goto quit_0

:err_msg
if "%1"=="" color f0
echo.&echo 'emsx_top.pld' not found!

:quit_0
if "%1"=="" del *.sof >nul 2>nul

:timer
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul

:quit
