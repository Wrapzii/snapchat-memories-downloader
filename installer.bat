@echo off
REM Snapchat Memories Downloader - Windows Installer
REM This script checks and installs necessary dependencies

echo ==========================================
echo Snapchat Memories Downloader - Installer
echo ==========================================
echo.

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo NOTE: Some installations may require administrator privileges.
    echo If installation fails, try running as administrator.
    echo.
)

REM Check for PowerShell
echo [1/2] Checking PowerShell...
where powershell >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: PowerShell not found!
    echo PowerShell is required for this script.
    pause
    exit /b 1
) else (
    echo SUCCESS: PowerShell is available!
    powershell -Command "Write-Host 'PowerShell Version:' $PSVersionTable.PSVersion.ToString()" 2>nul
)
echo.

REM Check for ExifTool
echo [2/2] Checking ExifTool...
where exiftool >nul 2>&1
if %errorLevel% neq 0 (
    echo WARNING: ExifTool not found!
    echo.
    echo ExifTool is required to write metadata to your photos and videos.
    echo Without it, files will be downloaded but won't have correct dates/GPS.
    echo.
    echo To install ExifTool:
    echo 1. Download from: https://exiftool.org/
    echo 2. Extract exiftool(-k).exe and rename to exiftool.exe
    echo 3. Place it in one of these folders:
    echo    - Same folder as this script
    echo    - C:\Windows\System32
    echo    - Or add its location to your PATH
    echo.
    echo Would you like to open the download page now?
    choice /C YN /M "Open download page"
    if errorlevel 2 goto skip_exiftool
    if errorlevel 1 start https://exiftool.org/
    :skip_exiftool
) else (
    echo SUCCESS: ExifTool is installed!
    exiftool -ver 2>nul | more
)
echo.

REM Installation complete
echo ==========================================
echo Installation Check Complete!
echo ==========================================
echo.
echo Next Steps:
echo.
echo 1. Request your Snapchat data:
echo    - Go to: https://accounts.snapchat.com
echo    - Click "My Data"
echo    - Select "Export your Memories" and "Request Only Memories"
echo    - Select "All Time"
echo    - Confirm email and submit
echo    - Wait for email with download link
echo.
echo 2. Download the memories_history.html file from Snapchat
echo    Place it in the same folder as the PowerShell scripts
echo.
echo 3. Run the downloader script:
echo    powershell -ExecutionPolicy Bypass -File snapchat-downloader.ps1
echo.
echo 4. (Optional) Add GPS location metadata:
echo    powershell -ExecutionPolicy Bypass -File metadata.ps1
echo.
echo 5. (Optional) Remove duplicates from extracted folders:
echo    powershell -ExecutionPolicy Bypass -File delete-dupes.ps1
echo.
echo ==========================================
echo.

pause
