

oh-my-posh --init --shell pwsh --config ~/.mytheme.omp.json | Invoke-Expression

del alias:curl

Set-Alias ls lsd -Option AllScope
New-Alias vi vim 

function config {
    vi $PROFILE.CurrentUserCurrentHost
}

function memo {
    code C:\Users\krist\Desktop\memo.md
}

function ll {
    lsd -al
}

function lt {
    lsd --tree
}

function ssh-server {
    ssh dhkristoff@192.168.1.207
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

function space-theme {
    oh-my-posh --init --shell pwsh `
        --config '~\Desktop\window_setting\oh-my-posh theme\craver.omp.json' `
    | Invoke-Expression	
}

function ssh-con($id, $ip) {
    [string]$conn_ip = "192.168.1." + $ip

    Write-Output "id : $id"
    Write-Output "ip : $conn_ip"

    [string]$ssh_ip = $id + '@' + $conn_ip

    ssh $ssh_ip -o ServerAliveInterval=50
}