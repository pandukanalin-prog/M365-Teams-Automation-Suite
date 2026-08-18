# ==========================================
# 1. READ YOUR CSV FILE FOR THE DROPDOWN
# ==========================================
$CsvPath = "C:\Path\To\site.csv"
$TeamNames = (Import-Csv -Path $CsvPath).TeamName | Where-Object { $_ -ne $null -and $_ -ne "" }
$BaseUrl = "https://yourdomain.sharepoint.com/sites/"

# ==========================================
# 2. BUILD THE WEB DASHBOARD
# ==========================================
New-UDApp -Title "Teams Class Backup Portal" -Content {
    # --- UI Elements ---
    New-UDImage -Path "C:\Path\To\logo.png" -Width 400
    New-UDHtml -Markup "<br>"
    New-UDCard -Title "Teams Backup" -Content {
        
        New-UDSelect -Id "SelectedClass" -Label "Choose Classes to Backup" -Multiple -Option {
            foreach ($Name in $TeamNames) {
                $FullUrl = $BaseUrl + $Name
                New-UDSelectOption -Name $Name -Value $FullUrl
            }
        }
        
        New-UDHtml -Markup "<br><br>"

        # --- THE DOWNLOAD BUTTON ---
        New-UDButton -Text "Start Backup" -Color Primary -OnClick {
            
            $SelectedUrls = (Get-UDElement -Id "SelectedClass").Value
            
            if ($null -eq $SelectedUrls -or $SelectedUrls.Count -eq 0) {
                Show-UDToast -Message "Please select at least one class!" -BackgroundColor Red -Duration 3000
                return
            }

            Show-UDToast -Message "Starting backup for $($SelectedUrls.Count) class(es)..." -Duration 5000 -Position topCenter
            Set-UDElement -Id "LiveStatus" -Content { "Initializing connection..." }

            # ==========================================
            # 3. SCRIPT LOGIC
            # ==========================================
            $BackupRoot = "C:\YourBackupDrive\TeamsBackup"
            $LibraryName = "Shared Documents"
            $ClientId = "YOUR-CLIENT-ID-HERE"
            $TenantId = "YOUR-TENANT-ID-HERE"

            if (!(Test-Path $BackupRoot)) {
                New-Item -ItemType Directory -Path $BackupRoot | Out-Null
            }

            function Download-SPOFolder {
                param(
                    [string]$FolderUrl,
                    [string]$LocalTarget
                )

                if (!(Test-Path $LocalTarget)) {
                    New-Item -ItemType Directory -Path $LocalTarget | Out-Null
                }

                $Files = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderUrl -ItemType File -ErrorAction Stop

                foreach($File in $Files){
                    $LocalFile = Join-Path $LocalTarget $File.Name
                    $Download = $true

                    if(Test-Path $LocalFile){
                        $LocalInfo = Get-Item $LocalFile

                        if($LocalInfo.Length -eq $File.Length){
                            try{
                                $RemoteTime = [datetime]$File.TimeLastModified
                                if($LocalInfo.LastWriteTimeUtc -ge $RemoteTime.ToUniversalTime()){
                                    $Download = $false
                                }
                            }catch{
                                $Download = $false
                            }
                        }
                    }

                    if(-not $Download){
                        Set-UDElement -Id "LiveStatus" -Content { "⏭️ Skipping (Already exists): $($File.Name)" }
                        continue
                    }

                    Set-UDElement -Id "LiveStatus" -Content { "⬇️ Downloading: $($File.Name)" }

                    Get-PnPFile `
                        -Url $File.ServerRelativeUrl `
                        -Path $LocalTarget `
                        -FileName $File.Name `
                        -AsFile `
                        -Force

                    if((Test-Path $LocalFile) -and $File.TimeLastModified){
                        (Get-Item $LocalFile).LastWriteTimeUtc = ([datetime]$File.TimeLastModified).ToUniversalTime()
                    }
                }

                $Folders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderUrl -ItemType Folder -ErrorAction Stop

                foreach($Folder in $Folders){
                    if($Folder.Name -in @("Forms", "Templates")){ continue }
                    
                    $NextFolder = $FolderUrl + "/" + $Folder.Name
                    $NextLocal = Join-Path $LocalTarget $Folder.Name
                    
                    Download-SPOFolder -FolderUrl $NextFolder -LocalTarget $NextLocal
                }
            }

            # ==========================================
            # 4. LOOP THROUGH EACH SELECTED CLASS
            # ==========================================
            foreach ($TargetUrl in $SelectedUrls) {
                try {
                    $SiteName = ($TargetUrl -split "/sites/")[1]
                    Set-UDElement -Id "LiveStatus" -Content { "Authenticating securely to: ${SiteName}..." }
                    
                    # We use the standard Interactive login. The MSAL cache handles the SSO.
                    Connect-PnPOnline -Url $TargetUrl -Interactive -ClientId $ClientId -Tenant $TenantId

                    foreach($c in [System.IO.Path]::GetInvalidFileNameChars()){
                        $SiteName = $SiteName.Replace($c,"_")
                    }

                    $Target = Join-Path $BackupRoot $SiteName

                    if(!(Test-Path $Target)){
                        New-Item -ItemType Directory -Path $Target | Out-Null
                    }

                    Download-SPOFolder -FolderUrl $LibraryName -LocalTarget $Target

                } catch {
                    Set-UDElement -Id "LiveStatus" -Content { "❌ FAILED for ${SiteName}" }
                    Show-UDToast -Message "FAILED for ${SiteName}: $($_.Exception.Message)" -BackgroundColor Red -Duration 10000 -Position topCenter
                }
            }
            
            # Clean up the session only AFTER all classes are completely finished downloading!
            try { Disconnect-PnPOnline } catch { }

            # FINAL SUCCESS MESSAGE AT THE BOTTOM
            Set-UDElement -Id "LiveStatus" -Content { "✅ All Selected Backups Finished!" }
            Show-UDToast -Message "✅ All Selected Backups Finished!" -BackgroundColor Green -Duration 8000 -Position topCenter
        }
        
        New-UDHtml -Markup "<br><hr><br>"
        
        # --- THE NEW LIVE STATUS BOX ---
        New-UDTypography -Text "Live Activity Log:" -Variant h6
        New-UDElement -Tag 'div' -Id "LiveStatus" -Content { 
            "Waiting for backup to start..." 
        }
    }
}
