@echo off
echo Starting AI Agent Loop Workers...
echo.

start "Controller" powershell -NoExit -NoProfile -File "%~dp0controller.ps1" -SkipClone
timeout /t 2 >nul

start "Bugfix Worker" powershell -NoExit -NoProfile -File "%~dp0worker-bugfix.ps1"
timeout /t 2 >nul

start "Coverage Worker" powershell -NoExit -NoProfile -File "%~dp0worker-coverage.ps1"
timeout /t 2 >nul

start "Refactor Worker" powershell -NoExit -NoProfile -File "%~dp0worker-refactor.ps1"
timeout /t 2 >nul

start "Lint Worker" powershell -NoExit -NoProfile -File "%~dp0worker-lint.ps1"
timeout /t 2 >nul

start "Doc Worker" powershell -NoExit -NoProfile -File "%~dp0worker-doc.ps1"
timeout /t 2 >nul

start "Feature Worker" powershell -NoExit -NoProfile -File "%~dp0worker-feature.ps1"
timeout /t 2 >nul

start "Ideate Worker" powershell -NoExit -NoProfile -File "%~dp0worker-ideate.ps1"

echo.
echo All 8 workers started! Check taskbar for PowerShell windows.
echo Workers: Controller, Bugfix, Coverage, Refactor, Lint, Doc, Feature, Ideate
echo Press any key to exit this window...
pause >nul
