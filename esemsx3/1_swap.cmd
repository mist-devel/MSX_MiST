@echo off
rem --- '1_swap.cmd' v2.3 by KdL (2018.07.27)

set TIMEOUT=1
if "%1"=="" color 87&title SWAP
pof2pld emsx_top.pof emsx_top.pld >nul 2>nul
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
if exist emsx_top.pof del recovery.pof >nul 2>nul
ren emsx_top.pof recovery.pof >nul 2>nul

:zemmixneo
if not exist emsx_top_304k.hex.backslash.zemmixneo goto msx2plus
ren emsx_top_304k.hex emsx_top_304k.hex.backslash.msx2plus
ren emsx_top_304k.hex.backslash.zemmixneo emsx_top_304k.hex
if exist emsx_top.pld ren emsx_top.pld emsx_top.pld.1chipmsx >nul 2>nul
if exist recovery.pof ren recovery.pof recovery.pof.1chipmsx >nul 2>nul
if exist emsx_top.fit.summary ren emsx_top.fit.summary emsx_top.fit.summary.1chipmsx >nul 2>nul
del "__1chipmsx__"
rem.>"__zemmixneo__"
cd src\peripheral\
ren swioports.vhd swioports.vhd.1chipmsx >nul 2>nul
ren swioports.vhd.japanese swioports.vhd.japanese.1chipmsx >nul 2>nul
ren swioports.vhd.zemmixneo swioports.vhd >nul 2>nul
ren swioports.vhd.japanese.zemmixneo swioports.vhd.japanese >nul 2>nul

if "%1"=="" cls&color 4f&echo.&echo Zemmix Neo is ready to compile!
goto timer

:msx2plus
if not exist emsx_top_304k.hex.backslash.msx2plus goto err_msg
ren emsx_top_304k.hex emsx_top_304k.hex.backslash.zemmixneo
ren emsx_top_304k.hex.backslash.msx2plus emsx_top_304k.hex
if exist emsx_top.pld ren emsx_top.pld emsx_top.pld.zemmixneo >nul 2>nul
if exist recovery.pof ren recovery.pof recovery.pof.zemmixneo >nul 2>nul
if exist emsx_top.fit.summary ren emsx_top.fit.summary emsx_top.fit.summary.zemmixneo >nul 2>nul
del "__zemmixneo__"
rem.>"__1chipmsx__"
cd src\peripheral\
ren swioports.vhd swioports.vhd.zemmixneo >nul 2>nul
ren swioports.vhd.japanese swioports.vhd.japanese.zemmixneo >nul 2>nul
ren swioports.vhd.1chipmsx swioports.vhd >nul 2>nul
ren swioports.vhd.japanese.1chipmsx swioports.vhd.japanese >nul 2>nul

if "%1"=="" cls&color 1f&echo.&echo 1chipMSX is ready to compile!  ^(default^)
goto timer

:err_msg
if "%1"=="" color f0
echo.&echo 'emsx_top_304k.hex.backslash.???' not found!

:timer
if "%1"=="" waitfor /T %TIMEOUT% pause >nul 2>nul

:quit
