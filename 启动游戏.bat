@echo off
setlocal

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "PROJECT_FILE=%PROJECT_DIR%\project.godot"
set "GODOT_EXE=D:\NeonSalvager3D\tools\Godot_v4.7.1-stable_win64.exe"

if not exist "%PROJECT_FILE%" goto no_project
if not exist "%GODOT_EXE%" goto no_godot

echo Using: "%GODOT_EXE%"
echo Project: "%PROJECT_DIR%"
echo Launching game...

"%GODOT_EXE%" --path "%PROJECT_DIR%"
if errorlevel 1 goto run_failed
exit /b 0

:no_project
echo project.godot not found. Put this BAT in your Godot project root.
pause
exit /b 1

:no_godot
echo Godot executable not found at:
echo %GODOT_EXE%
pause
exit /b 1

:run_failed
echo Godot exited with error code %errorlevel%.
pause
exit /b %errorlevel%
