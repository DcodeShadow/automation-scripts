# freeupspace_test.ps1
# Purpose:
# - Scan OneDrive / SharePoint synced folders
# - Find locally available files older than X days
# - Skip desktop.ini
# - Log results first
# - Only apply changes when -ApplyChanges is used

param(
    [int]$DaysOld = 30,
    [switch]$ApplyChanges
)

$ErrorActionPreference = "SilentlyContinue"

$LogPath = "C:\Temp\freeupspace_log.txt"
$CutoffDate = (Get-Date).AddDays(-$DaysOld)

if (!(Test-Path "C:\Temp")) {
    New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
}

# Start fresh log each run
if (Test-Path $LogPath) {
    Remove-Item $LogPath -Force
}

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LogPath -Value $Message -Encoding UTF8
}

Write-Log "=============================="
Write-Log "Run time: $(Get-Date)"
Write-Log "Days old cutoff: $DaysOld"
Write-Log "Apply changes: $ApplyChanges"
Write-Log "=============================="

# Find OneDrive paths
$CandidatePaths = @()

if ($env:OneDrive) {
    $CandidatePaths += $env:OneDrive
}

if ($env:OneDriveCommercial) {
    $CandidatePaths += $env:OneDriveCommercial
}

if ($env:OneDriveConsumer) {
    $CandidatePaths += $env:OneDriveConsumer
}

$UserProfile = $env:USERPROFILE

if (Test-Path $UserProfile) {
    $OneDriveFolders = Get-ChildItem -Path $UserProfile -Directory -Force | Where-Object {
        $_.Name -like "OneDrive*"
    }

    foreach ($Folder in $OneDriveFolders) {
        $CandidatePaths += $Folder.FullName
    }
}

$CandidatePaths = $CandidatePaths | Sort-Object -Unique

if (-not $CandidatePaths) {
    Write-Log "No OneDrive paths found."
    Write-Host "No OneDrive paths found."
    exit 1
}

Write-Log "Discovered paths:"

foreach ($Path in $CandidatePaths) {
    Write-Log $Path
}

$TotalScanned = 0
$TotalSkippedRecent = 0
$TotalSkippedSystem = 0
$TotalCandidates = 0
$TotalApplied = 0
$TotalFailed = 0

foreach ($Path in $CandidatePaths) {
    if (!(Test-Path $Path)) {
        continue
    }

    Write-Log "Scanning path: $Path"

    $Files = Get-ChildItem -Path $Path -Recurse -File -Force

    foreach ($File in $Files) {
        $TotalScanned++

        # Skip junk/system files
        if ($File.Name -eq "desktop.ini") {
            $TotalSkippedSystem++
            continue
        }

        # Skip recently modified files
        if ($File.LastWriteTime -gt $CutoffDate) {
            $TotalSkippedRecent++
            continue
        }

        $TotalCandidates++

        $SizeMB = [math]::Round(($File.Length / 1MB), 2)

        Write-Log "Candidate file: $($File.FullName) | Modified: $($File.LastWriteTime) | SizeMB: $SizeMB | Attr: $($File.Attributes)"

        if ($ApplyChanges) {
            cmd /c "attrib -P +U `"$($File.FullName)`""

            if ($LASTEXITCODE -eq 0) {
                $TotalApplied++
                Write-Log "Applied online-only attribute to: $($File.FullName)"
            } else {
                $TotalFailed++
                Write-Log "Failed to apply online-only attribute to: $($File.FullName)"
            }
        }
    }
}

Write-Log "=============================="
Write-Log "Summary:"
Write-Log "Total scanned: $TotalScanned"
Write-Log "Skipped system files: $TotalSkippedSystem"
Write-Log "Skipped recent files: $TotalSkippedRecent"
Write-Log "Candidate files: $TotalCandidates"
Write-Log "Changes applied: $TotalApplied"
Write-Log "Failed changes: $TotalFailed"
Write-Log "=============================="
Write-Log "Completed."

Write-Host "Done. Log saved to $LogPath"
