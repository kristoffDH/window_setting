
# window curl setting
del alias:curl

# oh-my-posh module
oh-my-posh init pwsh --config ~/.mytheme.omp.json | Invoke-Expression

# dir icon setting
Import-Module -Name Terminal-Icons

# ssh custom module
Import-Module ~/Documents/WindowsPowerShell/ssh-util.psm1;

# set alias
Set-Alias ls dir -Option AllScope

$window_profile_backup = "~/Desktop/window_setting"

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

function path-ps-profile {
	$window_profile_backup
}