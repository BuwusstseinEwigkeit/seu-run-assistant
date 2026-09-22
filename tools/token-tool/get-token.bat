@echo off
title SEU Run Assistant Token Bridge
echo.
echo   ==================================================
echo    SEU Run Assistant local token bridge
echo   --------------------------------------------------
echo    1. Keep this window open
echo    2. Open the mini-program in WeChat
echo    3. Click Extract Token in the web page
echo   ==================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bridge_server.ps1"
echo.
echo   Bridge stopped.
pause
