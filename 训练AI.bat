@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo  椅子大逃亡 - AI 离线训练（追捕者 + 躲藏者）
echo ============================================
echo.

set PY=python
where python >nul 2>nul || set PY=py

echo [1/2] 训练追捕者 Tagger ...
%PY% rl/train_pathfinder.py --map maps/ring_training.json --out rl/trained_policy.json
if errorlevel 1 echo   （追捕者训练达标率未通过阈值，但策略文件已生成）

echo.
echo [2/2] 训练躲藏者 Runner ...
%PY% rl/train_runner.py --map maps/ring_training.json --out rl/trained_runner_policy.json
if errorlevel 1 echo   （躲藏者训练达标率未通过阈值，但策略文件已生成）

echo.
echo 训练完成。策略文件位于 rl\ 目录，重新运行游戏即可生效。
pause
