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
echo 正在启动房主客户端...
start "ParkourTag Host" "%GODOT_EXE%" --path "%PROJECT_DIR%"

timeout /t 1 /nobreak >nul

echo 正在启动加入客户端...
start "ParkourTag Client" "%GODOT_EXE%" --path "%PROJECT_DIR%"

echo 已启动两个客户端。
echo 一个选择“创建联机房间”，另一个输入 127.0.0.1 后选择“加入联机房间”。
timeout /t 3 /nobreak >nul
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
echo 未找到 Godot 可执行文件。
echo 你可以把 Godot 放到项目目录、加入 PATH，或先设置 GODOT_EXE 环境变量。
pause
exit /b 1
