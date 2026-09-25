@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

set "MODE=%1"
if "%MODE%"=="" set "MODE=full"
if not "%MODE%"=="full" if not "%MODE%"=="slim" if not "%MODE%"=="nodaily" (
  echo Usage: backup.bat [full^|slim^|nodaily]
  echo   full    - code+models+data+_onsides to ..\
  echo   slim    - code+models+data, no _onsides
  echo   nodaily - full minus DailyMed archives, skips us download and labelzips
  goto end
)

where 7z >nul 2>nul
if errorlevel 1 set "PATH=C:\Program Files\7-Zip;%PATH%"
where 7z >nul 2>nul
if errorlevel 1 (
  echo [ERROR] 7-Zip not found. Run winget-install-all.bat first.
  goto end
)

for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "STAMP=%%t"
set "OUT=..\Onsides_%MODE%_%STAMP%.zip"

set "EXCL=%TEMP%\onsides_exclude.txt"
(
  echo .env
  echo cloudflared.exe
  echo *.lnk
  echo ssh-*.bat
  echo tai-cloudflared.bat
  echo New Text Document.txt
) > "%EXCL%"
if "%MODE%"=="slim" echo _onsides>> "%EXCL%"
if "%MODE%"=="nodaily" (
  echo _onsides\us\download\>> "%EXCL%"
  echo _onsides\us\labelzips\>> "%EXCL%"
  echo _onsides\*.zip>> "%EXCL%"
)

echo [1/3] Zipping %MODE% to %OUT% ...
rem 7z cannot update huge zip archives - always create fresh
if exist "%OUT%" del "%OUT%"
7z a -tzip -mx=1 "%OUT%" "." "-xr@%EXCL%"
if errorlevel 1 (
  echo [ERROR] 7z failed.
  goto end
)

echo.
echo [2/3] Checking G:\My Drive space ...
if not exist "G:\My Drive\" (
  echo [SKIP] G:\My Drive not found. Zip kept at %OUT%.
  goto end
)
for /f %%s in ('powershell -NoProfile -Command "(Get-Item '%OUT%').Length"') do set "ZSIZE=%%s"
for /f %%f in ('powershell -NoProfile -Command "(Get-PSDrive G).Free"') do set "GFREE=%%f"
echo Zip bytes: %ZSIZE%, G: free bytes: %GFREE%
for /f %%r in ('powershell -NoProfile -Command "if (%ZSIZE% -lt %GFREE%) {'FIT'} else {'NOFIT'}"') do set "FIT=%%r"
if not "%FIT%"=="FIT" (
  echo [SKIP] Zip does not fit on G:. Free space or use slim mode.
  echo   Zip kept at %OUT%.
  goto end
)

echo.
echo [3/3] Copying to G:\My Drive ...
copy /y "%OUT%" "G:\My Drive\" >nul
if errorlevel 1 (
  echo [ERROR] Copy failed.
  goto end
)
for /f %%c in ('powershell -NoProfile -Command "(Get-Item 'G:\My Drive\%~nxOUT%' 2>$null).Length"') do set "CSIZE=%%c"
echo Source: %ZSIZE% bytes, Copy: %CSIZE% bytes
if not "%ZSIZE%"=="%CSIZE%" (
  echo [ERROR] Size mismatch after copy.
  goto end
)
echo OK: G:\My Drive\%~nxOUT%

:end
echo.
pause
