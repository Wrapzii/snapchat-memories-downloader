@echo off
REM Simple wrapper to remove duplicate files

echo.
echo ==========================================
echo Delete Duplicate Files
echo ==========================================
echo.

REM Check if snapchat_memories folder exists
if not exist "snapchat_memories" (
    echo ERROR: snapchat_memories folder not found!
    echo.
    echo Please run the downloader first.
    echo.
    pause
    exit /b 1
)

echo This will remove duplicate files from extracted ZIP folders.
echo First, a preview will be shown (DRY RUN).
echo.
pause

echo.
echo Running preview (DRY RUN)...
echo.

REM Run in dry-run mode first
powershell -ExecutionPolicy Bypass -File delete-dupes.ps1 -DryRun $true

echo.
echo ==========================================
echo.
echo To actually delete the duplicates, run:
echo    powershell -ExecutionPolicy Bypass -File delete-dupes.ps1 -DryRun $false
echo.
echo Or edit this batch file and remove the -DryRun parameter.
echo.
pause
