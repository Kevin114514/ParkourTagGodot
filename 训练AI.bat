@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo  椅子大逃亡 - AI 离线训练（追捕者 + 躲藏者）
echo ============================================
echo.

set PY=python
where python >nul 2>nul || set PY=py

echo [1/1] 双 AI 自博弈 RL v2（命中 10 次 / 限时 300 秒）...
%PY% rl/train_selfplay.py --duration-seconds 300 --hits-to-win 10 --round-seconds 300 --progress-interval 15 --tagger-out rl/trained_policy.json --runner-out rl/trained_runner_policy.json
if errorlevel 1 goto train_failed

echo.
echo 训练完成。策略文件位于 rl\ 目录，重新运行游戏即可生效。
pause
exit /b 0

:train_failed
echo 训练失败，错误代码 %errorlevel%。
pause
exit /b %errorlevel%
