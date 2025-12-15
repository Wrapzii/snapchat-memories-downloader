# Delete Duplicates - Remove duplicate files in extracted ZIP folders
# Script to detect and remove duplicates in unpacked ZIP folders

param(
    [bool]$DryRun = $true
)

# Configuration
$DOWNLOAD_FOLDER = 'snapchat_memories'

# Calculate file hash
function Get-FileHashSHA256 {
    param([string]$filepath)
    
    try {
        $hash = Get-FileHash -Path $filepath -Algorithm SHA256
        return $hash.Hash
    }
    catch {
        Write-Host "Error calculating hash for $filepath : $_" -ForegroundColor Red
        return $null
    }
}

# Find duplicates in folder
function Find-DuplicatesInFolder {
    param([string]$folderPath)
    
    $files = Get-ChildItem -Path $folderPath -File
    
    if ($files.Count -lt 2) {
        return @()
    }
    
    # Calculate hashes for all files
    $fileHashes = @{}
    foreach ($file in $files) {
        $hash = Get-FileHashSHA256 -filepath $file.FullName
        if ($hash) {
            if (-not $fileHashes.ContainsKey($hash)) {
                $fileHashes[$hash] = @()
            }
            $fileHashes[$hash] += $file.FullName
        }
    }
    
    # Find duplicates (hash with multiple files)
    $duplicates = @()
    foreach ($hash in $fileHashes.Keys) {
        $filepaths = $fileHashes[$hash]
        if ($filepaths.Count -gt 1) {
            # Sort: Keep the file that matches folder name
            $folderName = Split-Path $folderPath -Leaf
            
            # Extract UUID/ID from folder name (Format: YYYYMMDD_HHMMSS_UUID)
            $folderUuid = if ($folderName -match '_') {
                $folderName -split '_', 3 | Select-Object -Last 1
            }
            else {
                $folderName
            }
            
            $primary = $null
            $toDelete = @()
            
            foreach ($filepath in $filepaths) {
                $filename = Split-Path $filepath -Leaf
                # Check if filename starts with folder UUID
                if ($filename -match "^$folderUuid") {
                    $primary = $filepath
                }
                else {
                    $toDelete += $filepath
                }
            }
            
            # If no match with folder UUID, keep the first file
            if ($null -eq $primary) {
                $primary = $filepaths[0]
                $toDelete = $filepaths[1..($filepaths.Count - 1)]
            }
            
            if ($toDelete.Count -gt 0) {
                $duplicates += @{
                    hash = $hash
                    keep = $primary
                    delete = $toDelete
                }
            }
        }
    }
    
    return $duplicates
}

# Process folders
function Process-Folders {
    param(
        [string]$directory,
        [bool]$dryRun = $true
    )
    
    if (-not (Test-Path $directory)) {
        Write-Host "ERROR: Folder '$directory' does not exist!" -ForegroundColor Red
        return
    }
    
    $foldersWithDuplicates = @()
    $totalDuplicates = 0
    $deletedCount = 0
    
    # Search all subfolders
    Get-ChildItem -Path $directory -Directory | ForEach-Object {
        $duplicates = Find-DuplicatesInFolder -folderPath $_.FullName
        
        if ($duplicates.Count -gt 0) {
            $foldersWithDuplicates += @{
                folder = $_.Name
                path = $_.FullName
                duplicates = $duplicates
            }
            
            # Count all files to delete
            foreach ($dup in $duplicates) {
                $totalDuplicates += $dup.delete.Count
            }
        }
    }
    
    if ($foldersWithDuplicates.Count -eq 0) {
        Write-Host "No duplicates found!" -ForegroundColor Green
        return
    }
    
    Write-Host "$($foldersWithDuplicates.Count) folders with duplicates found" -ForegroundColor Yellow
    Write-Host "Total $totalDuplicates duplicates to delete`n" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    
    # Process each folder
    foreach ($folderInfo in $foldersWithDuplicates) {
        $folderName = $folderInfo.folder
        $duplicates = $folderInfo.duplicates
        
        Write-Host "$folderName/" -ForegroundColor Cyan
        Write-Host "   Found: $($duplicates.Count) duplicate group(s)" -ForegroundColor Yellow
        Write-Host ""
        
        foreach ($dup in $duplicates) {
            $keepFile = Split-Path $dup.keep -Leaf
            Write-Host "   [KEEP] $keepFile" -ForegroundColor Green
            
            foreach ($deleteFile in $dup.delete) {
                $deleteFilename = Split-Path $deleteFile -Leaf
                Write-Host "   [DELETE] $deleteFilename" -ForegroundColor Red
                
                if (-not $dryRun) {
                    try {
                        Remove-Item $deleteFile -Force
                        $deletedCount++
                        Write-Host "      -> Deleted!" -ForegroundColor DarkGray
                    }
                    catch {
                        Write-Host "      ERROR: $_" -ForegroundColor Red
                    }
                }
            }
            
            Write-Host ""
        }
        
        Write-Host ("-" * 80) -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # Summary
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    if ($dryRun) {
        Write-Host "DRY RUN MODE - No files deleted!" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Folders with duplicates: $($foldersWithDuplicates.Count)"
        Write-Host "Files to delete: $totalDuplicates" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To delete the duplicates:" -ForegroundColor Cyan
        Write-Host "   Run the script with: -DryRun `$false" -ForegroundColor Cyan
    }
    else {
        Write-Host "Successfully deleted: $deletedCount files" -ForegroundColor Green
        if ($deletedCount -lt $totalDuplicates) {
            Write-Host "Errors: $($totalDuplicates - $deletedCount) files" -ForegroundColor Red
        }
    }
}

# Main
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Deduplicate ZIP Folder Contents" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN MODE - Preview only, no changes" -ForegroundColor Yellow
    Write-Host ""
}
else {
    Write-Host "WARNING: Duplicates will be actually deleted!" -ForegroundColor Red
    $response = Read-Host "Continue? (y/n)"
    if ($response -notin @('y', 'Y', 'yes', 'Yes')) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }
    Write-Host ""
}

Process-Folders -directory $DOWNLOAD_FOLDER -dryRun $DryRun
