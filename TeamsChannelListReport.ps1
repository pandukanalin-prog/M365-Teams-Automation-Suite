# ==========================================
# CONFIGURATION
# ==========================================
# 1. Base URL to run the search
$BaseUrl = "https://yourdomain.sharepoint.com"

# 2. App ID and Tenant ID
$ClientId = "YOUR-CLIENT-ID-HERE"
$TenantId = "YOUR-TENANT-ID-HERE"

# 3. Where you want the final generated report saved
$ReportPath = "C:\YourBackupDrive\Teams_Modules_Report.csv"

# ==========================================
# SCRIPT EXECUTION
# ==========================================
$AllModules = @()

Write-Host "Logging into Microsoft 365..." -ForegroundColor Yellow
# Initial login to the root site to establish the search session
Connect-PnPOnline -Url $BaseUrl -Interactive -ClientId $ClientId -Tenant $TenantId

Write-Host "Searching for all Teams classes you belong to..." -ForegroundColor Cyan

# 4. Search Query for all sites the logged-in user is a member of
$Search = Submit-PnPSearchQuery -Query "contentclass:STS_Site AND Path:$BaseUrl/sites/*" -TrimDuplicates $false -MaxResults 500

if ($null -eq $Search.ResultRows -or $Search.ResultRows.Count -eq 0) {
    Write-Host "No sites found for your user account! Are you a member of any classes?" -ForegroundColor Red
    Exit
}

# 5. Grab the Path key
$SiteUrls = $Search.ResultRows | ForEach-Object { $_["Path"] }

# Make sure we don't pass any empty URLs
$SiteUrls = $SiteUrls | Where-Object { $_ -ne $null -and $_ -ne "" }

Write-Host "Found $($SiteUrls.Count) sites! Starting scan..." -ForegroundColor Green

foreach ($Site in $SiteUrls) {
    Write-Host "Scanning Site: $Site" -ForegroundColor Cyan
    
    try {
        # Connect to the specific site in the loop
        Connect-PnPOnline -Url $Site -Interactive -ClientId $ClientId -Tenant $TenantId
        
        # Get the Team name from the URL for the report
        $TeamName = ($Site -split "/sites/")[1]

        # Fetch all top-level folders in the default document library
        $Folders = Get-PnPFolderItem -FolderSiteRelativeUrl "Shared Documents" -ItemType Folder -ErrorAction Stop

        foreach ($Folder in $Folders) {
            # Skip hidden system folders that Microsoft Teams creates automatically
            if ($Folder.Name -notin @("Forms", "Templates")) {
                
                # Add the folder data to our master list
                $AllModules += [PSCustomObject]@{
                    TeamName    = $TeamName
                    ModuleName  = $Folder.Name
                    ItemCount   = $Folder.ItemCount
                    DateCreated = $Folder.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                }
            }
        }
    }
    catch {
        Write-Host "FAILED to read modules for: $Site" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Disconnect-PnPOnline

# ==========================================
# EXPORT AND DISPLAY
# ==========================================
if ($AllModules.Count -gt 0) {
    # Save all the collected data to a new CSV file
    $AllModules | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
    
    Write-Host "`nScan Complete!" -ForegroundColor Green
    Write-Host "Report successfully saved to: $ReportPath" -ForegroundColor Green
    
    # Display a quick preview on the PowerShell screen
    Write-Host "`nPreview of Modules Found:" -ForegroundColor Yellow
    $AllModules | Format-Table -AutoSize
} else {
    Write-Host "No modules were found." -ForegroundColor DarkGray
}
