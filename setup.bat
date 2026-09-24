@echo off
setlocal
cd /d "%~dp0"
echo === OnSIDES one-time setup (run as Admin for WSL part) ===
echo.

where git >nul 2>nul
if errorlevel 1 (
  echo [1/4] Installing Git...
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent
) else (
  echo [1/4] Git OK
  git --version
)

echo.
echo [2/4] WSL2 + Ubuntu-22.04 (needs Admin + reboot if first time)
wsl -l -v
if errorlevel 1 (
  echo  -^> Run in Admin PowerShell: wsl --install -d Ubuntu-22.04
) else (
  echo  -^> WSL list OK. If no Ubuntu, run: wsl --install -d Ubuntu-22.04
)

echo.
echo [3/4] Docker Desktop
where docker >nul 2>nul
if errorlevel 1 (
  echo  -^> Installing Docker Desktop...
  winget install --id Docker.DockerDesktop -e --source winget --accept-package-agreements --accept-source-agreements --silent
) else (
  echo  -^> Docker found:
  docker --version
  docker compose version
)

echo.
echo [4/4] GPU check
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
echo.
echo Next: onsides.bat build ^&^& onsides.bat gpu ^&^& onsides.bat up
echo.
pause
