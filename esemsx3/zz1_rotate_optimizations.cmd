@echo off
rem --- 'zz1_rotate_optimizations.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
set SRC=.\
set DEST=c:\Altera\multi_release
if "%1"=="" color 1f&title Optimization techniques
if exist %DEST% goto err_msg

if not exist %SRC%emsx_top.qsf.balanced.extraeffort (
    ren %SRC%emsx_top.qsf emsx_top.qsf.balanced.extraeffort >nul 2>nul
    ren %SRC%emsx_top.qsf.area.off emsx_top.qsf >nul 2>nul
    if "%1"=="" color 3f&cls&echo.&echo [1] AREA ^& POWERPLAY OFF are set!
    goto quit
)

if not exist %SRC%emsx_top.qsf.area.off (
    ren %SRC%emsx_top.qsf emsx_top.qsf.area.off >nul 2>nul
    ren %SRC%emsx_top.qsf.area.normal emsx_top.qsf >nul 2>nul
    if "%1"=="" color 1f&cls&echo.&echo [A] AREA ^& NORMAL COMPILATION are set!  ^(default^)
    goto quit
)

if not exist %SRC%emsx_top.qsf.area.normal (
    ren %SRC%emsx_top.qsf emsx_top.qsf.area.normal >nul 2>nul
    ren %SRC%emsx_top.qsf.area.extraeffort emsx_top.qsf >nul 2>nul
    if "%1"=="" color 5f&cls&echo.&echo [X] AREA ^& EXTRA EFFORT are set!
    goto quit
)

if not exist %SRC%emsx_top.qsf.area.extraeffort (
    ren %SRC%emsx_top.qsf emsx_top.qsf.area.extraeffort >nul 2>nul
    ren %SRC%emsx_top.qsf.balanced.off emsx_top.qsf >nul 2>nul
    if "%1"=="" color 4f&cls&echo.&echo [2] BALANCED ^& POWERPLAY OFF are set!
    goto quit
)

if not exist %SRC%emsx_top.qsf.balanced.off (
    ren %SRC%emsx_top.qsf emsx_top.qsf.balanced.off >nul 2>nul
    ren %SRC%emsx_top.qsf.balanced.normal emsx_top.qsf >nul 2>nul
    if "%1"=="" color 6f&cls&echo.&echo [B] BALANCED ^& NORMAL COMPILATION are set!
    goto quit
)

if not exist %SRC%emsx_top.qsf.balanced.normal (
    ren %SRC%emsx_top.qsf emsx_top.qsf.balanced.normal >nul 2>nul
    ren %SRC%emsx_top.qsf.balanced.extraeffort emsx_top.qsf >nul 2>nul
    if "%1"=="" color 2f&cls&echo.&echo [Y] BALANCED ^& EXTRA EFFORT are set!
    goto quit
)

:err_msg
if "%1"=="" color f0
echo.&echo This action is not allowed when the Multi-Release is in progress!
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul

:quit
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul
