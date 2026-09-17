#########################################################
# Claude 사용량 수집기(test-ex) 영역 Start
#########################################################
# test-ex 서버의 ~/claude-usage/ 수집기를 이 PC에서 다루는 명령 모음.
# 서버는 월~금 06~18시(KST) 매시 정각에 claude /usage 를 찍어 usage.csv 에 누적한다.
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
    # 서버의 usage.csv 를 이 PC로 내려받고 신규 기록을 요약한다 (viewer.html 에 끌어다 놓으면 그래프)
    $dst = Join-Path $global:cu_local 'usage.csv'
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('cu-usage-{0}.csv' -f $PID)
    if (-not (Test-Path $global:cu_local)) {
        New-Item -ItemType Directory -Path $global:cu_local -Force | Out-Null
    }

    # 임시 파일로 받아 비교한 뒤 교체한다 (전송·해석 실패 시 기존 파일 보존)
    # BatchMode: 작업 스케줄러 같은 무인 실행에서 암호 입력을 기다리며 멈추지 않도록 한다
    scp -q -o BatchMode=yes -o ConnectTimeout=15 -o RemoteCommand=none "$($global:cu_host):claude-usage/usage.csv" $tmp
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Warning '내려받기 실패 - 기존 파일은 그대로 둡니다. (cu-status 로 서버 상태 확인)'
        return
    }
    try {
        $old = if (Test-Path $dst) { @(Import-Csv $dst) } else { @() }
        $new = @(Import-Csv $tmp)
    }
    catch {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Warning ('CSV 해석 실패 - 기존 파일은 그대로 둡니다. ({0})' -f $_.Exception.Message)
        return
    }

    $oldTs   = [System.Collections.Generic.HashSet[string]]::new([string[]]@($old | ForEach-Object { $_.ts }))
    $newTs   = [System.Collections.Generic.HashSet[string]]::new([string[]]@($new | ForEach-Object { $_.ts }))
    $added   = @($new | Where-Object { -not $oldTs.Contains($_.ts) } | Sort-Object ts)
    $missing = @($old | Where-Object { -not $newTs.Contains($_.ts) })
    # 파일 순서가 아니라 가장 늦은 시각을 '마지막'으로 본다
    $oldLast = $old | ForEach-Object { $_.ts } | Sort-Object | Select-Object -Last 1
    $newLast = $new | ForEach-Object { $_.ts } | Sort-Object | Select-Object -Last 1

    # 서버에 없는 기존 기록이 있으면 덮어쓰기 전에 백업한다
    $backup = $null
    if ($missing.Count -gt 0) {
        $backup = '{0}.bak-{1}' -f $dst, (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item $dst $backup
    }
    Move-Item $tmp $dst -Force

    $ko  = [cultureinfo]'ko-KR'
    $t16 = { param($ts) if ($ts) { $ts.Substring(0, [Math]::Min(16, $ts.Length)) } else { '-' } }

    Write-Host ''
    Write-Host (' cu-pull  {0} -> {1}' -f $global:cu_host, $dst) -ForegroundColor Cyan
    Write-Host ''
    if ($old.Count) {
        Write-Host (' 기존  {0,5}건 · 마지막 {1}' -f $old.Count, (& $t16 $oldLast))
    }
    else {
        Write-Host ' 기존     없음 (처음 받음)'
    }
    Write-Host (' 서버  {0,5}건 · 마지막 {1}' -f $new.Count, (& $t16 $newLast))

    if ($added.Count) {
        $err = @($added | Where-Object { $_.status -eq 'ERROR' }).Count
        Write-Host (' 신규  {0,5}건 · {1} ~ {2}' -f $added.Count, (& $t16 $added[0].ts), (& $t16 $added[-1].ts)) -ForegroundColor Yellow -NoNewline
        if ($err) { Write-Host ('  (수집 실패 {0}건)' -f $err) -ForegroundColor Red } else { Write-Host '' }
        foreach ($g in ($added | Group-Object { $_.ts.Substring(0, 10) } | Sort-Object Name)) {
            $d = [datetime]::ParseExact($g.Name, 'yyyy-MM-dd', $null)
            $e = @($g.Group | Where-Object { $_.status -eq 'ERROR' }).Count
            Write-Host ('        {0,-9} {1,3}건  {2} ~ {3}{4}' -f ('{0}/{1}({2})' -f $d.Month, $d.Day, $d.ToString('ddd', $ko)), $g.Count,
                $g.Group[0].ts.Substring(11, 5), $g.Group[-1].ts.Substring(11, 5),
                $(if ($e) { '  실패 {0}건' -f $e } else { '' })) -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host ' 신규     없음 (서버와 동일)' -ForegroundColor DarkGray
    }
    if ($missing.Count) {
        Write-Warning ('서버에 없는 기존 기록 {0}건 - 덮어쓰기 전에 백업함: {1}' -f $missing.Count, $backup)
    }

    $last = @($new | Where-Object { $_.status -eq 'OK' } | Sort-Object ts) | Select-Object -Last 1
    if ($last) {
        Write-Host ''
        Write-Host (' 최신값 전체 {0} · {1} {2} · 5시간 창 {3}  ({4})' -f
            $last.week_all_pct, $last.model_name, $last.week_model_pct, $last.session_pct, (& $t16 $last.ts))
    }
    Write-Host ''
    Write-Host (' 뷰어 : {0}' -f (Join-Path $global:cu_local 'viewer.html')) -ForegroundColor DarkGray
    Write-Host ''
}

function cu-help {
    # Claude 사용량 수집기 명령 목록을 출력한다.
    $cmds = @(
        @{ Name = 'cu-status'; Desc = '수집기 점검 - cron 등록/누적 건수/마지막 수집/로그인 상태' },
        @{ Name = 'cu-report'; Desc = '누적 요약 - 주차별 최고치와 요일·시간대 평균' },
        @{ Name = 'cu-run   '; Desc = '지금 한 번 더 수집 (예정 시각 외, 남용하지 말 것)' },
        @{ Name = 'cu-pull  '; Desc = 'usage.csv 를 이 PC로 내려받고 신규 기록 요약' }
    )

    Write-Host ''
    Write-Host ' Claude 사용량 수집기' -ForegroundColor Cyan
    Write-Host (' {0}:{1} · 월~금 06~18시 매시 자동 수집' -f $global:cu_host, $global:cu_remote) -ForegroundColor DarkGray
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
