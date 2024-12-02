# oh-my-posh module
oh-my-posh init pwsh --config ~/.mytheme.omp.json | Invoke-Expression

# setting env path

# Alias 
Set-Alias ls lsd
Set-Alias vi vim

# config path setting
$omp_config_file = "$env:HOMEPATH/.mytheme.omp.json"
$history_backup_file_path = "$env:APPDATA/Microsoft/Windows/PowerShell/PSReadLine"


##########################################################################################
# function list
function ll # lsd -al
{
    param (
        [string]$Path = (Get-Location)
    )

    ECHO "PATH : $Path" 
    lsd -alg $Path
}

function lt # lsd -- tree
{
    param (
        [string]$Path = (Get-Location)
    )
    
    ECHO "PATH : $Path" 
    lsd --tree $Path
}

function Config # open powershell profile config-file via vscode
{
    code $PROFILE.CurrentUserCurrentHost
}
function Config-lsd # open lsd config-file via vscode
{
    code $env:APPDATA/lsd/config.yaml
}

function Config-omp # open oh my posh config-file via vscode
{
    code $env:HOMEPATH/.mytheme.omp.json
}

function rsa-pubkey # show ssh rsa-public key
{
    cat $env:HOMEPATH/.ssh/id_rsa.pub
}

function Del-hist # delete powershell history
{
    rm "$history_backup_file_path/ConsoleHost_history.txt"
}

function Which # get binary path
{
    param(
        [String] $command
    )
    Get-Command -Name $command -ErrorAction SilentlyContinue 
}

function path # echo enc path
{
    $env:Path.Split(";")
}

function fnc # get function list in $profile
{
    cat $PROFILE | Select-string -Pattern "^function*" -NoEmphasis
}

function down  # change directory downloads
{ 
    cd $Home/Downloads
}
