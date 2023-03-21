
# oh-my-posh module
oh-my-posh init pwsh --config ~/.mytheme.omp.json | Invoke-Expression

# dir icon setting
Import-Module -Name Terminal-Icons

# ssh custom module
Import-Module ~/Documents/PowerShell/ssh-util.psm1;

# Alias
Remove-Alias ls

$window_profile_backup = "~/Desktop/window_setting"
$powershell_script_path = "~/Documents/PowerShell"
$history_backup_file_path = "~/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine"

# PSReadLine
# Set-PSReadLineOption -BellStyle None
# Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView

# fzf
Import-Module PSFzf
# Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r'

# function list
function ll { 
    dir -Force
}

function ld { 
    dir -directory 
}

function lf { 
    dir -file 
}

function ls { 
    dir | Format-Wide
}

function config {
    code $PROFILE.CurrentUserCurrentHost
}

function update-posh {
    winget upgrade JanDeDobbeleer.OhMyPosh -s winget
}

function update-ps-profile {
    $cur_path = pwd
    cp $PROFILE.CurrentUserCurrentHost $window_profile_backup"/powershell"
    cd $window_profile_backup
    git add .
    git commit -m "update window setting"
    git push
    cd $cur_path
}

function move-winsetting {
    cd $window_profile_backup
}

function open-ps-path {
    ii $powershell_script_path
}

function open-home {
    ii ~
}

function del_history {
    $cur_path = pwd
    cd $history_backup_file_path
    $file_path = pwd
    code $file_path"/ConsoleHost_history.txt"
    cd $cur_path
}

function which ($command) {
    Get-Command -Name $command -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue
}

 
function fnc-list { 

    Write-Host "=======================" -ForegroundColor Green
    Write-Host "Custom Function List"
    Write-Host "=======================" -ForegroundColor Green
    
    Write-Host "ll" -ForegroundColor Yellow
    Write-Host "ls" -ForegroundColor Yellow
    Write-Host "ld" -ForegroundColor Yellow
    Write-Host "lf" -ForegroundColor Yellow
    Write-Host "config" -ForegroundColor Yellow
    Write-Host "update-posh" -ForegroundColor Yellow
    Write-Host "update-ps-profile" -ForegroundColor Yellow
    Write-Host "move-winsetting" -ForegroundColor Yellow
    Write-Host "open-ps-path" -ForegroundColor Yellow
    Write-Host "open-home" -ForegroundColor Yellow
    Write-Host "which" -ForegroundColor Yellow
    Write-Host "del_history" -ForegroundColor Yellow
}