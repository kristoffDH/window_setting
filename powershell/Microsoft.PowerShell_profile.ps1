
# window curl setting
# del alias:curl

# oh-my-posh module
oh-my-posh init pwsh --config ~/.mytheme.omp.json | Invoke-Expression

# dir icon setting
Import-Module -Name Terminal-Icons

# ssh custom module
Import-Module ~/Documents/WindowsPowerShell/ssh-util.psm1;

# set alias
Set-Alias ls dir -Option AllScope
Set-Alias ll dir -Option AllScope

$window_profile_backup = "~/Desktop/window_setting"
$powershell_script_path = "~/Documents/PowerShell"

# PSReadLine
# Set-PSReadLineOption -BellStyle None
# Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView

# function list
function config {
    code $PROFILE.CurrentUserCurrentHost
}

function update-posh {
    winget upgrade JanDeDobbeleer.OhMyPosh -s winget
}

function ld {
    dir -directory
}

function lf {
    dir -file
}

function update-ps-profile {
    cp $PROFILE.CurrentUserCurrentHost $window_profile_backup"/powershell"
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