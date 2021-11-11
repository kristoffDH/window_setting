
oh-my-posh --init --shell pwsh --config ~/.mytheme.omp.json | Invoke-Expression

Set-Alias ls lsd -Option AllScope

function config {
    code $PROFILE.CurrentUserCurrentHost
}

function memo {
    code C:\Users\krist\Desktop\memo.md
}

function ll {
    lsd -al
}

function cd-jcesoft {
    cd C:\Users\krist\Desktop\JCESoft
}