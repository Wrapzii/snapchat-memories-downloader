@echo off
REM Simple wrapper to add GPS metadata to downloaded files

echo.
echo ==========================================
echo Add GPS Location Metadata
echo ==========================================
echo.

REM Check if downloaded_files.json exists
if not exist "downloaded_files.json" (
    echo ERROR: downloaded_files.json not found!
    echo.
    echo Please run the downloader first.
    echo.
    pause
    exit /b 1
)

REM Check if memories_history.html exists
if not exist "memories_history.html" (
    echo ERROR: memories_history.html not found!
    echo.
    echo The HTML file is needed to extract GPS coordinates.
    echo.
    pause
    exit /b 1
)

echo Adding GPS metadata to files...
echo.

REM Run the PowerShell script
powershell -ExecutionPolicy Bypass -File metadata.ps1

echo.
pause
