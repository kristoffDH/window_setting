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
        Write-Warning ('기동했지만 포트 {0} 대기가 확인되지 않습니다. serve.log 를 확인하세요.' -f $global:cu_port)
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
    $log = Join-Path $global:cu_local 'serve.log'
    if (Test-Path $log) { Get-Content $log -Tail 3 -Encoding utf8 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray } }
}

function cu-help {
    # Claude 사용량 수집기 명령 목록을 출력한다.
    $cmds = @(
        @{ Name = 'cu-status'; Desc = '수집기 점검 - cron 등록/누적 건수/마지막 수집/로그인 상태' },
        @{ Name = 'cu-report'; Desc = '누적 요약 - 주차별 최고치와 요일·시간대 평균' },
        @{ Name = 'cu-run   '; Desc = '지금 한 번 더 수집 (예정 시각 외, 남용하지 말 것)' },
        @{ Name = 'cu-pull  '; Desc = 'usage.csv 를 이 PC로 내려받고 신규 기록 요약' },
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
# Claude 사용량 수집기(test-ex) 영역 End
#########################################################
