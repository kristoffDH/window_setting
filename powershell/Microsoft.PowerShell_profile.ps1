
# oh-my-posh module
oh-my-posh init pwsh --config ~/.mytheme.omp.json | Invoke-Expression

# Remove-Alias 
$alias_result = Alias | Select-String 'ls ->'
if (!$alias_result) {
    Remove-Alias ls
}

# config path setting
$omp_config_file = "~/.mytheme.omp.json"
$window_setting_backup = "~/Desktop/window_setting"
$history_backup_file_path = "~/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine"

# PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView


# function list
function ls { 
    lsd
}

function ll { 
    lsd -al
}

function lsd-config {
    $cur_path = pwd
    cd $env:APPDATA
    code ./lsd/config.yaml
    cd $cur_path
}

function config {
    code $PROFILE.CurrentUserCurrentHost
}

function ssh-config {
    $cur_path = pwd
    cd
    code ./.ssh/config
    cd $cur_path
}

function omp-config {
    $cur_path = pwd
    cd
    code ./.mytheme.omp.json
    cd $cur_path
}

function show-rsa-pubkey {
    cat "~/.ssh/id_rsa.pub"
}

function show-remote-host {
    $remote_hosts = cat "~/.ssh/config" | Select-String "Host "

    foreach ($remote_host in $remote_hosts) {
        Write-Host $remote_host.Split(" ")
    }
}

function sync-profile {
    . $profile
}

function update-posh {
    winget upgrade JanDeDobbeleer.OhMyPosh -s winget
}

function update-lsd-config {
    $cur_path = pwd
    cd $window_setting_backup
    cp $env:APPDATA/lsd/config.yaml .
    git add .
    git commit -m "update lsd config"
    git push
    cd $cur_path
}

function update-ps-profile {
    $cur_path = pwd
    cd $window_setting_backup
    cp $PROFILE.CurrentUserCurrentHost "./powershell"
    git add .
    git commit -m "update window setting"
    git push
    cd $cur_path
}

function update-omp-config {
    $cur_path = pwd
    cd $window_setting_backup
    cp $omp_config_file "./powershell"
    git add .
    git commit -m "update omp setting"
    git push
    cd $cur_path
}

function open-window-setting-backup {
    cd $window_setting_backup
}

function home {
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
    
    Write-Host "ls" -ForegroundColor Yellow
    Write-Host "ll" -ForegroundColor Yellow
    Write-Host "config" -ForegroundColor Yellow
    Write-Host "lsd-config" -ForegroundColor Yellow
    Write-Host "ssh-config" -ForegroundColor Yellow
    Write-Host "omp-config" -ForegroundColor Yellow
    Write-Host "show-rsa-pubkey" -ForegroundColor Yellow
    Write-Host "show-remote-host" -ForegroundColor Yellow
    Write-Host "sync-profile" -ForegroundColor Yellow
    Write-Host "update-posh" -ForegroundColor Yellow
    Write-Host "update-ps-profile" -ForegroundColor Yellow
    Write-Host "update-omp-config" -ForegroundColor Yellow
    Write-Host "open-window-setting-backup" -ForegroundColor Yellow
    Write-Host "home" -ForegroundColor Yellow
    Write-Host "which" -ForegroundColor Yellow
    Write-Host "del_history" -ForegroundColor Yellow
}