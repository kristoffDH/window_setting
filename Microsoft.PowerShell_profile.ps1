
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
