@echo off
setlocal
cd /d "%~dp0"
echo === OnSIDES full winget set ===
echo Run this in Admin PowerShell/cmd for Docker + WSL parts.
echo.

set "FLAGS=--accept-package-agreements --accept-source-agreements --silent --source winget"

call :inst Git.Git "Git"
call :inst Docker.DockerDesktop "Docker Desktop"
call :inst Microsoft.VisualStudioCode "VS Code - close VS Code before upgrade"
call :inst Microsoft.WindowsTerminal "Windows Terminal"
call :inst Python.Python.3.12 "Python 3.12 host utils"
call :inst 7zip.7zip "7-Zip"
call :inst Notepad++.Notepad++ "Notepad++"
call :inst Nvidia.CUDA "NVIDIA CUDA Toolkit optional"

echo.
echo --- WSL2 + Ubuntu [not winget, needs Admin + reboot] ---
echo This old inbox WSL only lists "Ubuntu", not "Ubuntu-22.04".
wsl --list --online
wsl -l -v
if errorlevel 1 (
  echo Installing WSL2 + Ubuntu...
  wsl --install -d Ubuntu
) else (
  echo WSL OK. Updating kernel...
  wsl --update
)

echo.
echo --- Versions ---
git --version
docker --version
docker compose version
"%LocalAppData%\Programs\Python\Python312\python.exe" --version
where python
nvidia-smi --query-gpu=name,driver_version --format=csv
echo.
echo Done. Next: onsides.bat build
echo.
pause
goto :eof

:inst
echo.
echo [winget] %~2 (%~1)
winget install --id %~1 -e %FLAGS%
if errorlevel 1 (
  echo  -^> install/upgrade returned %errorlevel% ^(may already exist^)
) else (
  echo  -^> OK
)
goto :eof
