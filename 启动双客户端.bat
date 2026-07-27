@echo off
setlocal

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "GODOT_EXE=C:\Users\p_qiwenxu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

if not exist "%GODOT_EXE%" (
    echo 未找到 Godot：%GODOT_EXE%
    echo 请检查 Godot 路径，或编辑本脚本里的 GODOT_EXE。
    pause
    exit /b 1
)

echo 正在启动房主客户端...
start "ParkourTag Host" "%GODOT_EXE%" --path "%PROJECT_DIR%"

timeout /t 1 /nobreak >nul

echo 正在启动加入客户端...
start "ParkourTag Client" "%GODOT_EXE%" --path "%PROJECT_DIR%"

echo 已启动两个客户端。
echo 一个选择“创建联机房间”，另一个输入 127.0.0.1 后选择“加入联机房间”。
timeout /t 3 /nobreak >nul
