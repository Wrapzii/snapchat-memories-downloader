# Snapchat Memories Downloader
Since snapchat wants you to pay for more than 5gb of snapchat memories, I made a script to download all your memories since the version snapchat provided has a bug where it says 100% is downloaded but in reality it didn't download anything (at least in my case)

## Disclaimer
Everything i did here was vibe coded, i wanted it do be done quickly and it worked for me.
I think it's even better than the original, since I am adding metadata to the files, which snapchat doesn't
Feel free to contribute 👍🙏

## Available Versions
- **PowerShell Scripts** (`.ps1`) - **Recommended for Windows users** - No Python required!
- **Python Scripts** (`.py`) - For Mac/Linux users or those who prefer Python

# Quick Start (Windows - PowerShell)

## Prerequisites
1. **PowerShell** - Already included in Windows
2. **ExifTool** (optional but recommended for metadata)
   - Download from [https://exiftool.org/](https://exiftool.org/)
   - Extract and rename `exiftool(-k).exe` to `exiftool.exe`
   - Place in same folder as scripts or add to PATH

## How to Run

### 1. Run the installer (checks dependencies)
```powershell
installer.bat
```

### 2. Request your Snapchat data
- Go to [https://accounts.snapchat.com](https://accounts.snapchat.com)
- Click on `My Data`
- Select `Export your Memories` and click `Request Only Memories`
- Select `All Time`
- Confirm email and click `Submit`
- After some time you'll get an email with the download link. Follow the instructions and download the data

### 3. Place the `memories_history.html` file
Put the downloaded `memories_history.html` file in the same folder as the PowerShell scripts

### 4. Run the download script
```powershell
powershell -ExecutionPolicy Bypass -File snapchat-downloader.ps1
```

The script downloads all your memories and creates:
- `./snapchat_memories/` - Folder where all your memories are stored with correct dates
- `downloaded_files.json` - Information about downloaded files
- `download_errors.json` - Files that had download errors

### 5. (Optional) Add GPS location metadata
```powershell
powershell -ExecutionPolicy Bypass -File metadata.ps1
```

### 6. (Optional) Delete duplicates in extracted folders
```powershell
powershell -ExecutionPolicy Bypass -File delete-dupes.ps1
```

### 7. Retry failed downloads
- Delete the `download_errors.json` file
- Run the download script again
- If files still fail, try visiting the download link in your browser (may be a Snapchat issue)

---

# Python Version (Mac/Linux)

## How to run
1. create a python venv
```bash
python3 -m venv .venv
```
2. activate python venv
```bash
# mac/linux
source .venv/bin/activate

# windows
.\.venv\Scripts\Activate.ps1
```
3. check python venv
```bash
# mac/linux
which python
# windows
Get-Command python
```

4. run install script (mac/linux)
```bash
chmod +x ./installer.sh
./install.sh
```
helper if operation not permitted (mac):
```bash
xattr -d com.apple.quarantine ./installer.sh
```

5. request the download from snapchat
- go to [https://accounts.snapchat.com]()
- click on ``My Data```
- select ``Export your Memories`` and click ``Request Only Memories```
- select ``All Time``
- confirm email and click ``Submit``
- after some time you'll get a mail with the download link. Follow the instructions and download the data

6. paste the ``memories_history.html`` file in the project root (same folder as ``snapchat-downloader.py``)
for some reason snapchat doesn't let you download all your memories in a single (or multiple) zip files, but just gives you a html file (which is buggy at least for me) which lets you download all your memories.

7. run download script
```bash
python snapchat-downloader.py
```
The script then downloads all your memories
It creates the following folders/files 
- ``./snapchat_memories/``: Folder where all your memories are stored. The script automatically edits the metadata, so your files have the correct date. Files also have the prefix with the correct date and time.
Snaps with text, emojis or stickers are downloaded as zips containing all the layers. These zip files are extracted automatically.
- ``downloaded_files.json``: Json file containing some information about the downloaded files
- ``download_errors.json``: Json file containing files which had a download error

8. Trying failed downloads again
- delete the download_errors.json file
- run the download script again
- if any files do have an error again, try visiting the download link in your browser. Maybe there is no file on the other side (snapchat problem)
- if it works, try running it again

9. Adding Location Metadata
```bash
python metadata.py
```

10. deleting duplicate entries in folders with overlays
```bash
python delete-dupes.py
```

11. Reimport data (mac)
```bash
mdimport -r snapchat_memories/
```


12. correct the FileCreatedTimestamp to match the Created Timestamp (Mac/Linux only)
```bash
exiftool "-FileCreateDate<CreateDate" "-FileModifyDate<CreateDate" -ext mp4 -r snapchat_memories/
exiftool "-FileCreateDate<CreateDate" "-FileModifyDate<CreateDate" -ext jpg -r snapchat_memories/
```

---

## Script Parameters

### PowerShell Scripts

**snapchat-downloader.ps1**
```powershell
# Run with custom settings
powershell -ExecutionPolicy Bypass -File snapchat-downloader.ps1 -MaxWorkers 10 -UseExifTool $true

# Test mode (download only a few files)
powershell -ExecutionPolicy Bypass -File snapchat-downloader.ps1 -TestMode $true -TestFilesPerThread 3
```

**metadata.ps1**
```powershell
# Run without exiftool (only creates JSON)
powershell -ExecutionPolicy Bypass -File metadata.ps1 -UseExifTool $false
```

**delete-dupes.ps1**
```powershell
# Dry run (preview only)
powershell -ExecutionPolicy Bypass -File delete-dupes.ps1 -DryRun $true

# Actually delete duplicates
powershell -ExecutionPolicy Bypass -File delete-dupes.ps1 -DryRun $false
```

## Troubleshooting

### Windows PowerShell Execution Policy
If you get an error about execution policy, run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Or always use the `-ExecutionPolicy Bypass` flag when running scripts.

### ExifTool Not Found
- Make sure `exiftool.exe` is in the same folder as the scripts, or
- Add the folder containing `exiftool.exe` to your system PATH, or
- Place `exiftool.exe` in `C:\Windows\System32`

## Features
- ✅ **No Python required** (PowerShell version)
- ✅ Parallel downloads (configurable workers)
- ✅ Automatic metadata writing (dates, GPS)
- ✅ ZIP extraction with metadata for all layers
- ✅ Progress tracking and resume capability
- ✅ Error logging and retry support
- ✅ Duplicate detection and removal
- ✅ Works on Windows without any additional software (except ExifTool for metadata)
