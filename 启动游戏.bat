@echo off
setlocal EnableExtensions

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "PROJECT_FILE=%PROJECT_DIR%\project.godot"

if not exist "%PROJECT_FILE%" goto no_project

call :find_godot
if not defined GODOT_EXE goto no_godot

echo Using: "%GODOT_EXE%"
echo Project: "%PROJECT_DIR%"
echo Launching game...
"%GODOT_EXE%" --path "%PROJECT_DIR%"
if errorlevel 1 goto run_failed
exit /b 0

:find_godot
if defined GODOT_EXE if exist "%GODOT_EXE%" exit /b 0
if exist "%PROJECT_DIR%\Godot_v4.7.1-stable_win64.exe" set "GODOT_EXE=%PROJECT_DIR%\Godot_v4.7.1-stable_win64.exe" & exit /b 0
if exist "D:\NeonSalvager3D\tools\Godot_v4.7.1-stable_win64.exe" set "GODOT_EXE=D:\NeonSalvager3D\tools\Godot_v4.7.1-stable_win64.exe" & exit /b 0
if exist "%USERPROFILE%\Downloads\Godot_v4.7.1-stable_win64.exe" set "GODOT_EXE=%USERPROFILE%\Downloads\Godot_v4.7.1-stable_win64.exe" & exit /b 0
if exist "%USERPROFILE%\Desktop\Godot_v4.7.1-stable_win64.exe" set "GODOT_EXE=%USERPROFILE%\Desktop\Godot_v4.7.1-stable_win64.exe" & exit /b 0
for %%I in (godot4.exe godot4 godot.exe godot) do (
    for /f "delims=" %%P in ('where %%I 2^>nul') do (
        set "GODOT_EXE=%%P"
        exit /b 0
    )
)
set "GODOT_EXE="
exit /b 1

:no_project
echo project.godot not found. Put this BAT in your Godot project root.
pause
exit /b 1

:no_godot
echo Godot executable not found.
echo You can put Godot next to this project, add it to PATH, or set GODOT_EXE before running.
pause
exit /b 1

:run_failed
echo Godot exited with error code %errorlevel%.
pause
exit /b %errorlevel%
