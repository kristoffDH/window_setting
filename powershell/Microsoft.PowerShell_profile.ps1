
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

# function list
function config {
	code $PROFILE.CurrentUserCurrentHost
}

function update-posh {
	winget upgrade JanDeDobbeleer.OhMyPosh -s winget
}