# Snapchat Memories Downloader - PowerShell Version
# Downloads all memories from Snapchat's HTML export file

param(
    [int]$MaxWorkers = 5,
    [bool]$TestMode = $false,
    [int]$TestFilesPerThread = 5,
    [bool]$UseExifTool = $true
)

# ---------------- CONFIG ----------------
$HTML_FILE = 'memories_history.html'
$DOWNLOAD_FOLDER = 'snapchat_memories'
$LOG_FILE = 'downloaded_files.json'
$ERROR_LOG_FILE = 'download_errors.json'
# ----------------------------------------

# Create download folder
if (-not (Test-Path $DOWNLOAD_FOLDER)) {
    New-Item -ItemType Directory -Path $DOWNLOAD_FOLDER | Out-Null
}

# Thread-safe locks
$jsonLock = [System.Threading.Mutex]::new($false, "JsonLock")
$errorLock = [System.Threading.Mutex]::new($false, "ErrorLock")

# Load already downloaded files
$downloadedFiles = @{}
if (Test-Path $LOG_FILE) {
    $downloadedFiles = Get-Content $LOG_FILE -Raw | ConvertFrom-Json -AsHashtable
    if ($downloadedFiles -eq $null) { $downloadedFiles = @{} }
}

# Load error log
$errorLog = @{}
if (Test-Path $ERROR_LOG_FILE) {
    $errorLog = Get-Content $ERROR_LOG_FILE -Raw | ConvertFrom-Json -AsHashtable
    if ($errorLog -eq $null) { $errorLog = @{} }
}

# Check if exiftool is available
function Test-ExifTool {
    try {
        $null = & exiftool -ver 2>&1
        return $true
    }
    catch {
        return $false
    }
}

$exiftoolAvailable = if ($UseExifTool) { Test-ExifTool } else { $false }
if ($UseExifTool -and -not $exiftoolAvailable) {
    Write-Host "WARNING: exiftool not found. Metadata will not be written." -ForegroundColor Yellow
    Write-Host "Installation: https://exiftool.org/" -ForegroundColor Yellow
}
elseif ($exiftoolAvailable) {
    Write-Host "exiftool found - Metadata will be written to files." -ForegroundColor Green
}

# Read and parse HTML
if (-not (Test-Path $HTML_FILE)) {
    Write-Host "ERROR: '$HTML_FILE' not found!" -ForegroundColor Red
    exit 1
}

$htmlContent = Get-Content $HTML_FILE -Raw -Encoding UTF8

# Extract download URLs using regex
$pattern = "downloadMemories\('(.+?)',\s*this,\s*(true|false)\)"
$matches = [regex]::Matches($htmlContent, $pattern)

Write-Host "Found $($matches.Count) files to process" -ForegroundColor Cyan

# Extract dates from HTML table
function Get-DatesFromTable {
    param([string]$html)
    
    $dates = @()
    # Simple regex to extract dates from table cells
    # Format: YYYY-MM-DD HH:MM:SS UTC
    $datePattern = '(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+UTC)'
    $dateMatches = [regex]::Matches($html, $datePattern)
    
    foreach ($match in $dateMatches) {
        $dates += $match.Groups[1].Value
    }
    
    return $dates
}

$dates = Get-DatesFromTable -html $htmlContent
Write-Host "Found $($dates.Count) date entries" -ForegroundColor Cyan

# Extract unique ID from URL
function Get-UniqueIdFromUrl {
    param([string]$url)
    
    if ($url -match 'mid=([a-zA-Z0-9\-]+)') {
        return $Matches[1]
    }
    else {
        # Fallback: MD5 hash of URL
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($url))
        return [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()
    }
}

# Get file extension from URL
function Get-FileExtension {
    param([string]$url, [string]$contentType)
    
    # Try from URL first
    $urlPath = $url -split '\?' | Select-Object -First 1
    if ($urlPath -match '\.(mp4|jpg|jpeg|png|zip)$') {
        return $Matches[0]
    }
    
    # Fallback to content type
    if ($contentType) {
        if ($contentType -match 'video') { return '.mp4' }
        if ($contentType -match 'image/jpeg|image/jpg') { return '.jpg' }
        if ($contentType -match 'image/png') { return '.png' }
        if ($contentType -match 'zip') { return '.zip' }
    }
    
    return '.mp4' # Default fallback
}

# Build filename
function Build-Filename {
    param(
        [string]$uniqueId,
        [string]$dateStr = $null,
        [string]$contentType = $null,
        [string]$url = $null
    )
    
    $baseName = $uniqueId
    
    # Add date prefix if available
    if ($dateStr) {
        try {
            $dateCleaned = $dateStr.Trim() -replace '\s+UTC\s*$', ''
            $dt = [DateTime]::ParseExact($dateCleaned, 'yyyy-MM-dd HH:mm:ss', $null)
            $datePrefix = $dt.ToString('yyyyMMdd_HHmmss')
            $baseName = "${datePrefix}_${baseName}"
        }
        catch {
            # Date parsing failed, continue without date prefix
        }
    }
    
    # Determine extension
    $ext = Get-FileExtension -url $url -contentType $contentType
    $filename = $baseName + $ext
    $filepath = Join-Path $DOWNLOAD_FOLDER $filename
    
    return @{
        FilePath = $filepath
        FileName = $filename
    }
}

# Parse date string to DateTime
function Parse-DateString {
    param([string]$dateStr)
    
    if ([string]::IsNullOrWhiteSpace($dateStr)) {
        return $null
    }
    
    try {
        $dateCleaned = $dateStr.Trim() -replace '\s+UTC\s*$', ''
        $formats = @(
            'yyyy-MM-dd HH:mm:ss',
            'yyyy-MM-dd',
            'dd.MM.yyyy HH:mm:ss',
            'dd.MM.yyyy'
        )
        
        foreach ($fmt in $formats) {
            try {
                return [DateTime]::ParseExact($dateCleaned, $fmt, $null)
            }
            catch {
                continue
            }
        }
    }
    catch {
        return $null
    }
    
    return $null
}

# Write metadata to file using exiftool
function Write-MetadataToFile {
    param(
        [string]$filepath,
        [string]$dateStr,
        [bool]$silent = $false
    )
    
    if (-not $exiftoolAvailable -or [string]::IsNullOrWhiteSpace($dateStr)) {
        return $false
    }
    
    $dt = Parse-DateString -dateStr $dateStr
    if ($null -eq $dt) {
        return $false
    }
    
    try {
        $exifDate = $dt.ToString('yyyy:MM:dd HH:mm:ss')
        $fileExt = [System.IO.Path]::GetExtension($filepath).ToLower()
        $filename = [System.IO.Path]::GetFileName($filepath)
        
        # Skip overlay and thumbnail files
        if ($filename -match '-overlay|thumbnail') {
            if (-not $silent) {
                Write-Host "[SKIP] Skipping metadata for: $filename" -ForegroundColor DarkGray
            }
            # Set file timestamps
            try {
                $file = Get-Item $filepath
                $file.CreationTime = $dt
                $file.LastWriteTime = $dt
            }
            catch { }
            return $false
        }
        
        if ($fileExt -in @('.jpg', '.jpeg', '.png')) {
            $result = & exiftool -overwrite_original -q `
                "-DateTimeOriginal=$exifDate" `
                "-CreateDate=$exifDate" `
                "-ModifyDate=$exifDate" `
                $filepath 2>&1
            
            if ($LASTEXITCODE -ne 0 -and -not $silent) {
                return $false
            }
        }
        elseif ($fileExt -in @('.mp4', '.mov', '.avi')) {
            $result = & exiftool -overwrite_original -q `
                "-CreateDate=$exifDate" `
                "-MediaCreateDate=$exifDate" `
                "-TrackCreateDate=$exifDate" `
                "-ModifyDate=$exifDate" `
                $filepath 2>&1
            
            if ($LASTEXITCODE -ne 0 -and -not $silent) {
                return $false
            }
        }
        
        # Set file system timestamps
        $file = Get-Item $filepath
        $file.CreationTime = $dt
        $file.LastWriteTime = $dt
        
        return $true
    }
    catch {
        if (-not $silent) {
            Write-Host "[METADATA] Could not write metadata for: $filename" -ForegroundColor Yellow
        }
        return $false
    }
}

# Extract and cleanup ZIP
function Expand-AndCleanupZip {
    param([string]$zipPath)
    
    try {
        $extractFolder = [System.IO.Path]::GetFileNameWithoutExtension($zipPath)
        $extractPath = Join-Path $DOWNLOAD_FOLDER $extractFolder
        
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Remove-Item $zipPath -Force
        
        Write-Host "[ZIP] Extracted and deleted: $([System.IO.Path]::GetFileName($zipPath))" -ForegroundColor Cyan
        return $extractPath
    }
    catch {
        Write-Host "[ZIP ERROR] Failed to extract $([System.IO.Path]::GetFileName($zipPath)): $_" -ForegroundColor Red
        return $null
    }
}

# Process files in folder (for extracted ZIPs)
function Process-FilesInFolder {
    param(
        [string]$folderPath,
        [string]$dateStr
    )
    
    if (-not (Test-Path $folderPath -PathType Container)) {
        return
    }
    
    $successCount = 0
    $skipCount = 0
    
    Get-ChildItem -Path $folderPath -Recurse -File | Where-Object {
        $_.Extension -match '\.(jpg|jpeg|png|mp4|mov|avi)$'
    } | ForEach-Object {
        $result = Write-MetadataToFile -filepath $_.FullName -dateStr $dateStr -silent $true
        if ($result) {
            $successCount++
        }
        else {
            $skipCount++
        }
    }
    
    if ($successCount -gt 0 -or $skipCount -gt 0) {
        Write-Host "[ZIP-CONTENT] $successCount files with metadata, $skipCount skipped" -ForegroundColor Cyan
    }
}

# Log error
function Write-ErrorLog {
    param(
        [string]$uniqueId,
        [string]$url,
        [string]$dateStr,
        [string]$errorMessage,
        [int]$index
    )
    
    $errorLock.WaitOne() | Out-Null
    try {
        $errorLog[$uniqueId] = @{
            url = $url
            date = $dateStr
            error = $errorMessage
            index = $index
            timestamp = (Get-Date).ToString('o')
        }
        
        $errorLog | ConvertTo-Json -Depth 10 | Set-Content $ERROR_LOG_FILE -Encoding UTF8
    }
    finally {
        $errorLock.ReleaseMutex()
    }
}

# Download file
function Get-MemoryFile {
    param(
        [string]$url,
        [bool]$isGet,
        [string]$dateStr = $null,
        [int]$index = 0
    )
    
    $uniqueId = Get-UniqueIdFromUrl -url $url
    
    # Skip if already downloaded
    if ($downloadedFiles.ContainsKey($uniqueId)) {
        Write-Host "[SKIP] $uniqueId already downloaded" -ForegroundColor DarkGray
        return @{ UniqueId = $uniqueId; Status = 'skipped' }
    }
    
    try {
        $headers = @{
            'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'
        }
        
        # Make request
        if ($isGet) {
            $response = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -UseBasicParsing
        }
        else {
            $parts = $url -split '\?', 2
            $postUrl = $parts[0]
            $postData = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            $response = Invoke-WebRequest -Uri $postUrl -Headers $headers -Method Post -Body $postData -UseBasicParsing
        }
        
        $contentType = $response.Headers['Content-Type']
        
        # Build filename
        $fileInfo = Build-Filename -uniqueId $uniqueId -dateStr $dateStr -contentType $contentType -url $url
        $filepath = $fileInfo.FilePath
        $filename = $fileInfo.FileName
        
        # Save file
        [System.IO.File]::WriteAllBytes($filepath, $response.Content)
        
        # Write metadata
        $metadataWritten = Write-MetadataToFile -filepath $filepath -dateStr $dateStr
        
        # Extract ZIP if needed
        if ($filepath -match '\.zip$') {
            $extractFolder = Expand-AndCleanupZip -zipPath $filepath
            if ($extractFolder) {
                Process-FilesInFolder -folderPath $extractFolder -dateStr $dateStr
            }
        }
        
        # Save to log
        $downloadedFiles[$uniqueId] = @{
            filename = $filename
            url = $url
            date = $dateStr
            content_type = $contentType
            metadata_written = $metadataWritten
            timestamp = (Get-Date).ToString('o')
        }
        
        Write-Host "[OK] $filename downloaded$(if ($metadataWritten) { ' (metadata written)' })" -ForegroundColor Green
        return @{ UniqueId = $uniqueId; Status = 'downloaded' }
    }
    catch {
        Write-Host "[ERROR] Download failed for $uniqueId (Index $index): $_" -ForegroundColor Red
        Write-ErrorLog -uniqueId $uniqueId -url $url -dateStr $dateStr -errorMessage $_.Exception.Message -index $index
        return @{ UniqueId = $uniqueId; Status = 'error' }
    }
}

# Save progress
function Save-Progress {
    $jsonLock.WaitOne() | Out-Null
    try {
        $downloadedFiles | ConvertTo-Json -Depth 10 | Set-Content $LOG_FILE -Encoding UTF8
        return $true
    }
    catch {
        Write-Host "[JSON ERROR] Failed to save: $_" -ForegroundColor Red
        return $false
    }
    finally {
        $jsonLock.ReleaseMutex()
    }
}

# Prepare download tasks
$downloadTasks = @()
for ($i = 0; $i -lt $matches.Count; $i++) {
    $match = $matches[$i]
    $url = $match.Groups[1].Value
    $isGet = $match.Groups[2].Value -eq 'true'
    $dateStr = if ($i -lt $dates.Count) { $dates[$i] } else { $null }
    
    $downloadTasks += @{
        Url = $url
        IsGet = $isGet
        DateStr = $dateStr
        Index = $i
    }
}

# Test mode
if ($TestMode) {
    $totalTestFiles = $MaxWorkers * $TestFilesPerThread
    $downloadTasks = $downloadTasks[0..([Math]::Min($totalTestFiles - 1, $downloadTasks.Count - 1))]
    Write-Host "`n*** TEST MODE ACTIVE: Only downloading $($downloadTasks.Count) files ($TestFilesPerThread per thread) ***`n" -ForegroundColor Yellow
}

# Statistics
Write-Host "`nAlready downloaded: $($downloadedFiles.Count) files" -ForegroundColor Cyan
Write-Host "Failed downloads: $($errorLog.Count) files" -ForegroundColor Cyan
Write-Host "To process: $($downloadTasks.Count) files`n" -ForegroundColor Cyan

# Download files with parallel processing
$completedCount = 0
$downloadedCount = 0
$skippedCount = 0
$errorCount = 0
$totalCount = $downloadTasks.Count

# Use runspaces for parallel downloads
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxWorkers)
$runspacePool.Open()
$jobs = @()

foreach ($task in $downloadTasks) {
    $powershell = [powershell]::Create()
    $powershell.RunspacePool = $runspacePool
    
    # Add script block with all necessary functions and variables
    [void]$powershell.AddScript({
        param($task, $functions, $vars)
        
        # Import functions
        . ([scriptblock]::Create($functions))
        
        # Call download function
        Get-MemoryFile -url $task.Url -isGet $task.IsGet -dateStr $task.DateStr -index $task.Index
    }).AddArgument($task).AddArgument(@"
function Get-UniqueIdFromUrl { param([string]`$url); if (`$url -match 'mid=([a-zA-Z0-9\-]+)') { return `$Matches[1] } else { `$md5 = [System.Security.Cryptography.MD5]::Create(); `$hash = `$md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(`$url)); return [System.BitConverter]::ToString(`$hash).Replace('-', '').ToLower() } }
function Get-FileExtension { param([string]`$url, [string]`$contentType); `$urlPath = `$url -split '\?' | Select-Object -First 1; if (`$urlPath -match '\.(mp4|jpg|jpeg|png|zip)$') { return `$Matches[0] }; if (`$contentType) { if (`$contentType -match 'video') { return '.mp4' }; if (`$contentType -match 'image/jpeg|image/jpg') { return '.jpg' }; if (`$contentType -match 'image/png') { return '.png' }; if (`$contentType -match 'zip') { return '.zip' } }; return '.mp4' }
function Build-Filename { param([string]`$uniqueId, [string]`$dateStr = `$null, [string]`$contentType = `$null, [string]`$url = `$null); `$baseName = `$uniqueId; if (`$dateStr) { try { `$dateCleaned = `$dateStr.Trim() -replace '\s+UTC\s*$', ''; `$dt = [DateTime]::ParseExact(`$dateCleaned, 'yyyy-MM-dd HH:mm:ss', `$null); `$datePrefix = `$dt.ToString('yyyyMMdd_HHmmss'); `$baseName = "`${datePrefix}_`${baseName}" } catch { } }; `$ext = Get-FileExtension -url `$url -contentType `$contentType; `$filename = `$baseName + `$ext; `$filepath = Join-Path '$DOWNLOAD_FOLDER' `$filename; return @{ FilePath = `$filepath; FileName = `$filename } }
function Parse-DateString { param([string]`$dateStr); if ([string]::IsNullOrWhiteSpace(`$dateStr)) { return `$null }; try { `$dateCleaned = `$dateStr.Trim() -replace '\s+UTC\s*$', ''; `$formats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd', 'dd.MM.yyyy HH:mm:ss', 'dd.MM.yyyy'); foreach (`$fmt in `$formats) { try { return [DateTime]::ParseExact(`$dateCleaned, `$fmt, `$null) } catch { continue } } } catch { return `$null }; return `$null }
function Write-MetadataToFile { param([string]`$filepath, [string]`$dateStr, [bool]`$silent = `$false); if (-not $exiftoolAvailable -or [string]::IsNullOrWhiteSpace(`$dateStr)) { return `$false }; `$dt = Parse-DateString -dateStr `$dateStr; if (`$null -eq `$dt) { return `$false }; try { `$exifDate = `$dt.ToString('yyyy:MM:dd HH:mm:ss'); `$fileExt = [System.IO.Path]::GetExtension(`$filepath).ToLower(); `$filename = [System.IO.Path]::GetFileName(`$filepath); if (`$filename -match '-overlay|thumbnail') { if (-not `$silent) { Write-Host "[SKIP] Skipping metadata for: `$filename" -ForegroundColor DarkGray }; try { `$file = Get-Item `$filepath; `$file.CreationTime = `$dt; `$file.LastWriteTime = `$dt } catch { }; return `$false }; if (`$fileExt -in @('.jpg', '.jpeg', '.png')) { `$result = & exiftool -overwrite_original -q "-DateTimeOriginal=`$exifDate" "-CreateDate=`$exifDate" "-ModifyDate=`$exifDate" `$filepath 2>&1; if (`$LASTEXITCODE -ne 0 -and -not `$silent) { return `$false } } elseif (`$fileExt -in @('.mp4', '.mov', '.avi')) { `$result = & exiftool -overwrite_original -q "-CreateDate=`$exifDate" "-MediaCreateDate=`$exifDate" "-TrackCreateDate=`$exifDate" "-ModifyDate=`$exifDate" `$filepath 2>&1; if (`$LASTEXITCODE -ne 0 -and -not `$silent) { return `$false } }; `$file = Get-Item `$filepath; `$file.CreationTime = `$dt; `$file.LastWriteTime = `$dt; return `$true } catch { if (-not `$silent) { Write-Host "[METADATA] Could not write metadata for: `$filename" -ForegroundColor Yellow }; return `$false } }
function Expand-AndCleanupZip { param([string]`$zipPath); try { `$extractFolder = [System.IO.Path]::GetFileNameWithoutExtension(`$zipPath); `$extractPath = Join-Path '$DOWNLOAD_FOLDER' `$extractFolder; Expand-Archive -Path `$zipPath -DestinationPath `$extractPath -Force; Remove-Item `$zipPath -Force; Write-Host "[ZIP] Extracted and deleted: `$([System.IO.Path]::GetFileName(`$zipPath))" -ForegroundColor Cyan; return `$extractPath } catch { Write-Host "[ZIP ERROR] Failed to extract `$([System.IO.Path]::GetFileName(`$zipPath)): `$_" -ForegroundColor Red; return `$null } }
function Process-FilesInFolder { param([string]`$folderPath, [string]`$dateStr); if (-not (Test-Path `$folderPath -PathType Container)) { return }; `$successCount = 0; `$skipCount = 0; Get-ChildItem -Path `$folderPath -Recurse -File | Where-Object { `$_.Extension -match '\.(jpg|jpeg|png|mp4|mov|avi)$' } | ForEach-Object { `$result = Write-MetadataToFile -filepath `$_.FullName -dateStr `$dateStr -silent `$true; if (`$result) { `$successCount++ } else { `$skipCount++ } }; if (`$successCount -gt 0 -or `$skipCount -gt 0) { Write-Host "[ZIP-CONTENT] `$successCount files with metadata, `$skipCount skipped" -ForegroundColor Cyan } }
function Get-MemoryFile { param([string]`$url, [bool]`$isGet, [string]`$dateStr = `$null, [int]`$index = 0); `$uniqueId = Get-UniqueIdFromUrl -url `$url; try { `$headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36' }; if (`$isGet) { `$response = Invoke-WebRequest -Uri `$url -Headers `$headers -Method Get -UseBasicParsing } else { `$parts = `$url -split '\?', 2; `$postUrl = `$parts[0]; `$postData = if (`$parts.Count -gt 1) { `$parts[1] } else { '' }; `$response = Invoke-WebRequest -Uri `$postUrl -Headers `$headers -Method Post -Body `$postData -UseBasicParsing }; `$contentType = `$response.Headers['Content-Type']; `$fileInfo = Build-Filename -uniqueId `$uniqueId -dateStr `$dateStr -contentType `$contentType -url `$url; `$filepath = `$fileInfo.FilePath; `$filename = `$fileInfo.FileName; [System.IO.File]::WriteAllBytes(`$filepath, `$response.Content); `$metadataWritten = Write-MetadataToFile -filepath `$filepath -dateStr `$dateStr; if (`$filepath -match '\.zip$') { `$extractFolder = Expand-AndCleanupZip -zipPath `$filepath; if (`$extractFolder) { Process-FilesInFolder -folderPath `$extractFolder -dateStr `$dateStr } }; Write-Host "[OK] `$filename downloaded`$(if (`$metadataWritten) { ' (metadata written)' })" -ForegroundColor Green; return @{ UniqueId = `$uniqueId; Status = 'downloaded'; FileName = `$filename; ContentType = `$contentType; MetadataWritten = `$metadataWritten } } catch { Write-Host "[ERROR] Download failed for `$uniqueId (Index `$index): `$_" -ForegroundColor Red; return @{ UniqueId = `$uniqueId; Status = 'error'; Error = `$_.Exception.Message } } }
"@).AddArgument(@{ exiftoolAvailable = $exiftoolAvailable; DOWNLOAD_FOLDER = $DOWNLOAD_FOLDER })
    
    $jobs += @{
        Pipe = $powershell
        Status = $powershell.BeginInvoke()
    }
}

# Wait for all jobs to complete
foreach ($job in $jobs) {
    $result = $job.Pipe.EndInvoke($job.Status)
    $completedCount++
    
    if ($result.Status -eq 'downloaded') {
        $downloadedCount++
        # Update downloaded files
        $downloadedFiles[$result.UniqueId] = @{
            filename = $result.FileName
            content_type = $result.ContentType
            metadata_written = $result.MetadataWritten
            timestamp = (Get-Date).ToString('o')
        }
        Save-Progress
    }
    elseif ($result.Status -eq 'skipped') {
        $skippedCount++
    }
    elseif ($result.Status -eq 'error') {
        $errorCount++
    }
    
    # Progress display
    if (($completedCount % 10) -eq 0 -or $completedCount -eq $totalCount) {
        Write-Host "`n[PROGRESS] $completedCount/$totalCount files processed (Downloaded: $downloadedCount, Skipped: $skippedCount, Errors: $errorCount)`n" -ForegroundColor Cyan
    }
    
    $job.Pipe.Dispose()
}

$runspacePool.Close()
$runspacePool.Dispose()

# Final save
Save-Progress

# Summary
Write-Host "`n=== Download Summary ===" -ForegroundColor Cyan
Write-Host "Total processed: $($downloadTasks.Count) files"
Write-Host "Newly downloaded: $downloadedCount files" -ForegroundColor Green
Write-Host "Skipped (already exists): $skippedCount files" -ForegroundColor Yellow
Write-Host "Errors: $errorCount files" -ForegroundColor Red
Write-Host "Total successful: $($downloadedFiles.Count) files" -ForegroundColor Green

if ($errorCount -gt 0) {
    Write-Host "`nFailed downloads saved to '$ERROR_LOG_FILE'" -ForegroundColor Yellow
}

Write-Host "`nAll downloads processed." -ForegroundColor Green
