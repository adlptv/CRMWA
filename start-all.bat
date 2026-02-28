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

echo.
echo All workers started! Check taskbar for 6 PowerShell windows.
echo Press any key to exit this window...
pause >nul
