
# Install-Module powershell-yaml
# https://github.com/cloudbase/powershell-yaml
Import-Module powershell-yaml

$config_path = "C:/Users/krist/.ssh/remote_ssh_list.yaml"

function Connect-Ssh {
    [System.Collections.ArrayList]$host_list = @()
    Write-Host "ssh config path :" $config_path

    $file = Get-Content -Path $config_path -Raw
    $config = ConvertFrom-Yaml ($file)    
    
    $ROOT = $config['REMOTE_LIST']
    
    for ($idx = 0; $idx -lt $ROOT.Count; ++$idx) {
        $SSH_ADDR = "ssh " + $ROOT[$idx]['id'] + "@" + $ROOT[$idx]['addr']

        $SSH_PORT = $ROOT[$idx]['port']
        if ($SSH_PORT) {
            $SSH_ADDR += " -p $SSH_PORT" 
            [void]$host_list.Add($SSH_ADDR)
        }
        else {
            [void]$host_list.Add($SSH_ADDR)        
        }
    }

    Write-Host "[Remote SSh List]"

    for ($idx = 0; $idx -lt $host_list.Count; ++$idx) {
        Write-Host "---------------------------------"
        Write-Host "[${idx}] ->" $host_list[$idx]
    }
    Write-Host "---------------------------------"
        
    $selected = Read-Host "Select Remote SSH Index"

    Write-Host "Connect to" $host_list[$selected]
    Invoke-Expression $host_list[$selected]
    
}

Export-ModuleMember -Function Connect-Ssh