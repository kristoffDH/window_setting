#########################################################
# Claude 사용량 수집기(test-in) 영역 Start
#########################################################
# test-in 서버의 ~/claude-usage/ 수집기를 이 PC에서 다루는 명령 모음. (2026-10-21 test-ex 에서 이전)
# 서버는 월~금 06~18시(KST) 매시 정각에 claude /usage 를 찍어 usage.csv 에 누적한다.
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

function cu-local {
    # 이 PC에서 사용률을 지금 한 번 수집 (서버 로그인이 풀렸을 때 대신 쓰는 보조 수집, local.csv 에 쌓임)
    pwsh -NoProfile -File (Join-Path $global:cu_local 'local-collect.ps1')
    if (Test-Path $global:cu_local_csv) { Get-Content $global:cu_local_csv -Tail 1 -Encoding utf8 | ForEach-Object { Write-Host " $_" -ForegroundColor DarkGray } }
}

# 파일 구성: server.csv = 서버 원본 사본, local.csv = 이 PC 보조 수집분(local-collect.ps1),
#            usage.csv = 둘을 합친 결과 (뷰어가 읽는 파일)
$global:cu_server_csv = Join-Path $global:cu_local 'server.csv'
$global:cu_local_csv  = Join-Path $global:cu_local 'local.csv'
$global:cu_pull_ok    = $null   # 마지막 cu-pull 의 내려받기 성공 여부 (pull-task.ps1 알림용)

function cu-merge {
    # fnc-ignore
    # 서버 기록을 기준으로 usage.csv 를 만든다. 서버에 정상값이 없는 시간대(로그인 만료 등으로 ERROR 이거나 행이 없음)만
    # 이 PC 수집분으로 채운다. 같은 시간대에 둘 다 정상값이면 전체 사용률 차이로 계정이 같은지 확인한다.
    $dst  = Join-Path $global:cu_local 'usage.csv'
    $srv  = if (Test-Path $global:cu_server_csv) { @(Import-Csv $global:cu_server_csv) } else { @() }
    $loc  = if (Test-Path $global:cu_local_csv) { @(Import-Csv $global:cu_local_csv | Where-Object { $_.status -eq 'OK' }) } else { @() }
    $hour = { param($r) $r.ts.Substring(0, [Math]::Min(13, $r.ts.Length)) }   # 'yyyy-MM-dd HH'

    $srvOk = @{}
    foreach ($r in $srv) { if ($r.status -eq 'OK') { $srvOk[(& $hour $r)] = $r } }
    $fill  = @($loc | Where-Object { -not $srvOk.ContainsKey((& $hour $_)) })
    $fillH = [System.Collections.Generic.HashSet[string]]::new([string[]]@($fill | ForEach-Object { & $hour $_ }))
    $keep  = @($srv | Where-Object { $_.status -eq 'OK' -or -not $fillH.Contains((& $hour $_)) })
    $rows  = @(@($keep) + @($fill) | Sort-Object ts)

    $num = { param($v) if ($v -match '^(\d+)') { [int]$Matches[1] } else { $null } }
    $mismatch = @($loc | Where-Object {
            $s = $srvOk[(& $hour $_)]
            $s -and ($a = & $num $s.week_all_pct) -ne $null -and ($b = & $num $_.week_all_pct) -ne $null -and [Math]::Abs($a - $b) -gt 3
        })

    if ($rows.Count) {
        $tmp = '{0}.tmp' -f $dst
        $rows | Export-Csv $tmp -NoTypeInformation -UseQuotes AsNeeded -Encoding utf8
        Move-Item $tmp $dst -Force
    }
    [pscustomobject]@{ Rows = $rows; Filled = $fill; Mismatch = $mismatch }
}

function cu-pull {
    # 서버의 usage.csv 를 내려받아 이 PC 수집분과 합친다 (서버 기준, 서버가 실패한 시간대만 이 PC 값으로 채움)
    $dst = $global:cu_server_csv
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('cu-usage-{0}.csv' -f $PID)
    if (-not (Test-Path $global:cu_local)) {
        New-Item -ItemType Directory -Path $global:cu_local -Force | Out-Null
    }
    # 처음 실행이면 기존 usage.csv(서버 사본이던 파일)를 비교 기준으로 쓴다
    if (-not (Test-Path $dst) -and (Test-Path (Join-Path $global:cu_local 'usage.csv'))) {
        Copy-Item (Join-Path $global:cu_local 'usage.csv') $dst
    }

    # 임시 파일로 받아 비교한 뒤 교체한다 (전송·해석 실패 시 기존 파일 보존)
    # BatchMode: 작업 스케줄러 같은 무인 실행에서 암호 입력을 기다리며 멈추지 않도록 한다
    scp -q -o BatchMode=yes -o ConnectTimeout=15 -o RemoteCommand=none "$($global:cu_host):claude-usage/usage.csv" $tmp
    $global:cu_pull_ok = ($LASTEXITCODE -eq 0 -and (Test-Path $tmp))
    if (-not $global:cu_pull_ok) {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Warning '내려받기 실패 - 서버 사본은 그대로 두고 이 PC 수집분만 합칩니다. (cu-status 로 서버 상태 확인)'
        $m = cu-merge
        Write-Host (' 보충  {0,5}건 (이 PC 수집분, 서버 기록이 없거나 실패한 시간대)' -f $m.Filled.Count) -ForegroundColor DarkGray
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

    $m = cu-merge
    if ($m.Filled.Count) {
        Write-Host (' 보충  {0,5}건 · 이 PC 수집분으로 서버 실패 시간대를 채움 ({1} ~ {2})' -f $m.Filled.Count,
            (& $t16 $m.Filled[0].ts), (& $t16 $m.Filled[-1].ts)) -ForegroundColor Yellow
    }
    if ($m.Mismatch.Count) {
        Write-Warning ('같은 시각인데 서버와 이 PC의 전체 사용률이 3%p 넘게 다른 기록 {0}건 - 이 PC의 claude 가 다른 계정으로 로그인됐을 수 있습니다.' -f $m.Mismatch.Count)
    }

    $last = @($m.Rows | Where-Object { $_.status -eq 'OK' } | Sort-Object ts) | Select-Object -Last 1
    if ($last) {
        Write-Host ''
        Write-Host (' 최신값 전체 {0} · {1} {2} · 5시간 창 {3}  ({4})' -f
            $last.week_all_pct, $last.model_name, $last.week_model_pct, $last.session_pct, (& $t16 $last.ts))
    }
    Write-Host ''
    Write-Host (' 뷰어 : {0}' -f (Join-Path $global:cu_local 'viewer.html')) -ForegroundColor DarkGray
    Write-Host ''
}

$global:cu_port      = 8765
$global:cu_allowfile = Join-Path $global:cu_local 'serve.conf'   # 접속 허용 대역(CIDR)을 한 줄 적어 둔 파일

function cu-serve-pid {
    # fnc-ignore
    (Get-NetTCPConnection -LocalPort $global:cu_port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1).OwningProcess
}

function cu-serve-ip {
    # fnc-ignore
    (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1).IPAddress
}

function cu-serve {
    # 뷰어 웹 서버 기동 - 팀원이 브라우저로 접속 (이미 떠 있으면 상태만 표시)
    $running = cu-serve-pid
    if ($running) {
        Write-Host (' 이미 실행 중 · PID {0} · http://{1}:{2}/' -f $running, (cu-serve-ip), $global:cu_port) -ForegroundColor DarkGray
        return
    }
    if (-not (Test-Path $global:cu_allowfile)) {
        Write-Warning ('허용 대역 파일이 없습니다: {0}  (예: 10.0.0.0/24 를 한 줄 적어 두세요)' -f $global:cu_allowfile)
        return
    }
    $allow = (Get-Content $global:cu_allowfile | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | Select-Object -First 1).Trim()
    $pyw = python -c "import os, sys; print(os.path.join(os.path.dirname(sys.executable), 'pythonw.exe'))"
    if (-not (Test-Path $pyw)) { Write-Warning "pythonw.exe 를 찾지 못했습니다: $pyw"; return }

    # WMI 로 띄워야 호출한 셸이 닫혀도 서버가 살아남는다 (자식 프로세스로 띄우면 같이 정리됨)
    $cmd = '"{0}" serve.py --allow {1} --port {2} --bind 0.0.0.0' -f $pyw, $allow, $global:cu_port
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; CurrentDirectory = $global:cu_local }
    if ($r.ReturnValue -ne 0) { Write-Warning "서버 기동 실패 (코드 $($r.ReturnValue))"; return }

    foreach ($i in 1..10) { Start-Sleep -Milliseconds 400; if (cu-serve-pid) { break } }
    $now = cu-serve-pid
    if ($now) {
        Write-Host ''
        Write-Host (' 서버 기동 · PID {0}' -f $now) -ForegroundColor Cyan
        Write-Host (' 팀원 접속 : http://{0}:{1}/' -f (cu-serve-ip), $global:cu_port)
        Write-Host (' 내 PC     : http://localhost:{0}/' -f $global:cu_port) -ForegroundColor DarkGray
        Write-Host (' 허용 대역 : {0} (+ 루프백)' -f $allow) -ForegroundColor DarkGray
        Write-Host ''
    }
    else {
        Write-Warning ('기동했지만 포트 {0} 대기가 확인되지 않습니다. logs\serve.log 를 확인하세요.' -f $global:cu_port)
    }
}

function cu-serve-stop {
    # 뷰어 웹 서버 중지
    $running = cu-serve-pid
    if (-not $running) { Write-Host ' 실행 중인 서버가 없습니다.' -ForegroundColor DarkGray; return }
    Stop-Process -Id $running -Force
    Start-Sleep -Milliseconds 500
    if (cu-serve-pid) { Write-Warning "중지 실패 - PID $running 확인 필요" }
    else { Write-Host (' 서버 중지 · PID {0}' -f $running) -ForegroundColor Cyan }
}

function cu-serve-status {
    # 뷰어 웹 서버 상태 확인 (PID·접속 주소·최근 로그)
    $running = cu-serve-pid
    if ($running) { Write-Host (' 실행 중 · PID {0} · http://{1}:{2}/' -f $running, (cu-serve-ip), $global:cu_port) -ForegroundColor Cyan }
    else { Write-Host ' 중지됨 (cu-serve 로 기동)' -ForegroundColor DarkGray }
    $log = Join-Path $global:cu_local 'logs\serve.log'
    if (Test-Path $log) { Get-Content $log -Tail 3 -Encoding utf8 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray } }
}

function cu-help {
    # Claude 사용량 수집기 명령 목록을 출력한다.
    $cmds = @(
        @{ Name = 'cu-status'; Desc = '수집기 점검 - cron 등록/누적 건수/마지막 수집/로그인 상태' },
        @{ Name = 'cu-report'; Desc = '누적 요약 - 주차별 최고치와 요일·시간대 평균' },
        @{ Name = 'cu-run   '; Desc = '지금 한 번 더 수집 (예정 시각 외, 남용하지 말 것)' },
        @{ Name = 'cu-pull  '; Desc = '서버 기록을 받아 이 PC 수집분과 합침 (서버 기준, 서버 실패 시간대만 보충)' },
        @{ Name = 'cu-local '; Desc = '이 PC에서 지금 한 번 수집 (서버 로그인 만료 대비 보조 수집)' },
        @{ Name = 'cu-serve '; Desc = '뷰어 웹 서버 기동 (팀원 접속용, 허용 대역만)' },
        @{ Name = 'cu-serve-stop'; Desc = '뷰어 웹 서버 중지' },
        @{ Name = 'cu-serve-status'; Desc = '뷰어 웹 서버 상태와 최근 로그' }
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
# Claude 사용량 수집기(test-in) 영역 End
#########################################################
