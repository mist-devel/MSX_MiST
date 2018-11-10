@echo off
rem --- '5_auto-collect.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
if "%1"=="" color 1f&title AUTO-COLLECT
if "%1"=="--no-wait" color 1f&title Task "%~dp0emsx_top.qpf"
if not exist src\ goto err_msg
if "%1"=="" echo.&echo Press any key to start building...&pause >nul 2>nul
cls&echo.&echo Please wait...&echo.
rem ---------------cleanup----------------
call 3_finalize.cmd --no-wait >nul
call 4_collect.cmd --no-wait >nul
rem --------------------------------------
echo ^>^> Compile Design
echo   ^>^> Phase 1 - Analysis ^& Synthesis
c:\Altera\11.0sp1\quartus\bin\quartus_map.exe emsx_top.qpf >nul 2>nul
echo   ^>^> Phase 2 - Fitter (Place ^& Route)
c:\Altera\11.0sp1\quartus\bin\quartus_fit.exe emsx_top.qpf >nul 2>nul
echo   ^>^> Phase 3 - Assembler (Generate programming files)
c:\Altera\11.0sp1\quartus\bin\quartus_asm.exe emsx_top.qpf >nul 2>nul
echo   ^>^> Phase 4 - Convert programming files (EPCS4 Device)
c:\Altera\11.0sp1\quartus\bin\quartus_cpf.exe -c emsx_top_304k.cof >nul 2>nul
call 3_finalize.cmd --no-wait
call 4_collect.cmd --no-wait
if "%1"=="" del *.sof >nul 2>nul
cls&echo.&echo Done!
goto timer

:err_msg
if "%1"=="" color f0
echo.&echo 'src\' not found!

:timer
waitfor /T %TIMEOUT% pause >nul 2>nul

:quit
rem --- if "%1"=="" 6_fw-upload.cmd --no-wait
