@echo off
rem --- 'zz2_prepare_multi_release.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
set SRC=esemsx3\
set DEST=c:\Altera\multi_release\
if "%1"=="" color 1f&title Multi-Release preparing tool
if not exist src\ goto err_msg
if "%1"=="" echo.&echo A copy of this project will be prepared
if "%1"=="" echo to compile various layout in parallel.
if "%1"=="" echo.&echo Destination folder: %DEST%&echo.
if "%1"=="" echo Press any key to continue...&pause >nul
if "%1"=="" cls&echo.&echo Please wait...
if exist __zemmixneo__ set DEVICE=__zemmixneo__&call 1_swap.cmd --no-wait&cd %~dp0
rem ---------------cleanup----------------
rmdir /S /Q %DEST% >nul 2>nul
md %DEST% >nul 2>nul
rem --------------------------------------
echo @echo off>%DEST%compile_multi_release.cmd
echo rem --- 'compile_multi_release.cmd' v2.3 by KdL (2018.07.27)>>%DEST%compile_multi_release.cmd
echo.>>%DEST%compile_multi_release.cmd

rem --- BR layout
cd ..
set LAYOUT=br
set LAYOUTFN=brazilian
set YENSLASH=backslash
set INPDIR=%SRC%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_1chipmsx\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
del %OUTDIR%src\peripheral\keymap.vhd >nul 2>nul
ren %OUTDIR%src\peripheral\keymap.vhd.%LAYOUTFN% keymap.vhd
set INPDIR=%OUTDIR%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_zemmixneo\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
cd %OUTDIR%
call %OUTDIR%1_swap.cmd --no-wait
cd %~dp0

rem --- ES layout
cd ..
set LAYOUT=es
set LAYOUTFN=spanish
set YENSLASH=backslash
set INPDIR=%SRC%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_1chipmsx\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
rem --------vdp_vga.vhd.topleft25---------
del %OUTDIR%src\video\vdp_vga.vhd >nul 2>nul
ren %OUTDIR%src\video\vdp_vga.vhd.topleft25 vdp_vga.vhd
rem --------------------------------------
del %OUTDIR%src\peripheral\keymap.vhd >nul 2>nul
ren %OUTDIR%src\peripheral\keymap.vhd.%LAYOUTFN% keymap.vhd
set INPDIR=%OUTDIR%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_zemmixneo\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
cd %OUTDIR%
call %OUTDIR%1_swap.cmd --no-wait
cd %~dp0

rem --- FR layout
cd ..
set LAYOUT=fr
set LAYOUTFN=french
set YENSLASH=backslash
set INPDIR=%SRC%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_1chipmsx\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
rem --------vdp_vga.vhd.topleft25---------
del %OUTDIR%src\video\vdp_vga.vhd >nul 2>nul
ren %OUTDIR%src\video\vdp_vga.vhd.topleft25 vdp_vga.vhd
rem --------------------------------------
del %OUTDIR%src\peripheral\keymap.vhd >nul 2>nul
ren %OUTDIR%src\peripheral\keymap.vhd.%LAYOUTFN% keymap.vhd
set INPDIR=%OUTDIR%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_zemmixneo\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
cd %OUTDIR%
call %OUTDIR%1_swap.cmd --no-wait
cd %~dp0

rem -- JP layout
cd ..
set LAYOUT=jp
set LAYOUTFN=japanese
set YENSLASH=yen
set INPDIR=%SRC%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_1chipmsx\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
del %OUTDIR%src\peripheral\swioports.vhd >nul 2>nul
ren %OUTDIR%src\peripheral\swioports.vhd.%LAYOUTFN% swioports.vhd
del %OUTDIR%emsx_top_304k.hex >nul 2>nul
ren %OUTDIR%emsx_top_304k.hex.%YENSLASH%.msx2plus emsx_top_304k.hex
set INPDIR=%OUTDIR%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_zemmixneo\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
cd %OUTDIR%
call %OUTDIR%1_swap.cmd --no-wait
del %OUTDIR%src\peripheral\swioports.vhd >nul 2>nul
ren %OUTDIR%src\peripheral\swioports.vhd.%LAYOUTFN% swioports.vhd
del %OUTDIR%emsx_top_304k.hex >nul 2>nul
ren %OUTDIR%emsx_top_304k.hex.%YENSLASH%.zemmixneo emsx_top_304k.hex
cd %~dp0

rem --- UK layout
cd ..
set LAYOUT=uk
set YENSLASH=backslash
set INPDIR=%SRC%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_1chipmsx\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
set INPDIR=%OUTDIR%
set OUTDIR=%DEST%esemsx3_%LAYOUT%_zemmixneo\
echo start "compile" /d "%OUTDIR%" /min 5_auto-collect.cmd --no-wait>>%DEST%compile_multi_release.cmd
xcopy /S /E /Y %INPDIR%*.* %OUTDIR% >nul 2>nul
cd %OUTDIR%
call %OUTDIR%1_swap.cmd --no-wait
cd %~dp0

if "%DEVICE%"=="__zemmixneo__" call 1_swap.cmd --no-wait&cd %~dp0
if "%1"=="" cls&echo.&echo All done!
goto quit

:err_msg
if "%1"=="" color f0
echo.&echo 'src\' not found!

:quit
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul
