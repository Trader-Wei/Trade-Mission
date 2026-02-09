@echo off
REM 一鍵同步到 GitHub（會自動 add、commit、push，然後 GitHub Actions 會自動部署網頁）
cd /d "%~dp0"
git add .
git commit -m "sync %date% %time%" 2>nul || git commit -m "sync"
git push origin main
pause
