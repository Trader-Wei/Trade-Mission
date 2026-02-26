@echo off
chcp 65001 >nul
cd /d "c:\src\anya_trade_app"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\bingobingo_bot\deploy-to-ec2.ps1"
pause
