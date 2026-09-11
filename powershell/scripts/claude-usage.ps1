#########################################################
# Claude 사용량 수집기(test-ex) 영역 Start
#########################################################
# test-ex 서버의 ~/claude-usage/ 수집기를 이 PC에서 다루는 명령 모음.
# 서버는 월~금 06/12/18시(KST)에 claude /usage 를 찍어 usage.csv 에 누적한다.
# 주간 사용률은 계정 단위 값이라 여러 PC에 흩어진 사용량이 한 곳에 모인다.
#
# test-ex 호스트에는 RemoteCommand 가 걸려 있어 원격 명령을 함께 주려면
# 반드시 -o RemoteCommand=none 이 필요하다.
# (빠뜨리면 "Cannot execute command-line and remote command." 로 실패한다)

$global:cu_host   = 'test-ex'
$global:cu_remote = '~/claude-usage'
$global:cu_local  = Join-Path $HOME 'Downloads\claude-usage'

function cu-ssh {
    # fnc-ignore
    param([Parameter(Mandatory)][string]$Script)
    ssh -T -o RemoteCommand=none $global:cu_host "$global:cu_remote/$Script"
}

function cu-status {
    # Claude 사용량 수집기 점검 - cron 등록/누적 건수/마지막 수집/로그인 상태를 실측
    cu-ssh 'status.sh'
}

function cu-report {
    # 누적된 사용률 요약 - 주차별 최고치와 요일·시간대 평균
    cu-ssh 'report.sh'
}

function cu-run {
    # 예정 시각 외에 사용률을 지금 한 번 더 수집 (추이가 촘촘해지므로 남용하지 말 것)
    cu-ssh 'collect.sh'
}

function cu-pull {
    # 서버의 usage.csv 를 이 PC로 내려받는다 (viewer.html 에 끌어다 놓으면 그래프)
    if (-not (Test-Path $global:cu_local)) {
        New-Item -ItemType Directory -Path $global:cu_local -Force | Out-Null
    }
    scp -o RemoteCommand=none "$($global:cu_host):claude-usage/usage.csv" $global:cu_local
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("받음 : {0}" -f (Join-Path $global:cu_local 'usage.csv'))
        Write-Host ("뷰어 : {0}" -f (Join-Path $global:cu_local 'viewer.html'))
    }
}

function cu-help {
    # Claude 사용량 수집기 명령 목록을 출력한다.
    $cmds = @(
        @{ Name = 'cu-status'; Desc = '수집기 점검 - cron 등록/누적 건수/마지막 수집/로그인 상태' },
        @{ Name = 'cu-report'; Desc = '누적 요약 - 주차별 최고치와 요일·시간대 평균' },
        @{ Name = 'cu-run   '; Desc = '지금 한 번 더 수집 (예정 시각 외, 남용하지 말 것)' },
        @{ Name = 'cu-pull  '; Desc = 'usage.csv 를 이 PC로 내려받기' }
    )

    Write-Host ''
    Write-Host ' Claude 사용량 수집기' -ForegroundColor Cyan
    Write-Host (' {0}:{1} · 월~금 06/12/18시 자동 수집' -f $global:cu_host, $global:cu_remote) -ForegroundColor DarkGray
    Write-Host ''
    foreach ($c in $cmds) {
        Write-Host ('   {0}' -f $c.Name) -ForegroundColor Yellow -NoNewline
        Write-Host ('  {0}' -f $c.Desc)
    }
    Write-Host ''
    Write-Host ' 데이터 ' -ForegroundColor DarkGray -NoNewline
    Write-Host ('{0}:{1}/usage.csv' -f $global:cu_host, $global:cu_remote)
    Write-Host ' 뷰어   ' -ForegroundColor DarkGray -NoNewline
    Write-Host ('{0}  (cu-pull 로 받은 usage.csv 를 끌어다 놓기)' -f (Join-Path $global:cu_local 'viewer.html'))
    Write-Host ' 제거   ' -ForegroundColor DarkGray -NoNewline
    Write-Host ("ssh -T -o RemoteCommand=none {0} '{1}/uninstall.sh --purge-data --purge-claude'" -f $global:cu_host, $global:cu_remote)
    Write-Host ''
}

#########################################################
# Claude 사용량 수집기(test-ex) 영역 End
#########################################################
