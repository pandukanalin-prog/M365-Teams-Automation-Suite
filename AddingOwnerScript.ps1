# ==========================================
# CONFIGURATION
# ==========================================
# Type the exact email address you want to make an Owner
$TargetEmail = "admin@yourdomain.com"

# ==========================================
# SCRIPT EXECUTION
# ==========================================
Write-Host "Logging into Microsoft Teams Admin..." -ForegroundColor Yellow

# THE FIX IS HERE: We added -DisableWAM directly to the script
Connect-MicrosoftTeams -DisableWAM

Write-Host "Downloading the list of ALL Teams in the tenant (This may take a minute)..." -ForegroundColor Cyan
$AllTeams = Get-Team

Write-Host "Found $($AllTeams.Count) Teams. Starting security scan..." -ForegroundColor Green

foreach ($Team in $AllTeams) {
    Write-Host "Scanning: $($Team.DisplayName)" -ForegroundColor Cyan
    
    try {
        # Get the current list of Owners for this specific Team
        $CurrentOwners = Get-TeamUser -GroupId $Team.GroupId -Role Owner
        
        # Check if our Target Email is already in that list
        if ($CurrentOwners.User -contains $TargetEmail) {
            Write-Host " -> SKIPPING: $TargetEmail is already an Owner." -ForegroundColor DarkGray
        } 
        else {
            Write-Host " -> ADDING: Granting $TargetEmail Owner permissions..." -ForegroundColor Green
            # This is the command that actually adds the user as an Owner
            Add-TeamUser -GroupId $Team.GroupId -User $TargetEmail -Role Owner
        }
    }
    catch {
        Write-Host " -> FAILED to update: $($Team.DisplayName)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Disconnect-MicrosoftTeams
Write-Host "`nAll Teams have been processed!" -ForegroundColor Green
