@echo off
rem --- 'zz4_collect_multi_release.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
set SRC=c:\Altera\multi_release\
set DEST=..\firmware\
if not exist %SRC% goto err_msg
if "%1"=="" color 1f&title Multi-Release collector tool
if "%1"=="" echo.&echo WARNING: the '%DEST%' folder will be completely replaced!
if "%1"=="" echo.&echo Press any key to proceed...&pause >nul
cls&if "%1"=="" echo.&echo Please wait...
rem ---------------cleanup----------------
rmdir /S /Q %DEST%\1chipmsx_br_layout >nul 2>nul
rmdir /S /Q %DEST%\1chipmsx_es_layout >nul 2>nul
rmdir /S /Q %DEST%\1chipmsx_fr_layout >nul 2>nul
rmdir /S /Q %DEST%\1chipmsx_jp_layout >nul 2>nul
rmdir /S /Q %DEST%\1chipmsx_uk_layout >nul 2>nul
rmdir /S /Q %DEST%\zemmixneo_br_layout >nul 2>nul
rmdir /S /Q %DEST%\zemmixneo_es_layout >nul 2>nul
rmdir /S /Q %DEST%\zemmixneo_fr_layout >nul 2>nul
rmdir /S /Q %DEST%\zemmixneo_jp_layout >nul 2>nul
rmdir /S /Q %DEST%\zemmixneo_uk_layout >nul 2>nul
rem --------------------------------------
if not exist emsx_top.qsf.area.off set OPTMODE=1
if not exist emsx_top.qsf.area.normal if "%OPTMODE%"=="" (set OPTMODE=2) else (set OPTMODE=0)
if not exist emsx_top.qsf.area.extraeffort if "%OPTMODE%"=="" (set OPTMODE=3) else (set OPTMODE=0)
if not exist emsx_top.qsf.balanced.off if "%OPTMODE%"=="" (set OPTMODE=4) else (set OPTMODE=0)
if not exist emsx_top.qsf.balanced.normal if "%OPTMODE%"=="" (set OPTMODE=5) else (set OPTMODE=0)
if not exist emsx_top.qsf.balanced.extraeffort if "%OPTMODE%"=="" (set OPTMODE=6) else (set OPTMODE=0)
if "%OPTMODE%"=="0" set OPTMODE=(unknown_optimization)
if "%OPTMODE%"=="1" set OPTMODE=(area_powerplay_off)
if "%OPTMODE%"=="2" set OPTMODE=(area_normal_compilation)
if "%OPTMODE%"=="3" set OPTMODE=(area_extra_effort)
if "%OPTMODE%"=="4" set OPTMODE=(balanced_powerplay_off)
if "%OPTMODE%"=="5" set OPTMODE=(balanced_normal_compilation)
if "%OPTMODE%"=="6" set OPTMODE=(balanced_extra_effort)
set YENSLASH=backslash
set LAYOUT=br
call :collect_1chipmsx
call :collect_zemmixneo
set LAYOUT=es
call :collect_1chipmsx
call :collect_zemmixneo
set LAYOUT=fr
call :collect_1chipmsx
call :collect_zemmixneo
set LAYOUT=uk
call :collect_1chipmsx
call :collect_zemmixneo
set YENSLASH=yen
set LAYOUT=jp
call :collect_1chipmsx
call :collect_zemmixneo
rem ---------------cleanup----------------
rmdir /S /Q %SRC% >nul 2>nul
rem --------------------------------------
if "%1"=="" cls&echo.&echo All done!
goto quit

:collect_1chipmsx
set INPDIR=%SRC%esemsx3_%LAYOUT%_1chipmsx\
set OUTDIR=%DEST%1chipmsx_%LAYOUT%_layout\bios_msx2plus_%YENSLASH%\
md %OUTDIR% >nul 2>nul
if not "%OPTMODE%"=="" rem.>"%OUTDIR%%OPTMODE%"
move %INPDIR%fw\emsx_top.pld %OUTDIR% >nul 2>nul
move %INPDIR%fw\recovery.pof %OUTDIR% >nul 2>nul
cd %INPDIR%
del emsx_top_304k.hex >nul 2>nul
ren emsx_top_304k.hex.%YENSLASH%.msx3 emsx_top_304k.hex >nul 2>nul
c:\Altera\11.0sp1\quartus\bin\quartus_cpf.exe -c emsx_top_304k.cof >nul 2>nul
call 3_finalize.cmd --no-wait
call 4_collect.cmd --no-wait
cd %~dp0
set OUTDIR=%DEST%1chipmsx_%LAYOUT%_layout\bios_msx3_%YENSLASH%\
md %OUTDIR% >nul 2>nul
if not "%OPTMODE%"=="" rem.>"%OUTDIR%%OPTMODE%"
move %INPDIR%fw\emsx_top.pld %OUTDIR% >nul 2>nul
move %INPDIR%fw\recovery.pof %OUTDIR% >nul 2>nul
goto:eof

:collect_zemmixneo
set INPDIR=%SRC%esemsx3_%LAYOUT%_zemmixneo\
set OUTDIR=%DEST%zemmixneo_%LAYOUT%_layout\bios_zemmixneo_%YENSLASH%\
md %OUTDIR% >nul 2>nul
if not "%OPTMODE%"=="" rem.>"%OUTDIR%%OPTMODE%"
move %INPDIR%fw\emsx_top.pld %OUTDIR% >nul 2>nul
move %INPDIR%fw\recovery.pof %OUTDIR% >nul 2>nul
cd %INPDIR%
del emsx_top_304k.hex >nul 2>nul
ren emsx_top_304k.hex.%YENSLASH%.zemmixneobr emsx_top_304k.hex >nul 2>nul
c:\Altera\11.0sp1\quartus\bin\quartus_cpf.exe -c emsx_top_304k.cof >nul 2>nul
call 3_finalize.cmd --no-wait
call 4_collect.cmd --no-wait
cd %~dp0
set OUTDIR=%DEST%zemmixneo_%LAYOUT%_layout\bios_zemmixneobr_%YENSLASH%\
md %OUTDIR% >nul 2>nul
if not "%OPTMODE%"=="" rem.>"%OUTDIR%%OPTMODE%"
move %INPDIR%fw\emsx_top.pld %OUTDIR% >nul 2>nul
move %INPDIR%fw\recovery.pof %OUTDIR% >nul 2>nul
cd %INPDIR%
del emsx_top_304k.hex >nul 2>nul
ren emsx_top_304k.hex.%YENSLASH%.sx1 emsx_top_304k.hex >nul 2>nul
c:\Altera\11.0sp1\quartus\bin\quartus_cpf.exe -c emsx_top_304k.cof >nul 2>nul
call 3_finalize.cmd --no-wait
call 4_collect.cmd --no-wait
cd %~dp0
set OUTDIR=%DEST%zemmixneo_%LAYOUT%_layout\bios_sx1_%YENSLASH%\
md %OUTDIR% >nul 2>nul
if not "%OPTMODE%"=="" rem.>"%OUTDIR%%OPTMODE%"
move %INPDIR%fw\emsx_top.pld %OUTDIR% >nul 2>nul
move %INPDIR%fw\recovery.pof %OUTDIR% >nul 2>nul
goto:eof

:err_msg
if "%1"=="" color f0
echo.&echo '%SRC%' not found!

:quit
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul
