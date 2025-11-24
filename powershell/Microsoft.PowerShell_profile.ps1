
# oh-my-posh module
oh-my-posh init pwsh --config $HOME/.mytheme.omp.json | Invoke-Expression

# setting env path

# Alias 
Set-Alias ls lsd
Set-Alias vi vim

# config path setting
$omp_config_file = "$env:HOMEPATH/.mytheme.omp.json"
$history_backup_file_path = "$env:APPDATA/Microsoft/Windows/PowerShell/PSReadLine"

# PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView

Invoke-Expression (& { (zoxide init powershell | Out-String) })

Set-Alias zz zi

$env:OMP_TAG = "IP : 10.10.70.52"

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

function config # open powershell profile config-file via vscode
{
    code $PROFILE.CurrentUserCurrentHost
}
function config-lsd # open lsd config-file via vscode
{
    code $env:APPDATA/lsd/config.yaml
}

function config-omp # open oh my posh config-file via vscode
{
    code $env:HOMEPATH/.mytheme.omp.json
}

function rsa-pubkey # show ssh rsa-public key
{
    cat $env:HOMEPATH/.ssh/id_rsa.pub
}

function code-hist # open powershell history 
{
    code "$history_backup_file_path/ConsoleHost_history.txt"
}

function del-hist # delete powershell history
{
    rm "$history_backup_file_path/ConsoleHost_history.txt"
}

function open-hist
{
    code "$history_backup_file_path/ConsoleHost_history.txt"
}

function which # get binary path
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

function ssh-config
{
    code $Home/.ssh/config
}

function layout-config
{
    code C:/hanssak/powershell_script\ssh-layout
}

function reload {
    oh-my-posh init pwsh --config "$HOME\.mytheme.omp.json" | Invoke-Expression
}


