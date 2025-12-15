# Snapchat Metadata - GPS Location Extractor and Writer
# Extracts GPS coordinates from HTML and writes them to files

param(
    [bool]$UseExifTool = $true
)

# Configuration
$HTML_FILE = 'memories_history.html'
$DOWNLOADED_FILES_JSON = 'downloaded_files.json'
$METADATA_JSON = 'metadata.json'
$DOWNLOAD_FOLDER = 'snapchat_memories'

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

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Location Metadata Extractor & Writer" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

# Check exiftool
if ($UseExifTool -and -not $exiftoolAvailable) {
    Write-Host "ERROR: exiftool not found!" -ForegroundColor Red
    Write-Host "Installation: https://exiftool.org/" -ForegroundColor Yellow
    Write-Host "Metadata will only be saved to JSON, not in files." -ForegroundColor Yellow
    $response = Read-Host "`nContinue anyway? (y/n)"
    if ($response -notin @('y', 'Y', 'yes', 'Yes')) {
        return
    }
    Write-Host ""
}
elseif ($exiftoolAvailable) {
    Write-Host "exiftool found - GPS data will be written to files" -ForegroundColor Green
    Write-Host ""
}

# Load downloaded_files.json
if (-not (Test-Path $DOWNLOADED_FILES_JSON)) {
    Write-Host "ERROR: '$DOWNLOADED_FILES_JSON' not found!" -ForegroundColor Red
    return
}

$downloadedFiles = Get-Content $DOWNLOADED_FILES_JSON -Raw | ConvertFrom-Json -AsHashtable
if ($downloadedFiles -eq $null) { $downloadedFiles = @{} }

Write-Host "$($downloadedFiles.Count) entries found in downloaded_files.json" -ForegroundColor Cyan

# Extract locations from HTML
function Get-LocationsFromHtml {
    param([string]$htmlFile)
    
    if (-not (Test-Path $htmlFile)) {
        Write-Host "ERROR: '$htmlFile' not found!" -ForegroundColor Red
        return @()
    }
    
    $html = Get-Content $htmlFile -Raw -Encoding UTF8
    $locations = @()
    
    # Pattern for coordinates: "Latitude, Longitude: 48.26275, 13.296288"
    # Updated pattern to properly handle all decimal number formats
    $coordPattern = 'Latitude,\s*Longitude:\s*([+-]?\d*\.?\d+),\s*([+-]?\d*\.?\d+)'
    $matches = [regex]::Matches($html, $coordPattern)
    
    foreach ($match in $matches) {
        $locations += @{
            latitude = [double]$match.Groups[1].Value
            longitude = [double]$match.Groups[2].Value
        }
    }
    
    return $locations
}

# Extract URLs from HTML
function Get-UrlsFromHtml {
    param([string]$htmlFile)
    
    if (-not (Test-Path $htmlFile)) {
        return @()
    }
    
    $html = Get-Content $htmlFile -Raw -Encoding UTF8
    $pattern = "downloadMemories\('(.+?)',\s*this,\s*(true|false)\)"
    $matches = [regex]::Matches($html, $pattern)
    
    $urls = @()
    foreach ($match in $matches) {
        $urls += $match.Groups[1].Value
    }
    
    return $urls
}

# Extract unique ID from URL
function Get-UniqueIdFromUrl {
    param([string]$url)
    
    if ($url -match 'mid=([a-zA-Z0-9\-]+)') {
        return $Matches[1]
    }
    else {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($url))
        return [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()
    }
}

# Write GPS to file
function Write-GpsToFile {
    param(
        [string]$filepath,
        [double]$latitude,
        [double]$longitude
    )
    
    if (-not $exiftoolAvailable) {
        return $false
    }
    
    if (-not (Test-Path $filepath)) {
        return $false
    }
    
    try {
        $fileExt = [System.IO.Path]::GetExtension($filepath).ToLower()
        $filename = [System.IO.Path]::GetFileName($filepath)
        
        # Skip special files
        if ($filename -match '-overlay|thumbnail') {
            return $false
        }
        
        # Convert to EXIF GPS format
        $latRef = if ($latitude -ge 0) { 'N' } else { 'S' }
        $lonRef = if ($longitude -ge 0) { 'E' } else { 'W' }
        
        $absLat = [Math]::Abs($latitude)
        $absLon = [Math]::Abs($longitude)
        
        if ($fileExt -in @('.jpg', '.jpeg', '.png')) {
            $result = & exiftool -overwrite_original -q `
                "-GPSLatitude=$absLat" `
                "-GPSLatitudeRef=$latRef" `
                "-GPSLongitude=$absLon" `
                "-GPSLongitudeRef=$lonRef" `
                $filepath 2>&1
            
            return $LASTEXITCODE -eq 0
        }
        elseif ($fileExt -in @('.mp4', '.mov', '.avi')) {
            $result = & exiftool -overwrite_original -q `
                "-GPSLatitude=$absLat" `
                "-GPSLatitudeRef=$latRef" `
                "-GPSLongitude=$absLon" `
                "-GPSLongitudeRef=$lonRef" `
                $filepath 2>&1
            
            return $LASTEXITCODE -eq 0
        }
        
        return $false
    }
    catch {
        Write-Host "[GPS ERROR] Failed to write for $filename : $_" -ForegroundColor Red
        return $false
    }
}

# Process files in folder
function Process-FilesInFolder {
    param(
        [string]$folderPath,
        [double]$latitude,
        [double]$longitude
    )
    
    if (-not (Test-Path $folderPath -PathType Container)) {
        return 0
    }
    
    $successCount = 0
    
    Get-ChildItem -Path $folderPath -Recurse -File | Where-Object {
        $_.Extension -match '\.(jpg|jpeg|png|mp4|mov|avi)$'
    } | ForEach-Object {
        if (Write-GpsToFile -filepath $_.FullName -latitude $latitude -longitude $longitude) {
            $successCount++
        }
    }
    
    return $successCount
}

# Extract GPS coordinates
Write-Host "Extracting GPS coordinates from '$HTML_FILE'..." -ForegroundColor Cyan
$locations = Get-LocationsFromHtml -htmlFile $HTML_FILE
Write-Host "$($locations.Count) GPS coordinates found" -ForegroundColor Green

# Extract URLs for mapping
$urls = Get-UrlsFromHtml -htmlFile $HTML_FILE
Write-Host "$($urls.Count) URLs found" -ForegroundColor Green
Write-Host ""

# Create metadata
$metadata = @{}
$filesWithLocation = 0
$filesWithoutLocation = 0
$gpsWrittenCount = 0
$gpsFailedCount = 0

for ($i = 0; $i -lt $urls.Count; $i++) {
    $url = $urls[$i]
    $uniqueId = Get-UniqueIdFromUrl -url $url
    
    # Check if file was downloaded
    if (-not $downloadedFiles.ContainsKey($uniqueId)) {
        continue
    }
    
    $fileInfo = $downloadedFiles[$uniqueId]
    $filename = $fileInfo.filename
    
    # Add GPS coordinates if available
    $location = if ($i -lt $locations.Count) { $locations[$i] } else { $null }
    
    $metadata[$uniqueId] = @{
        filename = $filename
        date = $fileInfo.date
        content_type = $fileInfo.content_type
        location = $location
    }
    
    if ($location) {
        $filesWithLocation++
        
        # Write GPS to file
        if ($exiftoolAvailable) {
            $filepath = Join-Path $DOWNLOAD_FOLDER $filename
            
            # Check if it's a file or folder (extracted ZIP)
            if (Test-Path $filepath -PathType Leaf) {
                if (Write-GpsToFile -filepath $filepath -latitude $location.latitude -longitude $location.longitude) {
                    $gpsWrittenCount++
                    Write-Host "[OK] GPS written: $filename" -ForegroundColor Green
                }
                else {
                    $gpsFailedCount++
                    Write-Host "[WARN] GPS failed: $filename" -ForegroundColor Yellow
                }
            }
            elseif (Test-Path ($filepath -replace '\.zip$', '') -PathType Container) {
                # Extracted ZIP folder
                $folderPath = $filepath -replace '\.zip$', ''
                $count = Process-FilesInFolder -folderPath $folderPath -latitude $location.latitude -longitude $location.longitude
                $gpsWrittenCount += $count
                Write-Host "[OK] GPS written for $count files in: $([System.IO.Path]::GetFileName($folderPath))/" -ForegroundColor Green
            }
        }
    }
    else {
        $filesWithoutLocation++
    }
}

# Save metadata.json
Write-Host ""
Write-Host "Saving '$METADATA_JSON'..." -ForegroundColor Cyan
$metadata | ConvertTo-Json -Depth 10 | Set-Content $METADATA_JSON -Encoding UTF8

# Summary
Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Total processed: $($metadata.Count) files"
Write-Host "With GPS coordinates: $filesWithLocation files" -ForegroundColor Green
Write-Host "Without GPS coordinates: $filesWithoutLocation files" -ForegroundColor Yellow

if ($exiftoolAvailable) {
    Write-Host ""
    Write-Host "GPS written to files: $gpsWrittenCount" -ForegroundColor Green
    if ($gpsFailedCount -gt 0) {
        Write-Host "GPS write errors: $gpsFailedCount" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "'$METADATA_JSON' successfully created!" -ForegroundColor Green
