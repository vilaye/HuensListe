@echo off
rem Double-click to install or update Huens Liste from GitHub.
rem Keep this file and Update-HuensListe.ps1 together, but NOT inside the HuensListe addon folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-HuensListe.ps1" %*
echo.
pause
