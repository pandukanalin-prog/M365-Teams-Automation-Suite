# 1. Using Custom Entra ID App
$MyCustomClientId = "YOUR-CLIENT-ID-HERE"
$RootUrl = "https://yourdomain.sharepoint.com"

Write-Host "Connecting using Custom App..." -ForegroundColor Cyan
Connect-PnPOnline -Url $RootUrl -Interactive -ClientId $MyCustomClientId

# 2. Get the exact Admin email address automatically
$MyAccount = Invoke-PnPGraphMethod -Method Get -Url "v1.0/me"
$MyEmail = $MyAccount.userPrincipalName
Write-Host "Logged in as Admin: $MyEmail" -ForegroundColor Magenta

# 3. Fetch the master list
Write-Host "Downloading classes via Microsoft Graph..." -ForegroundColor Yellow
$AllClasses = Get-PnPMicrosoft365Group

if ($AllClasses.Count -gt 0) {
    
    $MasterToken = Get-PnPAccessToken -ResourceTypeName SharePoint
    Write-Host "Starting the silent lockdown loop..." -ForegroundColor Green

    foreach ($Class in $AllClasses) {
        
        $SiteUrl = $Class.SiteUrl
        if (-not $SiteUrl) { $SiteUrl = "$RootUrl/sites/$($Class.MailNickname)" }
        if (-not $SiteUrl -or $SiteUrl -eq "$RootUrl/sites/") { continue }
        
        Write-Host "Processing: $($Class.DisplayName)" -ForegroundColor Cyan
        
        try {
            Connect-PnPOnline -Url $SiteUrl -AccessToken $MasterToken
            
            $MembersGroup = Get-PnPGroup -AssociatedMemberGroup
            $List = Get-PnPList -Identity "Documents" -Includes HasUniqueRoleAssignments
            
            $IsRestricted = $false
            
            if ($List.HasUniqueRoleAssignments -eq $true) {
                $CurrentPerms = Get-PnPListPermissions -Identity "Documents" -PrincipalId $MembersGroup.Id
                if (($CurrentPerms.Name -contains "Read") -and ($CurrentPerms.Name -notcontains "Edit")) {
                    $IsRestricted = $true
                }
            }
            
            if ($IsRestricted -eq $true) {
                Write-Host "  -> Skipped: Already restricted." -ForegroundColor DarkGray
            } else {
                if ($List.HasUniqueRoleAssignments -eq $false) {
                    Set-PnPList -Identity "Documents" -BreakRoleInheritance -CopyRoleAssignments
                }
                
                Set-PnPListPermission -Identity "Documents" -Group $MembersGroup.Title -RemoveRole "Edit"
                Set-PnPListPermission -Identity "Documents" -Group $MembersGroup.Title -AddRole "Read"

                Write-Host "  -> Success! Locked down." -ForegroundColor Green
            }
        }
        catch {
            # THE SELF-HEALING BLOCK
            if ($_.Exception.Message -match "Unauthorized") {
                Write-Host "  -> Access Denied (Private Class). Injecting Admin permissions..." -ForegroundColor Yellow
                
                try {
                    # Forcefully add as an Owner to bypass the block
                    Add-PnPMicrosoft365GroupOwner -Identity $Class.Id -Users $MyEmail
                    
                    Write-Host "  -> Waiting 10 seconds for Microsoft cloud to sync permissions..." -ForegroundColor DarkGray
                    Start-Sleep -Seconds 10
                    
                    # Try locking it down ONE more time
                    $MembersGroup = Get-PnPGroup -AssociatedMemberGroup
                    $List = Get-PnPList -Identity "Documents" -Includes HasUniqueRoleAssignments
                    
                    if ($List.HasUniqueRoleAssignments -eq $false) {
                        Set-PnPList -Identity "Documents" -BreakRoleInheritance -CopyRoleAssignments
                    }
                    Set-PnPListPermission -Identity "Documents" -Group $MembersGroup.Title -RemoveRole "Edit"
                    Set-PnPListPermission -Identity "Documents" -Group $MembersGroup.Title -AddRole "Read"
                    
                    Write-Host "  -> Success! Block bypassed and folder locked." -ForegroundColor Green
                    
                } catch {
                    Write-Host "  -> Failed to force access. Error: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "  -> Failed to process site. Error: $_" -ForegroundColor Red
            }
        }
    }
    
    Write-Host "All classes have been processed! Disconnecting securely." -ForegroundColor Cyan
    Disconnect-PnPOnline

} else {
    Write-Host "Error: 0 groups returned." -ForegroundColor Red
}
