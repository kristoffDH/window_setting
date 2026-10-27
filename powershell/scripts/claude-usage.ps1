#########################################################
# Claude 사용량 수집기(test-in) 영역 Start
#########################################################
# test-in 서버의 ~/claude-usage/ 수집기를 이 PC에서 다루는 명령 모음. (2026-10-21 test-ex 에서 이전)
# 서버는 월~금 06~18시(KST) 매시 정각에 claude /usage 를 찍어 usage.csv 에 누적하고, 뷰어(:8765)도 서버가 띄운다.
# 이 PC 는 보조 수집(local.csv) → 서버 전송(cu-pull) → 실패 알림(pull-task.ps1)만 한다.
# 주간 사용률은 계정 단위 값이라 여러 PC에 흩어진 사용량이 한 곳에 모인다.
#
# 서버 호스트(ssh 설정)에 RemoteCommand 가 걸려 있으면 원격 명령을 함께 주려면
# 반드시 -o RemoteCommand=none 이 필요하다.
# (빠뜨리면 "Cannot execute command-line and remote command." 로 실패한다)

$global:cu_host   = 'test-in'
$global:cu_remote = '~/claude-usage'
$global:cu_local  = 'C:\Work\claude-usage'

function cu-ssh {
    # fnc-ignore
    param([Parameter(Mandatory)][string]$Script)
    # BatchMode: 작업 스케줄러 같은 무인 실행에서 암호 입력을 기다리며 멈추지 않도록 한다
    ssh -T -o BatchMode=yes -o ConnectTimeout=15 -o RemoteCommand=none $global:cu_host "$global:cu_remote/$Script"
}

function cu-ssh-cmd {
    # fnc-ignore
    param([Parameter(Mandatory)][string]$Command)
    ssh -T -o BatchMode=yes -o ConnectTimeout=15 -o RemoteCommand=none $global:cu_host $Command
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

function cu-local {
    # 이 PC에서 사용률을 지금 한 번 수집 (서버 로그인이 풀렸을 때 대신 쓰는 보조 수집, local.csv 에 쌓임)
    pwsh -NoProfile -File (Join-Path $global:cu_local 'local-collect.ps1')
    if (Test-Path $global:cu_local_csv) { Get-Content $global:cu_local_csv -Tail 1 -Encoding utf8 | ForEach-Object { Write-Host " $_" -ForegroundColor DarkGray } }
}

# 파일 구성: local.csv = 이 PC 보조 수집분(local-collect.ps1), server.csv = 서버 usage.csv 백업 사본(알림 판단용)
# 병합(서버 우선, 빈 시간대만 local.csv 로 채움)과 뷰어는 서버가 한다: ~/claude-usage/merge.py -> web/usage.csv
$global:cu_server_csv = Join-Path $global:cu_local 'server.csv'
$global:cu_local_csv  = Join-Path $global:cu_local 'local.csv'
$global:cu_pull_ok    = $null   # 마지막 cu-pull 의 내려받기 성공 여부 (pull-task.ps1 알림용)

function cu-pull {
    # 이 PC 수집분(local.csv)을 서버에 올려 병합시키고, 서버 usage.csv 를 백업 사본(server.csv)으로 받는다
    $dst = $global:cu_server_csv

    # 1) local.csv 전송 + 서버 병합 (실패해도 내려받기는 계속한다)
    if (Test-Path $global:cu_local_csv) {
        scp -q -o BatchMode=yes -o ConnectTimeout=15 -o RemoteCommand=none $global:cu_local_csv "$($global:cu_host):claude-usage/local.csv"
        if ($LASTEXITCODE -eq 0) { $mergeOut = cu-ssh 'merge.py' 2>&1 }
        else { Write-Warning 'local.csv 전송 실패 - 서버 병합은 다음 실행 때 다시 시도합니다.' }
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('cu-usage-{0}.csv' -f $PID)
    if (-not (Test-Path $global:cu_local)) {
        New-Item -ItemType Directory -Path $global:cu_local -Force | Out-Null
    }
    # 2) 서버 usage.csv 를 임시 파일로 받아 비교한 뒤 교체한다 (전송·해석 실패 시 기존 파일 보존)
    # BatchMode: 작업 스케줄러 같은 무인 실행에서 암호 입력을 기다리며 멈추지 않도록 한다
    scp -q -o BatchMode=yes -o ConnectTimeout=15 -o RemoteCommand=none "$($global:cu_host):claude-usage/usage.csv" $tmp
    $global:cu_pull_ok = ($LASTEXITCODE -eq 0 -and (Test-Path $tmp))
    if (-not $global:cu_pull_ok) {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Warning '내려받기 실패 - 백업 사본(server.csv)은 그대로 둡니다. (cu-status 로 서버 상태 확인)'
        return
    }
    try {
        $old = if (Test-Path $dst) { @(Import-Csv $dst) } else { @() }
        $new = @(Import-Csv $tmp)
    }
    catch {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        $global:cu_pull_ok = $false
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
        $backup = Join-Path $global:cu_local ('backup\server.csv.bak-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
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

    # 서버 병합 결과 (merge.py 출력: 보충 건수, 다른 계정 의심 경고)
    if ($mergeOut) {
        foreach ($l in @($mergeOut)) { Write-Host "$l" -ForegroundColor $(if ("$l" -match '\[!\]') { 'Red' } else { 'DarkGray' }) }
    }

    $last = @($new | Where-Object { $_.status -eq 'OK' } | Sort-Object ts) | Select-Object -Last 1
    if ($last) {
        Write-Host ''
        Write-Host (' 최신값 전체 {0} · {1} {2} · 5시간 창 {3}  ({4})' -f
            $last.week_all_pct, $last.model_name, $last.week_model_pct, $last.session_pct, (& $t16 $last.ts))
    }
    Write-Host ''
    Write-Host (' 뷰어 : {0}' -f (cu-viewer-url)) -ForegroundColor DarkGray
    Write-Host ''
}

$global:cu_port = 8765
$global:cu_unit = 'claude-usage-viewer'   # 서버의 뷰어 웹 서버 systemd 서비스 (10.10.70.0/24 만 허용)

function cu-viewer-url {
    # fnc-ignore
    # ssh 설정의 HostName 을 그대로 쓴다 (cu_host 는 ssh 별칭이라 DNS 로는 안 풀린다)
    $ip = ssh -G $global:cu_host | Select-String '^hostname ' | ForEach-Object { ($_.Line -split ' ')[1] } | Select-Object -First 1
    'http://{0}:{1}/' -f $ip, $global:cu_port
}

function cu-serve {
    # 서버의 뷰어 웹 서버 기동 (systemd, 부팅 시 자동 기동됨)
    cu-ssh-cmd "systemctl start $global:cu_unit && systemctl is-active $global:cu_unit"
    Write-Host (' 팀원 접속 : {0}' -f (cu-viewer-url)) -ForegroundColor Cyan
}

function cu-serve-stop {
    # 서버의 뷰어 웹 서버 중지 (다음 부팅 때는 다시 기동됨)
    cu-ssh-cmd "systemctl stop $global:cu_unit; systemctl is-active $global:cu_unit"
}

function cu-serve-status {
    # 서버의 뷰어 웹 서버 상태와 최근 로그
    cu-ssh-cmd "systemctl is-active $global:cu_unit; tail -n 3 $global:cu_remote/web/logs/serve.log"
    Write-Host (' 팀원 접속 : {0}' -f (cu-viewer-url)) -ForegroundColor DarkGray
}

function cu-help {
    # Claude 사용량 수집기 명령 목록을 출력한다.
    $cmds = @(
        @{ Name = 'cu-status'; Desc = '수집기 점검 - cron 등록/누적 건수/마지막 수집/로그인 상태' },
        @{ Name = 'cu-report'; Desc = '누적 요약 - 주차별 최고치와 요일·시간대 평균' },
        @{ Name = 'cu-run   '; Desc = '지금 한 번 더 수집 (예정 시각 외, 남용하지 말 것)' },
        @{ Name = 'cu-pull  '; Desc = '이 PC 수집분을 서버에 올려 병합 + 서버 기록을 백업 사본으로 받음' },
        @{ Name = 'cu-local '; Desc = '이 PC에서 지금 한 번 수집 (서버 로그인 만료 대비 보조 수집)' },
        @{ Name = 'cu-serve '; Desc = '서버 뷰어 웹 서버 기동 (10.10.70.0/24 만 허용)' },
        @{ Name = 'cu-serve-stop'; Desc = '서버 뷰어 웹 서버 중지' },
        @{ Name = 'cu-serve-status'; Desc = '서버 뷰어 웹 서버 상태와 최근 로그' }
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
    Write-Host ('{0}:{1}/usage.csv (서버) + local.csv (이 PC) -> web/usage.csv' -f $global:cu_host, $global:cu_remote)
    Write-Host ' 뷰어   ' -ForegroundColor DarkGray -NoNewline
    Write-Host (cu-viewer-url)
    Write-Host ' 제거   ' -ForegroundColor DarkGray -NoNewline
    Write-Host ("ssh -T -o RemoteCommand=none {0} '{1}/uninstall.sh --purge-data --purge-claude'" -f $global:cu_host, $global:cu_remote)
    Write-Host ''
}

#########################################################
# Claude 사용량 수집기(test-in) 영역 End
#########################################################
