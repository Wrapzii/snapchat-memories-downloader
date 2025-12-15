@echo off
REM Simple wrapper to run the Snapchat downloader PowerShell script
REM No need to type the full PowerShell command!

echo.
echo ==========================================
echo Snapchat Memories Downloader
echo ==========================================
echo.

REM Check if memories_history.html exists
if not exist "memories_history.html" (
    echo ERROR: memories_history.html not found!
    echo.
    echo Please download your Snapchat data and place the memories_history.html file
    echo in the same folder as this script.
    echo.
    echo Instructions:
    echo 1. Go to https://accounts.snapchat.com
    echo 2. Click "My Data"
    echo 3. Select "Export your Memories" and "Request Only Memories"
    echo 4. Download the memories_history.html file
    echo 5. Place it in this folder
    echo.
    pause
    exit /b 1
)

echo Starting download...
echo.

REM Run the PowerShell script
powershell -ExecutionPolicy Bypass -File snapchat-downloader.ps1

echo.
echo ==========================================
echo Download Complete!
echo ==========================================
echo.
pause
