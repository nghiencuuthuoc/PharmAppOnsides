@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set "GITBIN=C:\Program Files\Git\cmd"
if exist "%GITBIN%\git.exe" set "PATH=%GITBIN%;%PATH%"

if "%1"=="" goto menu
goto %1 2>nul || goto usage

:menu
echo.
echo OnSIDES Docker quick run
echo   onsides.bat build      - build pipeline image
echo   onsides.bat gpu        - test nvidia-smi + torch cuda
echo   onsides.bat up         - up pipeline + postgres + mysql
echo   onsides.bat shell      - exec bash in pipeline
echo   onsides.bat test       - pytest 71 tests in container
echo   onsides.bat db         - up postgres + mysql only
echo   onsides.bat annotator  - up annotator on :8000
echo   onsides.bat ps         - compose ps
echo   onsides.bat logs       - compose logs tail
echo   onsides.bat down       - stop all
echo.
goto end

:usage
echo Unknown command: %1
goto menu

:check_docker
where docker >nul 2>nul
if errorlevel 1 (
  echo [ERROR] docker not found. Run setup.bat first, start Docker Desktop.
  exit /b 1
)
docker info >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Docker Desktop not running. Start Docker Desktop and retry.
  exit /b 1
)
exit /b 0

:build
call :check_docker || goto end
docker compose build pipeline
goto end

:gpu
call :check_docker || goto end
docker run --rm --gpus all onsides-pipeline:cu128 nvidia-smi
docker run --rm --gpus all onsides-pipeline:cu128 python3.12 -c "import torch; print(torch.__version__, torch.cuda.is_available())"
goto end

:up
call :check_docker || goto end
docker compose up -d pipeline postgres mysql
docker compose ps
goto end

:shell
call :check_docker || goto end
docker compose up -d pipeline >nul
docker compose exec pipeline bash
goto end

:test
call :check_docker || goto end
docker compose up -d pipeline >nul
docker compose exec pipeline pytest src/onsides/ -q
goto end

:db
call :check_docker || goto end
docker compose up -d postgres mysql
docker compose ps
goto end

:annotator
call :check_docker || goto end
docker compose --profile annotator up -d annotator
echo Open http://localhost:8000
goto end

:ps
docker compose ps
goto end

:logs
docker compose logs --tail=100 -f
goto end

:down
docker compose --profile annotator down
goto end

:end
echo.
pause
