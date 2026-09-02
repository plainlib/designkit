@echo off
setlocal EnableDelayedExpansion

set "RC=src\designkit.rc"
set "LRS=src\designkit.lrs"
set "LIST=%TEMP%\lazres.lst"

if exist "%LIST%" del "%LIST%"

for /f "usebackq tokens=1,2,*" %%A in ("%RC%") do (
    if /I "%%B"=="RCDATA" (
        set "FILE=%%~C"
        set "FILE=!FILE:"=!"
        set "FILE=!FILE:/=\!"
        echo !FILE!>>"%LIST%"
    )
)

C:\lazarus\tools\lazres.exe "%LRS%" @"%LIST%"

del "%LIST%"