
# oh-my-posh module
oh-my-posh init pwsh --config ~/.mytheme.omp.json | Invoke-Expression

# setting env path
# $Env:python_module = "C:$env:HOMEPATH\python_module"
# $Env:Path += ";$Env:python_module;"

# Alias 
Remove-Item Alias:/ls
Set-Alias ls lsd
Set-Alias vi vim

# config path setting
#$omp_config_file = "$env:HOMEPATH/.mytheme.omp.json"
#$window_setting_backup = "$env:HOMEPATH/Desktop/window_setting"
$history_backup_file_path = "$env:APPDATA/Microsoft/Windows/PowerShell/PSReadLine"

# PSReadLine
# Set-PSReadLineOption -PredictionSource History
# Set-PSReadLineOption -PredictionViewStyle ListView

# function list
function ll {
    param (
        [string]$Path = (Get-Location)
    )

    ECHO "PATH : $Path" 
    lsd -alg $Path
}

function lt {
    param (
        [string]$Path = (Get-Location)
    )
    
    ECHO "PATH : $Path" 
    lsd --tree $Path
}

function Config {
    code $PROFILE.CurrentUserCurrentHost
}
function Config-lsd {
    code $env:APPDATA/lsd/config.yaml
}

function Config-omp {
    code $env:HOMEPATH/.mytheme.omp.json
}

function rsa-pubkey {
    cat $env:HOMEPATH/.ssh/id_rsa.pub
}

# function Update-posh {
#     winget upgrade JanDeDobbeleer.OhMyPosh -s winget
# }

# function Update-lsd-config {
#     $cur_path = pwd
#     cd $window_setting_backup
#     cp $env:APPDATA/lsd/config.yaml .
#     git add .
#     git commit -m "Update lsd config"
#     git push
#     cd $cur_path
# }

# function Update-ps-profile {
#     $cur_path = pwd
#     cd $window_setting_backup
#     cp $PROFILE.CurrentUserCurrentHost "./powershell"
#     git add .
#     git commit -m "Update window setting"
#     git push
#     cd $cur_path
# }

# function Update-omp-config {
#     $cur_path = pwd
#     cd $window_setting_backup
#     cp $omp_config_file "./powershell"
#     git add .
#     git commit -m "Update omp setting"
#     git push
#     cd $cur_path
# }

# function Open-win-backup {
#     cd $window_setting_backup
# }

function Del-hist {
    rm "$history_backup_file_path/ConsoleHost_history.txt"
}

function Which {
    param(
        [String] $command
    )
    Get-Command -Name $command -ErrorAction SilentlyContinue 
}

function path {
    $env:Path.Split(";")
}

