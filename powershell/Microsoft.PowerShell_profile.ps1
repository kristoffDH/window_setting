

oh-my-posh --init --shell pwsh --config ~/.mytheme.omp.json | Invoke-Expression

del alias:curl

Set-Alias ls lsd -Option AllScope
New-Alias vi vim 

function config {
	vi $PROFILE.CurrentUserCurrentHost
}

function config-code {
	vi $PROFILE.CurrentUserCurrentHost
}

function ll {
	lsd -al
}

function lt {
	lsd --tree
}

function omp-theme {

	Get-ChildItem -Path "~\Desktop\window_setting\oh-my-posh theme\*"  -Include '*.omp.json' `
	| Sort-Object Name `
	| ForEach-Object -Process `
	{ 
		$esc = [char]27
		Write-Host ">>>" 
		Write-Host "$esc[1m$($_.BaseName)$esc[0m"
		Write-Host ""
		oh-my-posh --config $($_.FullName) --pwd $PWD
		Write-Host ""
		Write-Host "========================================================"
	}
}

Import-Module ~/Documents/WindowsPowerShell/ssh-util.psm1;
