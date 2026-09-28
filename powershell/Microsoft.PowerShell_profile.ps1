#########################################################
# 외부 스크립트 로더 호출
#########################################################
# script-loader.ps1은 예전에 profile.ps1(CurrentUserAllHosts)이라 PowerShell이 자동으로 읽었다.
# 이름을 바꿔 자동 로드가 안 되므로 여기서 직접 읽는다 (예전과 같은 순서: 로더 → 폴더 스크립트 → 아래 본문).
$script_loader_file = Join-Path (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) 'script-loader.ps1'

if (Test-Path -LiteralPath $script_loader_file) {
    . $script_loader_file
}
else {
    Write-Warning ("스크립트 로더를 찾지 못했습니다: {0}" -f $script_loader_file)
}


#########################################################
# 셸 초기화 영역 Start - 로드 순서 중요
#########################################################

# init 스크립트 캐시 헬퍼: 캐시 1행(# EXE=경로)에 exe 경로를 기록해 두고,
# exe가 캐시보다 새로우면(업그레이드/재설치) 캐시를 다시 만든다.
# DependentFiles(테마 등 init 결과에 영향을 주는 파일)가 캐시보다 새로울 때도 다시 만든다.
# Get-Command는 세션 첫 호출이 ~200ms라 캐시가 유효한 동안에는 호출하지 않는다.
function Update-InitCache {
    # fnc-ignore
    param(
        [string]$CachePath,
        [string]$Command,
        [scriptblock]$Generate,
        [string[]]$DependentFiles = @()
    )

    # 검사 경로는 cmdlet 초기화 비용(세션 첫 호출 수십 ms)을 피하려고 .NET API만 쓴다.
    $cacheValid = $false
    try {
        if ([System.IO.File]::Exists($CachePath)) {
            $cacheTime = [System.IO.File]::GetLastWriteTime($CachePath)
            $exePath = ([System.IO.File]::ReadAllLines($CachePath)[0]) -replace '^# EXE=', ''
            $exeTime = [System.IO.File]::GetLastWriteTime($exePath)
            $cacheValid = ($exeTime.Year -gt 1700) -and ($cacheTime -gt $exeTime)

            foreach ($dep in $DependentFiles) {
                if ($cacheValid -and
                    [System.IO.File]::Exists($dep) -and
                    [System.IO.File]::GetLastWriteTime($dep) -ge $cacheTime) {
                    $cacheValid = $false
                }
            }
        }
    }
    catch {
        $cacheValid = $false
    }

    if ($cacheValid) {
        return
    }

    $exePath = (Get-Command $Command).Source
    @("# EXE=$exePath") + (& $Generate) | Set-Content $CachePath -Encoding utf8
}

# oh-my-posh: init이 출력하는 스텁은 omp를 업그레이드하기 전까지 항상 같으므로
# 파일로 캐시해 매 시작마다 exe를 띄우는 비용(~300ms)을 줄인다.
# 주의: 스텁 안의 POSH_SESSION_ID는 exe가 init 때 테마와 함께 등록해 둔 값이므로
# 그대로 재사용해야 한다. 다른 값으로 바꾸면 미등록 세션이라 기본 테마로 폴백한다.
$omp_init_cache = "$env:LOCALAPPDATA\pwsh-init-omp.ps1"
$omp_theme_file = "$HOME\.mytheme.omp.json"
$omp_init_gen = { oh-my-posh init pwsh --config "$HOME/.mytheme.omp.json" }

# 테마를 고치면 새 창에서 자동 반영되도록 테마 파일도 캐시 유효성 검사에 포함한다.
# (omp는 init 때 테마를 세션 캐시에 등록하므로, 스텁을 재사용하면 옛 테마가 남는다)
Update-InitCache -CachePath $omp_init_cache -Command 'oh-my-posh' -Generate $omp_init_gen -DependentFiles $omp_theme_file

# 캐시된 스텁에 세션 ID가 없거나(손상), 세션 ID에 연결된 omp 세션 캐시가 지워진
# 경우(oh-my-posh cache clear 등)에는 스텁이 실행돼도 기본 테마로 폴백하므로 다시 만든다.
$omp_stub_text = [System.IO.File]::ReadAllText($omp_init_cache)
$omp_sid = [regex]::Match($omp_stub_text, 'POSH_SESSION_ID = "([^"]+)"').Groups[1].Value
$omp_dir = [regex]::Match($omp_stub_text, "& '([^']+)\\init\.[^']+\.ps1'").Groups[1].Value

if (-not $omp_sid -or ($omp_dir -and -not [System.IO.File]::Exists("$omp_dir\pwsh.$omp_sid.omp.cache"))) {
    Remove-Item $omp_init_cache -ErrorAction SilentlyContinue
    Update-InitCache -CachePath $omp_init_cache -Command 'oh-my-posh' -Generate $omp_init_gen
}

try {
    . $omp_init_cache
}
catch {
    # 캐시가 가리키는 omp 내부 init 파일이 사라진 경우: 캐시를 강제 재생성 후 다시 실행한다.
    Remove-Item $omp_init_cache -ErrorAction SilentlyContinue
    Update-InitCache -CachePath $omp_init_cache -Command 'oh-my-posh' -Generate $omp_init_gen
    . $omp_init_cache
}

# zoxide는 프롬프트 함수를 감싸므로 oh-my-posh 초기화 이후에 실행해야 한다.
# init 출력은 zoxide 버전이 바뀌기 전까지 동일하므로 캐시해 exe 호출을 줄인다.
$zoxide_init_cache = "$env:LOCALAPPDATA\pwsh-init-zoxide.ps1"

Update-InitCache -CachePath $zoxide_init_cache -Command 'zoxide' -Generate { zoxide init powershell }

. $zoxide_init_cache

# PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -Colors @{ Parameter = '#7E8BA3' }
Set-PSReadLineOption -Colors @{ Operator = '#7E8BA3' }

# 오타는 히스토리 파일에 남기지 않는다. 구문 오류이거나 부르려는 명령이 없으면 MemoryOnly로 돌려
# 이 창에서는 위/아래 키로 불러와 고칠 수 있게 하되 파일에는 쓰지 않는다.
# (Enter 시점에는 실행 결과를 알 수 없으므로, 명령 자체는 정상인데 실패한 경우는 평소처럼 저장된다)
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)

    $both = [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    $memoryOnly = [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly

    try {
        # 비밀값이 든 줄을 거르는 PSReadLine 기본 판단을 먼저 따른다.
        $default = [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
        if ($default -ne $both) { return $default }

        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$null, [ref]$errors)
        if ($errors.Count -gt 0) { return $memoryOnly }

        # 이름이 글자 그대로 적힌 명령만 확인한다 (& $exe 처럼 변수로 부르는 건 판단하지 않는다).
        $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)

        foreach ($command in $commands) {
            $name = $command.GetCommandName()
            if (-not $name) { continue }
            if (Get-Command -Name $name -ErrorAction Ignore) { continue }
            if (Test-Path -LiteralPath $name -ErrorAction Ignore) { continue }   # .\script.ps1 처럼 경로로 실행하는 경우

            return $memoryOnly
        }

        return $both
    }
    catch {
        # 판단 중 문제가 생기면 기록이 빠지는 것보다 평소대로 저장하는 편이 낫다.
        return $both
    }
}

#########################################################
# 셸 초기화 영역 End
#########################################################


#########################################################
# 전역 변수 / Alias 영역 Start
#########################################################

# config path setting
$omp_config_file = "$env:HOMEPATH/.mytheme.omp.json"
$history_backup_file_path = "$env:APPDATA/Microsoft/Windows/PowerShell/PSReadLine"
$his_file = "$history_backup_file_path/ConsoleHost_history.txt"

# alias는 호출 시점에 이름이 해석되므로 대상 함수 정의(아래 영역)보다 앞에 둘 수 있다.
Set-Alias ls lsd
Set-Alias vi nvim
Set-Alias grep findstr
Set-Alias zz zi
Set-Alias -Name c -Value ssh-con
Set-Alias his Get-History

#########################################################
# 전역 변수 / Alias 영역 End
#########################################################


#########################################################
# 프롬프트(Oh My Posh) 관리 영역 Start
#########################################################

function Update-OmpTag {
    # fnc-ignore
    # 로컬 IP를 조회해 프롬프트 태그(OMP_TAG)에 반영한다. IP를 못 찾으면 태그를 지운다.
    $ip = $null

    try {
        # UDP connect는 패킷을 보내지 않고 라우팅 테이블 조회만으로 로컬 IP를 결정한다.
        $udp = [System.Net.Sockets.UdpClient]::new()
        try {
            $udp.Connect('8.8.8.8', 53)
            $ip = $udp.Client.LocalEndPoint.Address.IPAddressToString
        }
        finally {
            $udp.Dispose()
        }
    }
    catch {}

    # 라우팅 조회가 실패했거나 무의미한 값이면 기본 게이트웨이가 있는 어댑터에서 조회한다.
    if (-not $ip -or $ip -eq '0.0.0.0' -or $ip.StartsWith('169.254.')) {
        $ip = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
            Select-Object -ExpandProperty IPv4Address -First 1 |
            Select-Object -ExpandProperty IPAddress -First 1
    }

    if ($ip) {
        $env:OMP_TAG = "IP : $ip"
    }
    else {
        Remove-Item Env:OMP_TAG -ErrorAction SilentlyContinue
    }
}

Update-OmpTag

function reload
{
    # OMP_TAG를 갱신하고 oh-my-posh 테마를 다시 읽어 프롬프트를 새로고침한다. (프로필 변경은 새 창에서 반영)
    Update-OmpTag

    # omp 모듈을 다시 import하면 zoxide가 감싸 둔 prompt가 덮여 z의 폴더 학습이 끊긴다.
    # 그래서 init CLI로 새 테마 스냅샷만 등록하고 세션 ID/설정 경로 env만 바꾼다 (프롬프트는 매번 이 env로 렌더).
    $stub = (oh-my-posh init pwsh --config "$HOME\.mytheme.omp.json") -join "`n"
    $sessionId = [regex]::Match($stub, '\$env:POSH_SESSION_ID\s*=\s*"([^"]+)"').Groups[1].Value
    $configPath = [regex]::Match($stub, "\`$env:POSH_CONFIG\s*=\s*'([^']+)'").Groups[1].Value

    # 스텁 형식이 바뀌었거나 omp 모듈이 없으면 예전처럼 전체 init으로 폴백한다.
    if (-not $sessionId -or -not $configPath -or -not (Get-Module -Name 'oh-my-posh-core')) {
        $stub | Invoke-Expression
        return
    }

    $env:POSH_SESSION_ID = $sessionId
    $env:POSH_CONFIG = $configPath
}

function del-cache
{
    # oh-my-posh init 캐시(pwsh-init-omp.ps1)를 삭제한다. 새 창에서 현재 테마로 다시 만든다. (테마를 복사해 온 뒤 옛 테마가 남을 때)
    # 복사한 테마는 원래 수정 시각을 유지해 캐시보다 오래돼 보일 수 있어, 자동 재생성이 안 될 때 쓴다.
    $cache = $omp_init_cache

    if (-not (Test-Path -LiteralPath $cache)) {
        Write-Host ("삭제할 캐시가 없습니다: {0}" -f $cache) -ForegroundColor Yellow
        return
    }

    try {
        Remove-Item -LiteralPath $cache -ErrorAction Stop
    }
    catch {
        Write-Error ("캐시 삭제 실패: {0}" -f $_.Exception.Message)
        return
    }

    Write-Host ("oh-my-posh init 캐시를 삭제했습니다: {0}" -f $cache) -ForegroundColor Green
    Write-Host "새 창을 열면 현재 테마로 캐시를 다시 만듭니다." -ForegroundColor DarkCyan
}

#########################################################
# 프롬프트(Oh My Posh) 관리 영역 End
#########################################################


#########################################################
# 설정 파일 열기 / 백업 영역 Start
#########################################################

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
    code $omp_config_file
}

function ssh-config
{
    # ssh config 파일을 VSCode로 연다.
    code $Home/.ssh/config
}

function upload-cfg
{
    # PowerShell 프로필(+ 로더, 자동 로드 스크립트)과 oh-my-posh 테마를 win_term 저장소에 복사해 커밋하고 푸시한다.
    # (구 upload-pwsh + upload-omp 통합 — omp-mytheme 별도 저장소는 window_setting에 병합됨, 2026-08-10)
    $originalPath = Get-Location
    cd "C:\Users\hanssak\win_term\window_setting"
    cp $profile ./powershell/
    # 스크립트 로더(script-loader.ps1)와 자동 로드 폴더($my_scripts_dir)의 스크립트도 백업한다.
    cp $script_loader_file ./powershell/
    if ($global:my_scripts_dir -and (Test-Path $global:my_scripts_dir)) {
        $null = New-Item -ItemType Directory -Force -Path ./powershell/scripts
        cp (Join-Path $global:my_scripts_dir '*.ps1') ./powershell/scripts/
    }
    # oh-my-posh 테마도 같은 저장소의 omp-mytheme 폴더로 복사한다.
    cp $omp_config_file ./omp-mytheme/
    ls;
    git add .; git commit -m "update cfg"; git push;
    Set-Location -Path $originalPath
}

function upload-term
{
    # Windows Terminal 설정 파일을 win_term 저장소에 복사해 커밋하고 푸시한다.
    $originalPath = Get-Location
    cd "C:\Users\hanssak\win_term\window_setting"
    cp "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" ./window-term.setting.json
    ls;
    git add .; git commit -m "update terminal"; git push;
    Set-Location -Path $originalPath
}

#########################################################
# 설정 파일 열기 / 백업 영역 End
#########################################################


#########################################################
# 명령 히스토리 관리 영역 Start
#########################################################

function open-his
{
    # 명령 히스토리 파일을 VSCode로 연다.
    code "$his_file"
}

function his-all
{
    # 히스토리 파일에 쌓인 전체 명령을 화면에 모두 출력한다. (현재 창 기록만 보려면 his = Get-History)
    if (-not (Test-Path -LiteralPath $his_file)) {
        Write-Host ("히스토리 파일이 없습니다: {0}" -f $his_file) -ForegroundColor Yellow
        return
    }

    Get-Content -LiteralPath $his_file
}

function compact-his {
    # 히스토리 파일에서 빈 줄과 중복 명령을 제거한다(최근 항목 유지, .bak 백업).
    $path = "$his_file"

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "history 파일이 없습니다."
        return
    }

    $lines = Get-Content -LiteralPath $path
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $result = New-Object 'System.Collections.Generic.List[string]'

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($seen.Add($line)) {
            $result.Add($line)
        }
    }

    [array]::Reverse($result)

    Copy-Item -LiteralPath $path -Destination ($path + ".bak") -Force
    Set-Content -LiteralPath $path -Value $result -Encoding utf8

    Write-Host ("history 정리 완료: {0} -> {1}" -f $lines.Count, $result.Count) -ForegroundColor Green
    Write-Host ("backup: {0}.bak" -f $path) -ForegroundColor DarkCyan
}

#########################################################
# 명령 히스토리 관리 영역 End
#########################################################


#########################################################
# 일반 유틸리티 영역 Start
#########################################################

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

function down  # change directory downloads
{ 
    cd $Home/Downloads
}

#########################################################
# 일반 유틸리티 영역 End
#########################################################


#########################################################
# Git 단축 명령 영역 Start
#########################################################

function gs
{
    # git status
    git status
}

function gl
{
    # git pull
    git pull
}

function gp
{
    # git push
    git push
}

function gf
{
    # git fetch
    git fetch
}

#########################################################
# Git 단축 명령 영역 End
#########################################################


#########################################################
# 프로필 개발 도구 영역 Start
#########################################################

function Show-MyPalette {
    # 터미널/프롬프트에서 쓰는 색상 팔레트를 견본으로 출력한다.
    $esc = [char]27

    function Convert-HexToRgb {
        # fnc-ignore
        param([string]$Hex)
        $h = $Hex.Trim()
        if ($h.StartsWith('#')) { $h = $h.Substring(1) }
        [int]$r = [Convert]::ToInt32($h.Substring(0,2),16)
        [int]$g = [Convert]::ToInt32($h.Substring(2,2),16)
        [int]$b = [Convert]::ToInt32($h.Substring(4,2),16)
        return [pscustomobject]@{ R = $r; G = $g; B = $b }
    }

    function Convert-RgbToHex {
        # fnc-ignore
        param([int]$R, [int]$G, [int]$B)
        return ('#{0:X2}{1:X2}{2:X2}' -f $R,$G,$B)
    }

    function New-Tone {
        # fnc-ignore
        param(
            [string]$Hex,
            [double]$Factor,
            [string]$Suffix
        )
        $rgb = Convert-HexToRgb $Hex
        $r = [math]::Min([math]::Max([int]([math]::Round($rgb.R * $Factor)), 0), 255)
        $g = [math]::Min([math]::Max([int]([math]::Round($rgb.G * $Factor)), 0), 255)
        $b = [math]::Min([math]::Max([int]([math]::Round($rgb.B * $Factor)), 0), 255)
        $newHex = Convert-RgbToHex -R $r -G $g -B $b
        return [pscustomobject]@{
            Name = $Suffix
            Hex  = $newHex
        }
    }

    function Show-ColorRow {
        # fnc-ignore
        param(
            [string]$Title,
            [array]$Colors
        )

        $esc = [char]27
        Write-Host ""
        Write-Host "=== $Title ==="
        foreach ($c in $Colors) {
            $rgb = Convert-HexToRgb $c.Hex
            $R = $rgb.R; $G = $rgb.G; $B = $rgb.B
            $bg    = "$esc[48;2;${R};${G};${B}m"
            $reset = "$esc[0m"
            $name = $c.Name.PadRight(18)
            Write-Host ("{0}  {1}{2}  {3}" -f $bg, $reset, $name, $c.Hex)
        }
        Write-Host ""
    }

    # 1) Flat Remix 기본 팔레트
    $baseColors = @(
        @{ Name = "background";          Hex = "#1E1E1E" },
        @{ Name = "black";               Hex = "#232323" },
        @{ Name = "blue";                Hex = "#008DF8" },
        @{ Name = "brightBlack";         Hex = "#444444" },
        @{ Name = "brightBlue";          Hex = "#0092FF" },
        @{ Name = "brightCyan";          Hex = "#67FFF0" },
        @{ Name = "brightGreen";         Hex = "#9AFF87" },
        @{ Name = "brightPurple";        Hex = "#D19BFF" },
        @{ Name = "brightRed";           Hex = "#FF2740" },
        @{ Name = "brightWhite";         Hex = "#FFFFFF" },
        @{ Name = "brightYellow";        Hex = "#FFD242" },
        @{ Name = "cursorColor";         Hex = "#D41919" },
        @{ Name = "cyan";                Hex = "#00D8EB" },
        @{ Name = "foreground";          Hex = "#FFFFFF" },
        @{ Name = "green";               Hex = "#1A921C" },
        @{ Name = "purple";              Hex = "#B06CF5" },
        @{ Name = "red";                 Hex = "#FF000F" },
        @{ Name = "selectionBackground"; Hex = "#97A39D" },
        @{ Name = "white";               Hex = "#FFFFFF" },
        @{ Name = "yellow";              Hex = "#FFB900" }
    )

    # 2) 프롬프트에서 쓰는 악센트 색 + light/dark 변형을 Extra에 합치기
    $accentBase = @(
        @{ Name = "tagAccent"; Hex = "#17D7A0" },
        @{ Name = "memIcon";   Hex = "#83769C" },
        @{ Name = "cpuIcon";   Hex = "#33658A" }
    )

    $extraColors = @()

    foreach ($a in $accentBase) {
        # 기본 accent
        $extraColors += @{ Name = $a.Name; Hex = $a.Hex }
        # light/dark 톤
        $extraColors += New-Tone -Hex $a.Hex -Factor 1.2 -Suffix ("{0}_light" -f $a.Name)
        $extraColors += New-Tone -Hex $a.Hex -Factor 0.7 -Suffix ("{0}_dark"  -f $a.Name)
    }

    # 3) 추천 추가 색상들 
    $extraColors += @(
        @{ Name = "softFg";        Hex = "#C7CCD1" },
        @{ Name = "midBorder";     Hex = "#5C6773" },
        @{ Name = "hoverAccent";   Hex = "#7E8BA3" },
        @{ Name = "disabledText";  Hex = "#6B6B6B" },

        @{ Name = "accentBlue1";   Hex = "#3A86FF" },
        @{ Name = "accentBlue2";   Hex = "#4CC9F0" },
        @{ Name = "tealDeep";      Hex = "#2EC4B6" },
        @{ Name = "navyDeep";      Hex = "#264653" },

        @{ Name = "softOrange";    Hex = "#FF9E64" },
        @{ Name = "softRed";       Hex = "#FF6B6B" },
        @{ Name = "magenta";       Hex = "#FF79C6" },
        @{ Name = "violet";        Hex = "#B388FF" },

        @{ Name = "softBg";        Hex = "#252733" },  
        @{ Name = "softBgAlt";     Hex = "#2B3040" },  
        @{ Name = "panelBorder";   Hex = "#4B5563" },  
        @{ Name = "lineHighlight"; Hex = "#31364A" },  

        @{ Name = "statusGreen";   Hex = "#3DD68C" },  
        @{ Name = "statusYellow";  Hex = "#F6C453" },  
        @{ Name = "statusRed";     Hex = "#F75C7E" },  
        @{ Name = "statusBlue";    Hex = "#2F9BFF" },  

        @{ Name = "tagPink";       Hex = "#FF8EC7" },  
        @{ Name = "tagPinkDark";   Hex = "#D75A9C" },  
        @{ Name = "royalPurple";   Hex = "#6C4AB6" },  
        @{ Name = "indigo";        Hex = "#4953C4" },  

        @{ Name = "softCyan";      Hex = "#7FE7FF" },  
        @{ Name = "deepCyan";      Hex = "#008B9E" },  
        @{ Name = "mint";          Hex = "#9CF6E0" },  
        @{ Name = "deepMint";      Hex = "#0F9F8C" },  

        @{ Name = "warningOrange"; Hex = "#FFB347" },  
        @{ Name = "accentGold";    Hex = "#E9C46A" },  
        @{ Name = "graphLine1";    Hex = "#A3B9FF" },  
        @{ Name = "graphLine2";    Hex = "#89F0FF" },  

        @{ Name = "softPink";      Hex = "#FFB3D9" },  
        @{ Name = "deepPink";      Hex = "#E05297" },  
        @{ Name = "consoleBgAlt";  Hex = "#1F2430" },  
        @{ Name = "mutedBlue";     Hex = "#5C7CFA" },  
        @{ Name = "mutedTeal";     Hex = "#3CB9A4" },  
        @{ Name = "softLime";      Hex = "#B8F28D" },  
        @{ Name = "errorBg";       Hex = "#4A1F2F" },  
        @{ Name = "successBg";     Hex = "#123E3A" },  
        @{ Name = "infoBg";        Hex = "#102A43" },  
        @{ Name = "badgeBg";       Hex = "#3D3B5C" },  
            
        @{ Name = "mintLight";      Hex = "#9CF6E0" },
        @{ Name = "mintSoft";       Hex = "#B9FBC0" },
        @{ Name = "mintPale";       Hex = "#D8FFF4" },
        @{ Name = "tealSoft";       Hex = "#7FE7D6" },
        @{ Name = "tealDeep";       Hex = "#2EC4B6" },

        @{ Name = "cyanSoft";       Hex = "#89F0FF" },
        @{ Name = "skySoft";        Hex = "#BDE0FE" },
        @{ Name = "blueAccent";     Hex = "#3A86FF" },
        @{ Name = "navyDark";       Hex = "#102A43" },
        @{ Name = "blueGray";       Hex = "#5C6773" },

        @{ Name = "lavenderSoft";   Hex = "#CDB4DB" },
        @{ Name = "violetSoft";     Hex = "#B388FF" },
        @{ Name = "purpleDeep";     Hex = "#6C4AB6" },
        @{ Name = "badgePurple";    Hex = "#3D3B5C" },

        @{ Name = "roseSoft";       Hex = "#F7A8B8" },
        @{ Name = "pinkSoft";       Hex = "#FFB3D9" },
        @{ Name = "coralSoft";      Hex = "#FFB4A2" },
        @{ Name = "salmonSoft";     Hex = "#FF8A8A" },

        @{ Name = "yellowSoft";     Hex = "#FFF3B0" },
        @{ Name = "goldSoft";       Hex = "#E9C46A" },
        @{ Name = "amberSoft";      Hex = "#F6C453" },
        @{ Name = "orangeSoft";     Hex = "#FFB347" },

        @{ Name = "bgDeepMint";     Hex = "#123E3A" },
        @{ Name = "bgTealDark";     Hex = "#0B2E33" },
        @{ Name = "bgNavyDark";     Hex = "#102A43" },
        @{ Name = "bgPanelDark";    Hex = "#1F2430" },
        @{ Name = "borderMintDark"; Hex = "#256D63" }
    )

    Show-ColorRow -Title "Flat Remix base palette" -Colors $baseColors
    Show-ColorRow -Title "Extra matching colors"   -Colors $extraColors

    Write-Host "$esc[0m"
}

function fnc {
    # PROFILE에 정의된 함수 목록을 프로필 영역별로 묶어 설명과 함께 출력한다. (fnc <함수명>: 해당 함수만 표시)
    param([string]$Name)

    $tokens = $null
    $errors = $null

    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $PROFILE,
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        Write-Error "PROFILE 파싱 중 오류가 발생했습니다."
        return
    }

    $functions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)

    $comments = @($tokens | Where-Object {
        $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment
    })

    # 프로필의 영역 배너 주석에서 섹션 제목과 시작 위치를 읽는다.
    $sections = @(foreach ($c in $comments) {
        if ($c.Text -match '^#+\s*(.+?)\s+영역 Start\b') {
            [pscustomobject]@{
                Title  = $matches[1]
                Offset = $c.Extent.StartOffset
            }
        }
    })

    $items = foreach ($func in $functions) {
        $start = $func.Extent.StartOffset
        $end   = $func.Extent.EndOffset

        # 본문에서 코드가 시작되는 지점(param 블록 또는 첫 문장)을 찾는다.
        $body = $func.Body
        $codeOffsets = @(
            if ($body.ParamBlock) { $body.ParamBlock.Extent.StartOffset }
            foreach ($block in @($body.BeginBlock, $body.ProcessBlock, $body.EndBlock)) {
                if ($block -and $block.Statements.Count -gt 0) {
                    $block.Statements[0].Extent.StartOffset
                }
            }
        )
        $firstCode = if ($codeOffsets.Count -gt 0) {
            ($codeOffsets | Measure-Object -Minimum).Minimum
        }
        else {
            $end
        }

        # 함수 선언 줄 끝의 주석 또는 본문 첫 코드 앞의 첫 주석을 설명으로 사용한다.
        $head = $comments | Where-Object {
            $_.Extent.StartOffset -ge $start -and
            $_.Extent.EndOffset -le $firstCode
        } | Select-Object -First 1

        $text = if ($head) { ($head.Text -replace '^#+\s*', '').Trim() } else { '' }

        # 첫 줄 주석이 fnc-ignore면 목록에서 제외한다.
        if ($text -match '(?i)^fnc-ignore\b') {
            continue
        }

        # 설명이 "alias-fn:"으로 시작하면 다른 함수를 편하게 쓰기 위한 래퍼 함수로 표시한다.
        # 이런 함수는 소속 영역 대신 alias-function 묶음으로 모아서 보여준다.
        $isAliasFn = $false
        if ($text -match '(?i)^alias-fn\s*:\s*(.*)$') {
            $isAliasFn = $true
            $text = $matches[1].Trim()
        }

        [pscustomobject]@{
            Name        = $func.Name
            Description = $text
            Offset      = $start
            AliasFn     = $isAliasFn
        }
    }

    # 같은 이름은 첫 정의만 남기고, 프로필에 적힌 순서(오프셋순)를 유지한다.
    $seen = @{}
    $items = @($items | Sort-Object Offset | Where-Object {
        if ($seen.ContainsKey($_.Name)) { return $false }
        $seen[$_.Name] = $true
        return $true
    })

    # 함수 이름이 지정되면 해당 함수만 남긴다. 없는 이름이면 에러 표시 후 전체 목록으로 진행한다.
    if ($Name) {
        $matched = @($items | Where-Object { $_.Name -eq $Name })
        if ($matched.Count -gt 0) {
            $items = $matched
        }
        else {
            Write-Error "'$Name' 함수 이름이 없습니다. 전체 목록을 출력합니다."
        }
    }

    if ($items.Count -eq 0) {
        Write-Host "표시할 함수가 없습니다."
        return
    }

    Write-Host ("Functions in PROFILE ({0})" -f $items.Count) -ForegroundColor Cyan

    $nameWidth = ($items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum

    $index = 1
    $currentSection = $null

    # alias-fn 래퍼는 소속 영역에서 빼서 alias-function 묶음으로 목록 마지막에 모아 보여준다.
    $ordered = @($items | Where-Object { -not $_.AliasFn }) + @($items | Where-Object { $_.AliasFn })

    foreach ($item in $ordered) {
        # 함수 시작 위치보다 앞에 있는 마지막 영역 배너가 소속 영역이다.
        $section = if ($item.AliasFn) {
            'alias-function'
        }
        else {
            ($sections | Where-Object { $_.Offset -lt $item.Offset } | Select-Object -Last 1).Title
        }
        if (-not $section) { $section = '기타' }

        if (($sections.Count -gt 0 -or $item.AliasFn) -and $section -ne $currentSection) {
            $currentSection = $section
            Write-Host ""
            Write-Host ("[ {0} ]" -f $section) -ForegroundColor Yellow
        }

        Write-Host ("{0,2}. {1}" -f $index, $item.Name.PadRight($nameWidth)) -NoNewline
        if ($item.Description) {
            Write-Host ("  # {0}" -f $item.Description) -ForegroundColor DarkCyan
        }
        else {
            Write-Host ""
        }
        $index++
    }
}

#########################################################
# 프로필 개발 도구 영역 End
#########################################################


#########################################################
# SSH 서버 선택 / 접속 영역 Start
#########################################################

# --- 내부 헬퍼 ---

# 선택기 상세 캐시: 별칭별 ssh -G/DNS 조회 결과를 세션 동안 재사용한다.
$script:SshPickerDetailCache = @{}

function Expand-UserPath {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path -eq '~') {
        return $HOME
    }

    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        return Join-Path $HOME $Path.Substring(2)
    }

    return $Path
}

function Split-SshTokens {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $result = New-Object System.Collections.Generic.List[string]
    $matches = [regex]::Matches($Text, '("(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*''|\S+)')

    foreach ($m in $matches) {
        $value = $m.Value.Trim()

        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            if ($value.Length -ge 2) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$result.Add($value)
        }
    }

    return $result
}

function Get-SshAliasesFromConfigFile {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Visited
    )

    $items = New-Object System.Collections.Generic.List[object]

    $expanded = Expand-UserPath $Path
    try {
        $resolved = [System.IO.Path]::GetFullPath($expanded)
    }
    catch {
        $resolved = $expanded
    }

    if ($Visited.ContainsKey($resolved)) {
        return $items
    }

    $Visited[$resolved] = $true

    if (-not (Test-Path -LiteralPath $resolved)) {
        return $items
    }

    $dir = Split-Path -Parent $resolved
    $lines = [System.IO.File]::ReadAllLines($resolved)

    foreach ($line in $lines) {
        $trim = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trim)) {
            continue
        }

        if ($trim.StartsWith('#')) {
            continue
        }

        if ($trim -match '^(?i)include\s+(.+)$') {
            $patterns = Split-SshTokens $matches[1]

            foreach ($pattern in $patterns) {
                $includePath = Expand-UserPath $pattern

                if (-not [System.IO.Path]::IsPathRooted($includePath)) {
                    $includePath = Join-Path $dir $includePath
                }

                $matchedFiles = Get-ChildItem -Path $includePath -File -ErrorAction SilentlyContinue
                foreach ($file in $matchedFiles) {
                    $childItems = Get-SshAliasesFromConfigFile -Path $file.FullName -Visited $Visited
                    foreach ($child in $childItems) {
                        [void]$items.Add($child)
                    }
                }
            }

            continue
        }

        if ($trim -match '^(?i)host\s+(.+)$') {
            $tokens = Split-SshTokens $matches[1]

            foreach ($token in $tokens) {
                if ($token.StartsWith('!')) {
                    continue
                }

                if ($token.IndexOfAny([char[]]'*?') -ge 0) {
                    continue
                }

                [void]$items.Add([pscustomobject]@{
                    Alias  = $token
                    Source = $resolved
                })
            }
        }
    }

    return $items
}

function Get-SshMapValue {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$Default = ''
    )

    if (-not $Map.ContainsKey($Key)) {
        return $Default
    }

    $value = $Map[$Key]

    if ($value -is [System.Array]) {
        return ($value -join ', ')
    }

    return [string]$value
}

function Resolve-HostToIp {
    # fnc-ignore
    param(
        [string]$HostName
    )

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return ''
    }

    $parsed = $null
    if ([System.Net.IPAddress]::TryParse($HostName, [ref]$parsed)) {
        return $parsed.IPAddressToString
    }

    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($HostName)

        $ipv4 = $addresses | Where-Object {
            $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
        }

        if ($ipv4 -and $ipv4.Count -gt 0) {
            return $ipv4[0].IPAddressToString
        }

        if ($addresses -and $addresses.Count -gt 0) {
            return $addresses[0].IPAddressToString
        }
    }
    catch {
    }

    return ''
}

function Get-SshEffectiveConfig {
    # fnc-ignore
    # 기본은 ssh -G(로컬 config 해석)만 수행한다. DNS 조회는 blocking이 길 수 있어
    # -ResolveIp를 준 경우에만 한다. HostName이 IP 리터럴이면 조회 없이 바로 채운다.
    # IpResolved: IP 확인을 시도했는지(성공/실패 무관) 여부. picker 표시 문구 구분용.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Alias,

        [switch]$ResolveIp
    )

    $output = & ssh -G $Alias 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $output) {
        return [pscustomobject]@{
            Alias        = $Alias
            HostName     = $Alias
            IP           = ''
            IpResolved   = [bool]$ResolveIp
            Port         = '22'
            User         = ''
            IdentityFile = ''
            ProxyJump    = ''
        }
    }

    $map = @{}

    foreach ($line in $output) {
        if ($line -match '^\s*(\S+)\s+(.*)\s*$') {
            $key = $matches[1].ToLowerInvariant()
            $val = $matches[2].Trim()

            if ($map.ContainsKey($key)) {
                if ($map[$key] -is [System.Array]) {
                    $map[$key] += $val
                }
                else {
                    $map[$key] = @($map[$key], $val)
                }
            }
            else {
                $map[$key] = $val
            }
        }
    }

    $hostName = Get-SshMapValue -Map $map -Key 'hostname' -Default $Alias
    $port = Get-SshMapValue -Map $map -Key 'port' -Default '22'
    $user = Get-SshMapValue -Map $map -Key 'user' -Default ''
    $identityFile = Get-SshMapValue -Map $map -Key 'identityfile' -Default ''
    $proxyJump = Get-SshMapValue -Map $map -Key 'proxyjump' -Default ''

    $ip = ''
    $ipResolved = $false
    $parsedIp = $null

    if ([System.Net.IPAddress]::TryParse($hostName, [ref]$parsedIp)) {
        $ip = $parsedIp.IPAddressToString
        $ipResolved = $true
    }
    elseif ($ResolveIp) {
        $ip = Resolve-HostToIp $hostName
        $ipResolved = $true
    }

    return [pscustomobject]@{
        Alias        = $Alias
        HostName     = $hostName
        IP           = $ip
        IpResolved   = $ipResolved
        Port         = $port
        User         = $user
        IdentityFile = $identityFile
        ProxyJump    = $proxyJump
    }
}

function Get-SshDetailCached {
    # fnc-ignore
    # picker 탐색 중에는 -ResolveIp 없이 호출해 DNS 대기를 피하고,
    # 서버를 확정(Enter/직접 지정)한 시점에만 -ResolveIp로 IP를 채워 캐시를 승격한다.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Alias,

        [switch]$ResolveIp
    )

    $key = $Alias.ToLowerInvariant()

    if (-not $script:SshPickerDetailCache.ContainsKey($key)) {
        $script:SshPickerDetailCache[$key] = Get-SshEffectiveConfig -Alias $Alias -ResolveIp:$ResolveIp
    }
    elseif ($ResolveIp -and -not $script:SshPickerDetailCache[$key].IpResolved) {
        $script:SshPickerDetailCache[$key] = Get-SshEffectiveConfig -Alias $Alias -ResolveIp
    }

    return $script:SshPickerDetailCache[$key]
}

function Set-SshSelectionVars {
    # fnc-ignore
    # -Prefix 'SV'(기본)/'DST' — 같은 로직으로 해당 계열 변수($SV*/$DST*)와 OMP_* env를 설정한다.
    param(
        [Parameter(Mandatory = $true)]
        [object]$Entry,

        [ValidateSet('SV', 'DST')]
        [string]$Prefix = 'SV'
    )

    # 서버가 바뀌면 이전 서버 기준의 작업 디렉터리($SVDIR)는 의미가 없으므로 함께 해제한다.
    if ($Prefix -eq 'SV') {
        Remove-Variable 'SVDIR' -Scope Global -ErrorAction SilentlyContinue
        Remove-Item 'Env:OMP_SVDIR' -ErrorAction SilentlyContinue
    }

    # 선택 확정 시점이므로 여기서만 IP를 실제로 조회한다 (picker 탐색 중에는 조회 안 함).
    $detail = Get-SshDetailCached -Alias $Entry.Alias -ResolveIp

    # 선택한 ssh Host 별칭
    Set-Variable -Name $Prefix -Value $Entry.Alias -Scope Global
    Set-Variable -Name "${Prefix}PORT" -Value ([int]$detail.Port) -Scope Global
    Set-Item -Path "Env:OMP_${Prefix}" -Value $Entry.Alias
    Set-Item -Path "Env:OMP_${Prefix}PORT" -Value ([string][int]$detail.Port)

    # ssh -G가 알려주는 접속 계정(User). config에 User가 없으면 로컬 계정명이 온다.
    if ([string]::IsNullOrWhiteSpace($detail.User)) {
        Remove-Variable "${Prefix}ID" -Scope Global -ErrorAction SilentlyContinue
        Remove-Item "Env:OMP_${Prefix}ID" -ErrorAction SilentlyContinue
    }
    else {
        Set-Variable -Name "${Prefix}ID" -Value $detail.User -Scope Global
        Set-Item -Path "Env:OMP_${Prefix}ID" -Value $detail.User
    }

    # ssh -G 결과의 HostName을 실제 IP로 변환한 값만 해당 계열 IP 변수에 저장한다.
    # IP 확인에 실패하면 이전 서버의 값이 남지 않도록 제거한다.
    if ([string]::IsNullOrWhiteSpace($detail.IP)) {
        Remove-Variable "${Prefix}IP" -Scope Global -ErrorAction SilentlyContinue
        Remove-Item "Env:OMP_${Prefix}IP" -ErrorAction SilentlyContinue

        Show-SshSelectedScreen -Entry $Entry -Mode $Prefix
        Write-Warning ("원격 IP를 확인하지 못해 `${0}IP를 설정하지 않았습니다. HostName: {1}" -f $Prefix, $detail.HostName)
        return
    }

    Set-Variable -Name "${Prefix}IP" -Value $detail.IP -Scope Global
    Set-Item -Path "Env:OMP_${Prefix}IP" -Value $detail.IP

    Show-SshSelectedScreen -Entry $Entry -Mode $Prefix
    Write-Host ("변수 설정 완료: `${0}={1}, `${0}ID={2}, `${0}IP={3}, `${0}PORT={4}" -f $Prefix, $Entry.Alias, $detail.User, $detail.IP, [int]$detail.Port) -ForegroundColor Green
}

function Clear-SshSelectionVars {
    # fnc-ignore
    # -Prefix 'SV'(기본)/'DST' — 해당 계열 변수와 OMP_* env만 제거한다 (반대쪽 계열은 유지).
    param(
        [ValidateSet('SV', 'DST')]
        [string]$Prefix = 'SV'
    )

    # 원격 작업 디렉터리(DIR)는 SV 전용이라 SV 계열을 해제할 때만 함께 지운다.
    $suffixes = @('', 'ID', 'IP', 'PORT')
    if ($Prefix -eq 'SV') { $suffixes += 'DIR' }

    foreach ($suffix in $suffixes) {
        Remove-Variable "$Prefix$suffix" -Scope Global -ErrorAction SilentlyContinue
        Remove-Item "Env:OMP_$Prefix$suffix" -ErrorAction SilentlyContinue
    }
}

# --- 선택기 UI ---

function Reset-SshConsoleInput {
    # fnc-ignore
    # ssh/tssh를 Ctrl+C로 중단하면 콘솔 입력 모드(VT 입력 플래그)가 복원되지 않은 채 남아
    # 다음 picker에서 방향키가 ESC 시퀀스 조각으로 들어와 커서가 움직이지 않을 수 있다.
    # picker를 열기 전에 VT 입력 플래그를 끄고 남아 있는 입력 버퍼를 비운다.
    if (-not ('SshPicker.Native' -as [type])) {
        Add-Type -Namespace SshPicker -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool FlushConsoleInputBuffer(IntPtr hConsoleHandle);
'@
    }

    $STD_INPUT_HANDLE = -10
    $ENABLE_VIRTUAL_TERMINAL_INPUT = 0x200

    $handle = [SshPicker.Native]::GetStdHandle($STD_INPUT_HANDLE)
    if ($handle -eq [IntPtr]::Zero -or $handle.ToInt64() -eq -1) {
        return
    }

    $mode = [uint32]0
    if (-not [SshPicker.Native]::GetConsoleMode($handle, [ref]$mode)) {
        return
    }

    $newMode = [uint32]($mode -band (-bnot $ENABLE_VIRTUAL_TERMINAL_INPUT))
    if ($newMode -ne $mode) {
        [void][SshPicker.Native]::SetConsoleMode($handle, $newMode)
    }

    [void][SshPicker.Native]::FlushConsoleInputBuffer($handle)
}

function Render-SshPicker {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Entries,

        [Parameter(Mandatory = $true)]
        [int]$Index,

        [string]$Mode = 'SV'
    )

    $detail = Get-SshDetailCached -Alias $Entries[$Index].Alias
    $total = $Entries.Count

    [Console]::Clear()

    $modeLabel = if ($Mode -eq 'DST') { ' [DST 대상]' } else { '' }
    Write-Host ("SSH Host Picker{0}  [{1}/{2}]" -f $modeLabel, ($Index + 1), $total) -ForegroundColor Cyan
    Write-Host "↑/↓ 이동  Ctrl+↑/↓ 3칸 이동  Enter 선택  Esc 취소" -ForegroundColor DarkCyan
    Write-Host ""

    $visibleCount = [Math]::Min(11, $total)
    $half = [Math]::Floor($visibleCount / 2)

    $start = [Math]::Max(0, $Index - $half)
    $end = [Math]::Min($total - 1, $start + $visibleCount - 1)

    if (($end - $start + 1) -lt $visibleCount) {
        $start = [Math]::Max(0, $end - $visibleCount + 1)
    }

    for ($i = $start; $i -le $end; $i++) {
        $item = $Entries[$i]
        $prefix = if ($i -eq $Index) { '>' } else { ' ' }
        $text = "{0} [{1,3}/{2}] {3}" -f $prefix, ($i + 1), $total, $item.Alias

        if ($i -eq $Index) {
            Write-Host $text -ForegroundColor Black -BackgroundColor DarkCyan
        }
        else {
            Write-Host $text
        }
    }

    Write-Host ""

    # 탐색 중에는 DNS를 조회하지 않으므로, HostName이 IP가 아니면 미조회 상태로 표시한다.
    $ipText = if (-not [string]::IsNullOrWhiteSpace($detail.IP)) { $detail.IP }
        elseif ($detail.IpResolved) { '<DNS 해석 실패>' }
        else { '(선택 시 조회)' }

    Write-Host "상세" -ForegroundColor Yellow
    Write-Host ("  Alias        : {0}" -f $detail.Alias)
    Write-Host ("  HostName     : {0}" -f $detail.HostName)
    Write-Host ("  IP           : {0}" -f $ipText)
    Write-Host ("  Port         : {0}" -f $detail.Port)
    Write-Host ("  User         : {0}" -f $detail.User)
    Write-Host ("  IdentityFile : {0}" -f $detail.IdentityFile)
    Write-Host ("  ProxyJump    : {0}" -f $detail.ProxyJump)
    Write-Host ("  Source       : {0}" -f $Entries[$Index].Source)
}

function Show-SshSelectedScreen {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [object]$Entry,

        [string]$Mode = 'SV'
    )

    $detail = Get-SshDetailCached -Alias $Entry.Alias

    [Console]::Clear()

    Write-Host ("SSH Selected{0}" -f $(if ($Mode -eq 'DST') { ' [DST 대상]' } else { '' })) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "선택됨" -ForegroundColor Yellow
    Write-Host ("  Alias        : {0}" -f $detail.Alias)
    Write-Host ("  HostName     : {0}" -f $detail.HostName)
    Write-Host ("  IP           : {0}" -f $(if ([string]::IsNullOrWhiteSpace($detail.IP)) { "<DNS 해석 실패>" } else { $detail.IP }))
    Write-Host ("  Port         : {0}" -f $detail.Port)
    Write-Host ("  User         : {0}" -f $detail.User)
    Write-Host ("  IdentityFile : {0}" -f $detail.IdentityFile)
    Write-Host ("  ProxyJump    : {0}" -f $detail.ProxyJump)
    Write-Host ("  Source       : {0}" -f $Entry.Source)
    Write-Host ""
}

function Read-SshPickerKey {
    # fnc-ignore
    # sss-picker-v3: Esc 취소 및 Ctrl+Up/Down 3칸 이동 지원
    # 일반 ConsoleKey와 VT 입력(ESC [ A/B, ESC [ 1;5 A/B)을 모두 정규화한다.
    $first = [Console]::ReadKey($true)
    $firstKey = $first.Key.ToString()
    $isCtrl = ($first.Modifiers -band [ConsoleModifiers]::Control) -ne 0

    # VT 입력 모드에서는 ESC 문자가 Key=0(None)으로 들어올 수 있어 KeyChar로도 판별한다.
    if ($first.KeyChar -eq [char]27) {
        $firstKey = 'Escape'
    }

    switch ($firstKey) {
        'UpArrow' {
            if ($isCtrl) { return 'CtrlUpArrow' }
            return 'UpArrow'
        }
        'DownArrow' {
            if ($isCtrl) { return 'CtrlDownArrow' }
            return 'DownArrow'
        }
        'LeftArrow'  { return 'LeftArrow' }
        'RightArrow' { return 'RightArrow' }
        'Enter'      { return 'Enter' }
        'Escape'     { break }
        default      { return $firstKey }
    }

    # ENABLE_VIRTUAL_TERMINAL_INPUT 상태에서는 키가 ESC 시퀀스로 전달될 수 있다.
    $deadline = [DateTime]::UtcNow.AddMilliseconds(80)

    while (-not [Console]::KeyAvailable -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 2
    }

    # 뒤따르는 문자가 없으면 사용자가 누른 실제 Esc 키다.
    if (-not [Console]::KeyAvailable) {
        return 'Escape'
    }

    $second = [Console]::ReadKey($true)

    if ($second.KeyChar -ne '[' -and $second.KeyChar -ne 'O') {
        return 'Escape'
    }

    $sequence = New-Object System.Text.StringBuilder
    [void]$sequence.Append([char]$second.KeyChar)
    $finalChar = $null
    $finalModifiers = [ConsoleModifiers]0
    $deadline = [DateTime]::UtcNow.AddMilliseconds(80)

    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not [Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 2
            continue
        }

        $next = [Console]::ReadKey($true)
        $char = [char]$next.KeyChar
        [void]$sequence.Append($char)
        $deadline = [DateTime]::UtcNow.AddMilliseconds(80)

        if ($char -in @('A', 'B', 'C', 'D')) {
            $finalChar = $char
            $finalModifiers = $next.Modifiers
            break
        }
    }

    if ($null -eq $finalChar) {
        return 'Escape'
    }

    $sequenceText = $sequence.ToString()
    $isCtrlSequence = (($finalModifiers -band [ConsoleModifiers]::Control) -ne 0) -or ($sequenceText -match ';5[A-D]$')

    switch ($finalChar) {
        'A' {
            if ($isCtrlSequence) { return 'CtrlUpArrow' }
            return 'UpArrow'
        }
        'B' {
            if ($isCtrlSequence) { return 'CtrlDownArrow' }
            return 'DownArrow'
        }
        'C' { return 'RightArrow' }
        'D' { return 'LeftArrow' }
        default { return 'Escape' }
    }
}

# --- 사용자 명령 ---

function Set-SshHost {
    # ssh config의 Host를 선택해 $SV/$SVID/$SVIP/$SVPORT 변수를 설정한다. (축약: ss, -d: $DST 계열 설정 = sd)
    param(
        [Parameter(Position = 0)]
        [string]$Alias,

        [Alias('d')][switch]$Dst,

        [string]$ConfigPath = "$HOME/.ssh/config"
    )

    # -d(-Dst)면 rr 전송 대상인 DST 계열만, 아니면 SV 계열만 다룬다 (반대쪽 계열은 유지).
    $prefix = if ($Dst) { 'DST' } else { 'SV' }

    # 실행할 때마다 이전 선택값(해당 계열만)을 먼저 제거한다.
    # 새 서버를 선택하지 않고 중단(Esc, Ctrl+C, 오류)하면 기존 값이 남지 않는다.
    Clear-SshSelectionVars -Prefix $prefix

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw "ssh 명령을 찾지 못했습니다. OpenSSH Client가 설치되어 있어야 합니다."
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw ("ssh config 파일이 없습니다: {0}" -f $ConfigPath)
    }

    $visited = @{}
    $rawEntries = Get-SshAliasesFromConfigFile -Path $ConfigPath -Visited $visited

    if (-not $rawEntries -or $rawEntries.Count -eq 0) {
        throw ("선택 가능한 Host 항목을 찾지 못했습니다. config 파일을 확인해 주세요: {0}" -f $ConfigPath)
    }

    $seen = @{}
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $rawEntries) {
        $key = $entry.Alias.ToLowerInvariant()

        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$entries.Add($entry)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Alias)) {
        $matchedEntry = $entries | Where-Object {
            $_.Alias -ieq $Alias
        } | Select-Object -First 1

        if (-not $matchedEntry) {
            Write-Error ("ssh config에 정의된 Host를 찾지 못했습니다: {0}" -f $Alias)
            return
        }

        Set-SshSelectionVars -Entry $matchedEntry -Prefix $prefix
        return $true
    }

    # 직전 ssh/tssh가 Ctrl+C로 중단되며 콘솔 입력 모드가 깨졌을 수 있어 picker 전에 복구한다.
    Reset-SshConsoleInput

    $index = 0

    while ($true) {
        Render-SshPicker -Entries $entries.ToArray() -Index $index -Mode $prefix

        $pickerKey = Read-SshPickerKey
        switch ($pickerKey) {
            'UpArrow' {
                $index = [Math]::Max(0, $index - 1)
            }

            'CtrlUpArrow' {
                $index = [Math]::Max(0, $index - 3)
            }

            'DownArrow' {
                $index = [Math]::Min($entries.Count - 1, $index + 1)
            }

            'CtrlDownArrow' {
                $index = [Math]::Min($entries.Count - 1, $index + 3)
            }

            'Enter' {
                $selected = $entries[$index]
                Set-SshSelectionVars -Entry $selected -Prefix $prefix
                return $true
            }

            'Escape' {
                Write-Host ""
                Write-Host "취소했습니다." -ForegroundColor DarkYellow
                return $false
            }
        }
    }
}

function ss {
    # alias-fn: 원본 서버(SV)를 선택한다. (= set-sshhost, 접속은 c)
    param(
        [Parameter(Position = 0)]
        [string]$Alias
    )

    $null = Set-SshHost -Alias $Alias
}

function sd {
    # alias-fn: rr 전송 대상(DST) 서버를 선택한다. (= set-sshhost -d)
    param(
        [Parameter(Position = 0)]
        [string]$Alias
    )

    $null = Set-SshHost -Dst -Alias $Alias
}

function sb {
    # alias-fn: 원본 서버(SV)와 rr 전송 대상(DST)을 한 번에 선택한다. (= ss <SV> + sd <DST>)
    param(
        [Parameter(Position = 0)]
        [string]$Source,

        [Parameter(Position = 1)]
        [string]$Dest
    )

    # 생략한 쪽은 ss/sd처럼 목록에서 고른다. SV 선택이 실패·취소되면($true가 아니면) DST는 건드리지 않는다.
    if (-not (@(Set-SshHost -Alias $Source) -contains $true)) { return }
    $null = Set-SshHost -Dst -Alias $Dest
}

# ss/sd/sb/set-sshhost 별칭 자동완성: ssh config의 Host 목록을 후보로 보여준다. (config 파싱만, 네트워크 조회 없음)
# 같은 로직을 여러 명령·파라미터에 등록하려고 스크립트블록을 변수로 만든 뒤, 등록이 끝나면 변수는 지운다.
$sshHostAliasCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $configPath = "$HOME/.ssh/config"

    if (-not (Test-Path -LiteralPath $configPath) -or
        -not (Get-Command Get-SshAliasesFromConfigFile -ErrorAction SilentlyContinue)) {
        return
    }

    $word = $wordToComplete.Trim("'`"")
    $visited = @{}
    $seen = @{}

    # picker와 같은 순서(config 기재 순) + 중복 제거로 후보를 만든다.
    foreach ($entry in Get-SshAliasesFromConfigFile -Path $configPath -Visited $visited) {
        $alias = $entry.Alias
        $key = $alias.ToLowerInvariant()

        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        if ($word -and -not $alias.StartsWith($word, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $completionText = if ($alias -match '\s') { "'$alias'" } else { $alias }

        [System.Management.Automation.CompletionResult]::new(
            $completionText,
            $alias,
            [System.Management.Automation.CompletionResultType]::ParameterValue,
            $alias
        )
    }
}

Register-ArgumentCompleter -CommandName ss, sd, Set-SshHost -ParameterName Alias -ScriptBlock $sshHostAliasCompleter
Register-ArgumentCompleter -CommandName sb -ParameterName Source -ScriptBlock $sshHostAliasCompleter
Register-ArgumentCompleter -CommandName sb -ParameterName Dest -ScriptBlock $sshHostAliasCompleter
Remove-Variable -Name sshHostAliasCompleter

function ssh-con {
    # 선택된 $SV 서버에 ssh로 접속한다. (alias: c)
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Write-Error "ssh 명령을 찾지 못했습니다. OpenSSH Client가 설치되어 있어야 합니다."
        return
    }

    if (-not (Get-Variable SV -Scope Global -ErrorAction SilentlyContinue) -or
        [string]::IsNullOrWhiteSpace($global:SV)) {
        Write-Host "SV가 설정되지 않았습니다. 먼저 set-sshhost를 실행해 주세요." -ForegroundColor Yellow
        return
    }

    $configPath = "$HOME/.ssh/config"

    if ((Test-Path -LiteralPath $configPath) -and
        (Get-Command Get-SshAliasesFromConfigFile -ErrorAction SilentlyContinue)) {

        $visited = @{}
        $rawEntries = Get-SshAliasesFromConfigFile -Path $configPath -Visited $visited

        $aliases = $rawEntries |
            ForEach-Object { $_.Alias } |
            Sort-Object -Unique

        $matched = $aliases |
            Where-Object { $_ -ieq $global:SV } |
            Select-Object -First 1

        if (-not $matched) {
            Write-Host ("현재 SV '{0}' 는 ssh config에 정의되어 있지 않습니다." -f $global:SV) -ForegroundColor Yellow
            Write-Host "먼저 set-sshhost를 다시 실행해 주세요." -ForegroundColor Yellow
            return
        }
    }

    Write-Host ("connecting: ssh {0}" -f $global:SV) -ForegroundColor Green
    & ssh $global:SV @Args
}

function clear-sv {
    # 선택된 SV 계열 변수($SV/$SVID/$SVIP/$SVPORT)를 해제한다. (-d: DST 계열만 해제, 축약: xs/xd)
    param([Alias('d')][switch]$Dst)

    if ($Dst) {
        Clear-SshSelectionVars -Prefix DST
        Write-Host "DST 정보 제거 완료" -ForegroundColor Yellow
        return
    }

    Clear-SshSelectionVars

    Write-Host "SV 정보 제거 완료" -ForegroundColor Yellow
}

function xs {
    # alias-fn: 선택된 SV 계열 변수를 해제한다. (= clear-sv)
    clear-sv
}

function xd {
    # alias-fn: 선택된 DST 계열 변수를 해제한다. (= clear-sv -d)
    clear-sv -d
}

function ping-test {
    # 선택된 $SVIP로 ping.exe -t를 계속 보낸다 (출력이 계속 쌓인다). 상태만 보려면 p(ping-watch).
    $svipVar = Get-Variable SVIP -Scope Global -ErrorAction SilentlyContinue

    if (-not $svipVar -or [string]::IsNullOrWhiteSpace($global:SVIP)) {
        Write-Error "SVIP가 설정되어 있지 않습니다. 먼저 ss로 서버를 선택해 주세요."
        return
    }

    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($global:SVIP, [ref]$parsedIp)) {
        Write-Error ("SVIP 값이 올바른 IP 형식이 아닙니다: {0}" -f $global:SVIP)
        return
    }

    & ping.exe -t $parsedIp.IPAddressToString
}

function Test-PingOnce {
    # fnc-ignore
    # ping 1회. 응답이면 Ok=$true와 왕복시간(ms)을 돌려준다. (ping-watch 전용 - 시험 때 이 함수만 바꿔 끼운다)
    param(
        [string]$Target,
        [int]$TimeoutMs = 1000
    )

    try {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        try {
            $reply = $ping.Send($Target, $TimeoutMs)
        }
        finally {
            $ping.Dispose()
        }
    }
    catch {
        # 이름을 못 찾거나 네트워크가 없는 경우도 '응답 없음'으로 본다.
        return @{ Ok = $false; Ms = 0 }
    }

    if ($reply.Status -eq 'Success') {
        return @{ Ok = $true; Ms = [int]$reply.RoundtripTime }
    }

    return @{ Ok = $false; Ms = 0 }
}

function Format-PingDuration {
    # fnc-ignore
    # 초를 "1시간 03분 / 2분 05초 / 12초" 형태로 짧게 표시한다. (ping-watch 표시용)
    param([double]$Seconds)

    $total = [int][Math]::Round($Seconds)

    if ($total -ge 3600) { return ("{0}시간 {1:d2}분" -f [int]($total / 3600), [int](($total % 3600) / 60)) }
    if ($total -ge 60) { return ("{0}분 {1:d2}초" -f [int]($total / 60), ($total % 60)) }
    return ("{0}초" -f $total)
}

function ping-watch {
    # 대상(기본 $SVIP)의 ping 상태를 한 줄에서 갱신하며 지켜본다. 상태가 바뀔 때만 줄을 남겨 재부팅 확인에 쓴다. (축약: p, 종료 Ctrl+C)
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Alias('i')][int]$Interval = 1,
        [Alias('t')][int]$Timeout = 1000,
        [Alias('c')][int]$Count = 0
    )

    if ([string]::IsNullOrWhiteSpace($Target)) {
        if ([string]::IsNullOrWhiteSpace($global:SVIP)) {
            Write-Host "사용법: p [대상(IP/호스트명)] [-i 간격초] [-c 횟수]   (대상을 생략하면 선택된 SVIP - 먼저 ss로 서버 선택)" -ForegroundColor Yellow
            return
        }

        $Target = [string]$global:SVIP
    }

    $label = if ($global:SV -and $Target -eq [string]$global:SVIP) { "{0} ({1})" -f $global:SV, $Target } else { $Target }

    $esc = [char]27
    $green = "$esc[38;2;144;190;109m"
    $red = "$esc[38;2;255;39;64m"
    $gray = "$esc[38;2;141;153;174m"
    $reset = "$esc[0m"

    Write-Host ("[{0:HH:mm:ss}] 감시 시작  {1}  ·  {2}초 간격  ·  Ctrl+C 종료" -f (Get-Date), $label, $Interval) -ForegroundColor Cyan

    $state = $null            # $true=응답, $false=무응답 (첫 결과로 정해진다)
    $now = Get-Date
    $since = $now             # 현재 상태가 시작된 시각
    $startedAt = $now
    $streak = 0               # 현재 상태가 이어진 횟수
    $changes = 0
    $downTotal = 0.0
    $checks = 0

    # 갱신 줄은 [Console]::Write로 직접 쓰는데, 콘솔 기본 인코딩(CP949)에서는 ✖ 같은 문자가 ?로 깨진다.
    # 그래서 감시하는 동안만 UTF-8로 바꿔 쓰고 끝나면 되돌린다.
    $prevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        while ($true) {
            $result = Test-PingOnce -Target $Target -TimeoutMs $Timeout
            $ok = [bool]$result.Ok
            $checks++

            if ($null -eq $state -or $ok -ne $state) {
                $now = Get-Date
                $held = ($now - $since).TotalSeconds

                # 갱신 중인 줄을 지우고, 그 자리에 변화 기록만 남긴다 (이 줄만 화면에 쌓인다).
                [Console]::Write("`r$esc[K")

                if ($null -eq $state) {
                    $first = if ($ok) { "● 응답 {0}ms" -f $result.Ms } else { "✖ 응답 없음" }
                    Write-Host ("[{0:HH:mm:ss}] {1}" -f $now, $first) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
                }
                elseif ($ok) {
                    $downTotal += $held
                    $changes++
                    Write-Host ("[{0:HH:mm:ss}] ● 응답 재개 {1}ms  (응답 없음 {2} 지속)" -f $now, $result.Ms, (Format-PingDuration $held)) -ForegroundColor Green
                }
                else {
                    $changes++
                    Write-Host ("[{0:HH:mm:ss}] ✖ 응답 끊김  (응답 {1} 지속)" -f $now, (Format-PingDuration $held)) -ForegroundColor Red
                }

                $state = $ok
                $since = $now
                $streak = 0
            }

            $streak++
            $held = ((Get-Date) - $since).TotalSeconds
            $head = if ($ok) { "{0}● 응답 {1,4}ms{2}" -f $green, $result.Ms, $reset } else { "{0}✖ 응답 없음{1}" -f $red, $reset }
            [Console]::Write(("`r$esc[K {0}  {1}· {2}회 연속 · {3} 유지 · 확인 {4}회{5}" -f $head, $gray, $streak, (Format-PingDuration $held), $checks, $reset))

            if ($Count -gt 0 -and $checks -ge $Count) { break }
            Start-Sleep -Seconds $Interval
        }
    }
    finally {
        # Ctrl+C로 끊겨도 갱신 줄을 지우고 요약을 남긴다.
        [Console]::Write("`r$esc[K")

        if ($false -eq $state) { $downTotal += ((Get-Date) - $since).TotalSeconds }

        Write-Host ("[{0:HH:mm:ss}] 감시 종료  ·  총 {1}  ·  확인 {2}회  ·  상태 변경 {3}회  ·  응답 없음 합계 {4}" -f
            (Get-Date), (Format-PingDuration ((Get-Date) - $startedAt).TotalSeconds), $checks, $changes, (Format-PingDuration $downTotal)) -ForegroundColor Cyan

        [Console]::OutputEncoding = $prevEncoding
    }
}

function p {
    # alias-fn: 대상(기본 SVIP)의 ping 상태를 한 줄로 지켜본다. (= ping-watch, 상태가 바뀔 때만 기록)
    ping-watch @args
}

function Test-TcpPort {
    # fnc-ignore
    # TCP 포트 하나에 접속을 시도해 열림 / 닫힘(거부) / 무응답(타임아웃)을 구분한다. (pt/rb 전용 - 시험 때 이 함수만 바꿔 끼운다)
    param(
        [string]$Target,
        [int]$Port,
        [int]$TimeoutMs = 1000
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $client = [System.Net.Sockets.TcpClient]::new()

    try {
        # 동기 Connect는 타임아웃을 정할 수 없어 ConnectAsync + Wait로 기다린다.
        if (-not $client.ConnectAsync($Target, $Port).Wait($TimeoutMs)) {
            return @{ State = 'timeout'; Ms = $TimeoutMs }
        }

        return @{ State = 'open'; Ms = [int]$watch.ElapsedMilliseconds }
    }
    catch {
        # 접속 거부(RST)와 이름 조회 실패가 모두 여기로 온다. Wait는 실패한 작업의 예외를 다시 던진다.
        return @{ State = 'closed'; Ms = [int]$watch.ElapsedMilliseconds }
    }
    finally {
        $watch.Stop()
        $client.Dispose()
    }
}

function Invoke-SvSsh {
    # fnc-ignore
    # 선택된 $SV에 명령 한 줄을 보내고 출력과 종료 코드를 돌려준다. (rs/rb 공용 - 시험 때 이 함수만 바꿔 끼운다)
    # config의 Host * RemoteCommand와 충돌하지 않게 무효화하고, 한글이 깨지지 않게 실행 중에만 UTF-8로 받는다.
    param(
        [string]$Command,
        [int]$ConnectTimeout = 5,
        [switch]$IncludeError
    )

    $prevEncoding = [Console]::OutputEncoding

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

        $sshArgs = @(
            '-o', 'BatchMode=yes',
            '-o', ("ConnectTimeout={0}" -f $ConnectTimeout),
            '-o', 'RemoteCommand=none',
            '-o', 'RequestTTY=no',
            '-p', $global:SVPORT,
            $global:SV,
            $Command
        )

        $lines = if ($IncludeError) { @(& ssh @sshArgs 2>&1) } else { @(& ssh @sshArgs 2>$null) }

        return @{ Lines = $lines; ExitCode = $LASTEXITCODE }
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }
}

function pt {
    # 대상의 TCP 포트가 열렸는지 확인한다. 열림/닫힘/무응답을 구분해 표로 보여준다. (대상 생략 시 $SVIP, 포트 생략 시 SVPORT+22/80/443)
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Parameter(Position = 1)]
        [string]$Ports,

        [Alias('t')][int]$Timeout = 1000
    )

    # 'pt 8080'처럼 대상을 생략하고 포트만 준 경우를 알아본다 (숫자·쉼표·범위만 있으면 포트로 본다).
    if ($Target -and -not $Ports -and $Target -match '^[0-9]+(\s*[-,]\s*[0-9]+)*$') {
        $Ports = $Target
        $Target = ''
    }

    if ([string]::IsNullOrWhiteSpace($Target)) {
        if ([string]::IsNullOrWhiteSpace($global:SVIP)) {
            Write-Host "사용법: pt [대상(IP/호스트명)] [포트목록] [-t 타임아웃ms]   (대상을 생략하면 선택된 SVIP - 먼저 ss로 서버 선택)" -ForegroundColor Yellow
            Write-Host "  예: pt 8080   /   pt 10.0.0.5 22,80,443   /   pt myhost 8000-8010 -t 500" -ForegroundColor DarkCyan
            return
        }

        $Target = [string]$global:SVIP
    }

    # 포트를 생략하면 ssh 포트와 흔한 서비스 포트를 함께 본다 (ping은 되는데 서비스가 안 뜬 상황 구분용).
    if ([string]::IsNullOrWhiteSpace($Ports)) {
        $Ports = (@($global:SVPORT, 22, 80, 443) | Where-Object { $_ }) -join ','
    }

    $requested = [System.Collections.Generic.List[int]]::new()
    $seen = @{}

    foreach ($chunk in ($Ports -split ',')) {
        $text = $chunk.Trim()
        if (-not $text) { continue }

        $range = $text -split '-', 2
        $first = 0
        $last = 0

        if (-not [int]::TryParse($range[0].Trim(), [ref]$first) -or
            ($range.Count -eq 2 -and -not [int]::TryParse($range[1].Trim(), [ref]$last))) {
            Write-Error ("포트 형식을 알 수 없습니다: {0}" -f $text)
            return
        }

        if ($range.Count -eq 1) { $last = $first }

        if ($first -lt 1 -or $last -gt 65535 -or $last -lt $first) {
            Write-Error ("포트 범위가 올바르지 않습니다: {0} (1-65535)" -f $text)
            return
        }

        for ($port = $first; $port -le $last; $port++) {
            if ($seen.ContainsKey($port)) { continue }
            $seen[$port] = $true
            $requested.Add($port)
        }
    }

    if ($requested.Count -eq 0) {
        Write-Error "확인할 포트가 없습니다."
        return
    }

    # 포트 스캐너가 아니라 서비스 확인용이므로 한 번에 보는 개수를 제한한다 (기본 타임아웃에서 최악 64초).
    if ($requested.Count -gt 64) {
        Write-Error ("한 번에 확인할 수 있는 포트는 64개까지입니다. (요청 {0}개)" -f $requested.Count)
        return
    }

    # 이름을 못 찾은 경우를 '포트 닫힘'과 섞지 않도록 주소는 미리 한 번만 조회한다.
    $address = $null

    if (-not [System.Net.IPAddress]::TryParse($Target, [ref]$address)) {
        try {
            $address = @([System.Net.Dns]::GetHostAddresses($Target))[0]
        }
        catch {
            Write-Error ("주소를 찾지 못했습니다: {0}" -f $Target)
            return
        }
    }

    $ip = $address.IPAddressToString

    $shown = if ($global:SV -and $Target -eq [string]$global:SVIP) { "{0} ({1})" -f $global:SV, $ip }
        elseif ($Target -ne $ip) { "{0} ({1})" -f $Target, $ip }
        else { $ip }

    # 어느 대상인지가 한눈에 들어오도록 rl과 같은 굵은 코랄 머리글을 쓴다.
    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"

    Write-Host ("{0}port:$esc[0m {1}{2}$esc[0m  {0}(포트 {3}개 · 타임아웃 {4}ms)$esc[0m" -f $sub, $head, $shown, $requested.Count, $Timeout)

    $services = @{
        21 = 'ftp'; 22 = 'ssh'; 23 = 'telnet'; 25 = 'smtp'; 53 = 'dns'; 80 = 'http'
        111 = 'rpcbind'; 123 = 'ntp'; 139 = 'smb'; 389 = 'ldap'; 443 = 'https'; 445 = 'smb'
        514 = 'syslog'; 873 = 'rsync'; 1521 = 'oracle'; 2049 = 'nfs'; 3000 = 'http-alt'
        3306 = 'mysql'; 3389 = 'rdp'; 5432 = 'postgres'; 5900 = 'vnc'; 6379 = 'redis'
        8000 = 'http-alt'; 8080 = 'http-alt'; 8443 = 'https-alt'; 9000 = 'http-alt'
        9200 = 'elastic'; 27017 = 'mongo'
    }

    $openCount = 0

    foreach ($port in $requested) {
        $result = Test-TcpPort -Target $ip -Port $port -TimeoutMs $Timeout

        switch ($result.State) {
            'open' { $mark = '●'; $state = '열림  '; $color = 'Green'; $openCount++ }
            'closed' { $mark = '✖'; $state = '닫힘  '; $color = 'Red' }
            default { $mark = '○'; $state = '무응답'; $color = 'DarkYellow' }
        }

        $took = if ($result.State -eq 'timeout') { "{0}ms 초과" -f $Timeout } else { "{0}ms" -f $result.Ms }

        $note = if ($services.ContainsKey($port)) { $services[$port] } else { '' }

        if ("$port" -eq "$($global:SVPORT)" -and $Target -eq [string]$global:SVIP) {
            $note = if ($note) { "{0} · SVPORT" -f $note } else { 'SVPORT' }
        }

        Write-Host ("  {0,5}/tcp  " -f $port) -NoNewline
        Write-Host ("{0} {1}" -f $mark, $state) -NoNewline -ForegroundColor $color
        Write-Host ("  {0,-11}" -f $took) -NoNewline -ForegroundColor DarkGray
        Write-Host $note -ForegroundColor DarkCyan
    }

    Write-Host ("  {0}열림 {1}개 / 확인 {2}개$esc[0m" -f $sub, $openCount, $requested.Count)
}

function rb {
    # 선택된 SV가 재부팅으로 내려갔다 올라오는 과정을 한 줄에서 지켜본다. 재부팅 명령은 보내지 않는다.
    # (원격 셸에서 reboot을 친 뒤 빠져나와 실행한다. -c 복구되면 접속, -w 단계별 최대 대기(분), -i 확인 간격(초), 종료 Ctrl+C)
    param(
        [Alias('c')][switch]$Connect,
        [Alias('w')][double]$Wait = 10,
        [Alias('i')][int]$Interval = 2
    )

    if (-not (Test-ScpReady)) { return }

    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"
    $green = "$esc[38;2;144;190;109m"
    $red = "$esc[38;2;255;39;64m"
    $gray = "$esc[38;2;141;153;174m"
    $reset = "$esc[0m"
    $target = [string]$global:SVIP

    Write-Host ("{0}reboot:$esc[0m {1}{2}$esc[0m  {0}({3}:{4} · {5})$esc[0m" -f $sub, $head, $global:SV, $target, $global:SVPORT, $global:SVID)
    Write-Host ("  {0}다운 확인 -> 응답 재개 -> ssh 포트 -> 로그인 순서로 기록합니다. (Ctrl+C 종료){1}" -f $sub, $reset)

    # 분 단위지만 0.5처럼 소수도 받는다 (짧게 확인하거나 시험할 때 쓴다).
    $limit = [TimeSpan]::FromMinutes([Math]::Max(0.01, $Wait))
    $startedAt = Get-Date
    $downAt = $null
    $upAt = $null
    $readyAt = $null

    # 이미 내려간 뒤에 실행했다면 다운 확인은 건너뛰고 복구만 기다린다.
    $first = Test-PingOnce -Target $target -TimeoutMs 1000

    if (-not $first.Ok) {
        $downAt = $startedAt
        Write-Host ("[{0:HH:mm:ss}] ✖ 이미 응답 없음 - 복구만 지켜봅니다." -f $startedAt) -ForegroundColor Red
    }

    # 갱신 줄은 [Console]::Write로 직접 쓰는데, 콘솔 기본 인코딩(CP949)에서는 ✖ 같은 문자가 ?로 깨진다.
    # 그래서 지켜보는 동안만 UTF-8로 바꿔 쓰고 끝나면 되돌린다. (ping-watch와 같은 방식)
    $prevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    try {
        # 1단계: 다운 확인 - 순간적인 유실과 구분하려고 연속 2회 무응답일 때 다운으로 본다.
        if (-not $downAt) {
            $missed = 0
            $phaseStart = Get-Date

            while ($true) {
                $result = Test-PingOnce -Target $target -TimeoutMs 1000
                $now = Get-Date

                if ($result.Ok) { $missed = 0 }
                else {
                    $missed++
                    if ($missed -ge 2) { $downAt = $now; break }
                }

                if (($now - $phaseStart) -gt $limit) { break }

                $line = if ($result.Ok) { "{0}● 응답 {1,4}ms{2}" -f $green, $result.Ms, $reset } else { "{0}✖ 무응답 {1}회{2}" -f $red, $missed, $reset }
                [Console]::Write(("`r$esc[K {0}  {1}· 다운 대기 · {2} 경과{3}" -f $line, $gray, (Format-PingDuration ($now - $phaseStart).TotalSeconds), $reset))
                Start-Sleep -Seconds $Interval
            }

            [Console]::Write("`r$esc[K")

            if (-not $downAt) {
                Write-Host ("[{0:HH:mm:ss}] 다운을 확인하지 못했습니다 ({1} 동안 계속 응답). 재부팅이 아직 시작되지 않았을 수 있습니다." -f (Get-Date), (Format-PingDuration $limit.TotalSeconds)) -ForegroundColor Yellow
                return
            }

            Write-Host ("[{0:HH:mm:ss}] ✖ 다운 확인  (감시 시작 후 {1})" -f $downAt, (Format-PingDuration ($downAt - $startedAt).TotalSeconds)) -ForegroundColor Red
        }

        # 2단계: 응답 재개 대기
        $phaseStart = Get-Date

        while ($true) {
            $result = Test-PingOnce -Target $target -TimeoutMs 1000
            $now = Get-Date

            if ($result.Ok) { $upAt = $now; break }
            if (($now - $phaseStart) -gt $limit) { break }

            [Console]::Write(("`r$esc[K {0}✖ 응답 없음{1}  {2}· 복구 대기 · {3} 경과{4}" -f $red, $reset, $gray, (Format-PingDuration ($now - $downAt).TotalSeconds), $reset))
            Start-Sleep -Seconds $Interval
        }

        [Console]::Write("`r$esc[K")

        if (-not $upAt) {
            Write-Host ("[{0:HH:mm:ss}] {1} 동안 응답이 돌아오지 않았습니다. p로 계속 지켜보세요." -f (Get-Date), (Format-PingDuration $limit.TotalSeconds)) -ForegroundColor Yellow
            return
        }

        Write-Host ("[{0:HH:mm:ss}] ● 응답 재개 {1}ms  (다운 {2} 지속)" -f $upAt, $result.Ms, (Format-PingDuration ($upAt - $downAt).TotalSeconds)) -ForegroundColor Green

        # 3단계: sshd 기동 - 포트가 열리고 실제로 로그인까지 되는지 확인한다.
        $phaseStart = Get-Date
        $portAt = $null

        while ($true) {
            $port = Test-TcpPort -Target $target -Port ([int]$global:SVPORT) -TimeoutMs 1000
            $now = Get-Date

            if ($port.State -eq 'open') { $portAt = $now; break }
            if (($now - $phaseStart) -gt $limit) { break }

            [Console]::Write(("`r$esc[K {0}○ {1} 포트 대기{2}  {3}· {4} 경과{5}" -f $gray, $global:SVPORT, $reset, $gray, (Format-PingDuration ($now - $upAt).TotalSeconds), $reset))
            Start-Sleep -Seconds $Interval
        }

        [Console]::Write("`r$esc[K")

        if (-not $portAt) {
            Write-Host ("[{0:HH:mm:ss}] ping은 되지만 {1} 포트가 열리지 않았습니다. pt로 확인해 보세요." -f (Get-Date), $global:SVPORT) -ForegroundColor Yellow
            return
        }

        Write-Host ("[{0:HH:mm:ss}] ● ssh {1} 포트 열림  (응답 재개 후 {2})" -f $portAt, $global:SVPORT, (Format-PingDuration ($portAt - $upAt).TotalSeconds)) -ForegroundColor Green

        # sshd가 막 떠서 잠깐 거절하는 경우가 있어 로그인은 몇 번 다시 시도한다.
        for ($try = 1; $try -le 3; $try++) {
            $login = Invoke-SvSsh -Command 'true'
            if ($login.ExitCode -eq 0) { $readyAt = Get-Date; break }
            Start-Sleep -Seconds $Interval
        }

        if ($readyAt) {
            Write-Host ("[{0:HH:mm:ss}] 복구 완료  ·  전체 {1}  ·  다운 {2}" -f $readyAt, (Format-PingDuration ($readyAt - $startedAt).TotalSeconds), (Format-PingDuration ($upAt - $downAt).TotalSeconds)) -ForegroundColor Cyan
        }
        else {
            Write-Host ("[{0:HH:mm:ss}] 포트는 열렸지만 ssh 로그인이 아직 되지 않습니다. 잠시 후 c로 접속해 보세요." -f (Get-Date)) -ForegroundColor Yellow
        }
    }
    finally {
        # Ctrl+C로 끊겨도 갱신 줄을 지우고 인코딩을 되돌린다.
        [Console]::Write("`r$esc[K")
        [Console]::OutputEncoding = $prevEncoding
    }

    if (-not $readyAt) { return }

    if ($Connect) { ssh-con }
    else { Write-Host ("  {0}c 로 접속 · rs 로 상태 확인{1}" -f $sub, $reset) }
}

function Clear-ChangedHostKey {
    # fnc-ignore
    # 서버의 호스트 키가 known_hosts 기록과 달라 접속이 막히는지 확인하고, 그럴 때만 해당 항목을 지운다.
    # (IP를 재사용한 다른 장비로 교체된 경우. 무조건 지우면 중간자 공격 경고 자체가 무의미해지므로
    #  실제 충돌이 확인될 때만 정리하고, 무엇을 지웠는지 화면에 남긴다.)
    # 반환값: 정리했으면 $true — 호출한 쪽이 새 키를 받아들이도록 옵션을 붙이는 데 쓴다.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [string[]]$PortArgs = @()
    )

    $probe = & ssh @PortArgs -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes `
        -o RemoteCommand=none -o RequestTTY=no $Destination exit 2>&1
    $text = $probe | Out-String

    if ($text -notmatch 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed') {
        return $false
    }

    # known_hosts에는 별칭이 아니라 실제 접속 대상(HostName)이 기록되므로 그 이름으로 지운다.
    $target = $Destination -replace '^.*@', ''
    $resolved = & ssh -G @PortArgs $Destination 2>$null |
        Where-Object { $_ -match '^hostname\s+(.+)$' } |
        ForEach-Object { $matches[1] } |
        Select-Object -First 1
    if ($resolved) { $target = $resolved }

    Write-Host "서버의 호스트 키가 기존 known_hosts 기록과 다릅니다 (IP 재사용 등으로 장비가 바뀐 경우)." -ForegroundColor Yellow
    Write-Host ("기존 항목을 정리한 뒤 등록을 계속합니다: {0}" -f $target) -ForegroundColor Yellow
    del-host $target

    return $true
}

function Show-AuthUsage {
    # fnc-ignore
    Write-Host "사용법: auth [계정@서버IP | ssh별칭] [포트]" -ForegroundColor Yellow
    Write-Host "  auth                    : ss로 선택한 서버(`$SV)에 등록 (포트는 선택 시 값 사용)" -ForegroundColor DarkCyan
    Write-Host "  auth user@10.0.0.5      : 기본 포트(22)로 등록" -ForegroundColor DarkCyan
    Write-Host "  auth user@10.0.0.5 2222 : 22가 아닌 포트는 두 번째 인자로 지정" -ForegroundColor DarkCyan
    Write-Host "  auth myhost             : ssh config 별칭 사용 (포트는 config의 Port 값 적용)" -ForegroundColor DarkCyan
    Write-Host "  auth myhost 2222        : 별칭을 쓰면서 포트만 따로 지정" -ForegroundColor DarkCyan
}

function auth
{
    # 서버에 SSH 공개키를 등록해 비밀번호 없이 접속하도록 설정한다.
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Parameter(Position = 1)]
        [int]$Port = 0,

        [Alias('h')]
        [switch]$Help
    )

    # -h/-Help는 스위치로 바인딩되지만 --help, -?, /? 는 $Target에 문자열로 들어온다.
    # (지원하지 않는 옵션이 서버 이름으로 해석돼 엉뚱한 등록을 시도하는 것을 막는다.)
    if ($Help -or $Target -match '^(--?help|[-/]\?|/h)$') {
        Show-AuthUsage
        return
    }

    foreach ($cmd in 'ssh', 'ssh-keygen') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Error ("{0} 명령을 찾을 수 없습니다. OpenSSH 클라이언트 설치를 확인해 주세요." -f $cmd)
            return
        }
    }

    # 접속 대상: 인자가 있으면 인자(계정@서버IP)를, 없으면 sss로 선택한 $SV를 사용한다.
    $portArgs = @()
    if ($Target) {
        $dest = $Target
        if ($Port -gt 0) { $portArgs = @('-p', $Port) }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$global:SV)) {
        $dest = $global:SV
        if ($Port -gt 0) { $portArgs = @('-p', $Port) }
        elseif ($global:SVPORT) { $portArgs = @('-p', $global:SVPORT) }
    }
    else {
        Show-AuthUsage
        return
    }

    # 같은 IP를 쓰던 다른 장비로 바뀌었으면 옛 호스트 키 때문에 접속 자체가 막히므로 먼저 정리한다.
    # 정리한 경우에만 새 호스트 키를 자동으로 받아들인다(이미 사용자가 재등록을 의도한 상황).
    $hostKeyArgs = @()
    if (Clear-ChangedHostKey -Destination $dest -PortArgs $portArgs) {
        $hostKeyArgs = @('-o', 'StrictHostKeyChecking=accept-new')
    }

    $sshDir = Join-Path $HOME '.ssh'
    $pubKeys = @(Get-ChildItem -Path (Join-Path $sshDir '*.pub') -File -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath ($_.FullName -replace '\.pub$', '') })

    # 1) 로컬 키 중 하나라도 이미 등록되어 있으면 바로 종료
    foreach ($pub in $pubKeys) {
        $priv = $pub.FullName -replace '\.pub$', ''
        & ssh @portArgs @hostKeyArgs -i $priv -o IdentitiesOnly=yes -o BatchMode=yes -o PasswordAuthentication=no -o ConnectTimeout=5 -o RemoteCommand=none -o RequestTTY=no $dest exit 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("이미 SSH 키가 등록되어 있습니다: {0} ({1})" -f $dest, $pub.Name) -ForegroundColor Green
            return
        }
    }

    # 2) 사용할 키 결정: 없으면 생성, 하나면 그대로, 여러 개면 사용자에게 선택받기
    if ($pubKeys.Count -eq 0) {
        if (-not (Test-Path -LiteralPath $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir | Out-Null
        }
        $keyPath = Join-Path $sshDir 'id_ed25519'
        $pubKeyPath = "$keyPath.pub"
        if (Test-Path -LiteralPath $keyPath) {
            # 개인키만 있고 .pub이 없는 경우: 개인키를 덮어쓰지 않고 공개키만 다시 뽑아낸다.
            Write-Host ("기존 개인키에서 공개키를 복원합니다: {0}" -f $keyPath) -ForegroundColor Yellow
            & ssh-keygen -y -f $keyPath | Set-Content -LiteralPath $pubKeyPath -Encoding ascii
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -LiteralPath $pubKeyPath -ErrorAction SilentlyContinue
                Write-Error "공개키 복원에 실패했습니다."
                return
            }
        }
        else {
            Write-Host ("SSH 키가 없어 새로 생성합니다: {0}" -f $keyPath) -ForegroundColor Yellow
            # PS 7.3 미만은 빈 문자열 인자가 네이티브 명령에 유실되므로 '""' 로 넘겨야 한다.
            $emptyPass = if ($PSVersionTable.PSVersion -ge [version]'7.3') { '' } else { '""' }
            & ssh-keygen -q -t ed25519 -f $keyPath -N $emptyPass
            if ($LASTEXITCODE -ne 0) {
                Write-Error "SSH 키 생성에 실패했습니다."
                return
            }
        }
    }
    elseif ($pubKeys.Count -eq 1) {
        $pubKeyPath = $pubKeys[0].FullName
    }
    else {
        Write-Host "등록할 SSH 키를 선택해 주세요:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $pubKeys.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $pubKeys[$i].Name)
        }
        $choice = Read-Host ("번호 입력 (1-{0})" -f $pubKeys.Count)
        $index = 0
        if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $pubKeys.Count) {
            Write-Host "잘못된 선택입니다. 취소합니다." -ForegroundColor Yellow
            return
        }
        $pubKeyPath = $pubKeys[$index - 1].FullName
    }

    # 3) 공개키를 원격 authorized_keys에 추가 (이미 같은 줄이 있으면 건너뜀)
    #    최초 접속이므로 여기서 서버 비밀번호를 물어본다.
    Write-Host ("공개키 등록: {0} -> {1}" -f (Split-Path $pubKeyPath -Leaf), $dest) -ForegroundColor Green
    Write-Host "서버 접속 비밀번호를 입력해 주세요." -ForegroundColor Yellow
    $remoteCmd = 'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; k=$(cat); grep -qxF "$k" ~/.ssh/authorized_keys || echo "$k" >> ~/.ssh/authorized_keys'
    Get-Content -LiteralPath $pubKeyPath -TotalCount 1 | & ssh @portArgs @hostKeyArgs -o RemoteCommand=none -o RequestTTY=no $dest $remoteCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error ("공개키 등록에 실패했습니다 (exit code: {0})" -f $LASTEXITCODE)
        return
    }

    # 4) 등록한 키로 실제 접속되는지 확인
    $privKeyPath = $pubKeyPath -replace '\.pub$', ''
    & ssh @portArgs @hostKeyArgs -i $privKeyPath -o IdentitiesOnly=yes -o BatchMode=yes -o PasswordAuthentication=no -o ConnectTimeout=5 -o RemoteCommand=none -o RequestTTY=no $dest exit 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("SSH 키 등록 완료 ({0})" -f $dest) -ForegroundColor Green
    }
    else {
        Write-Host "키는 등록했지만 키 인증 확인에 실패했습니다. 서버의 sshd 설정(PubkeyAuthentication)을 확인해 주세요." -ForegroundColor Yellow
    }
}

function rsa-pubkey # show ssh rsa-public key
{
    cat $env:HOMEPATH/.ssh/id_rsa.pub
}

function Get-KeepTitleSnippet {
    # fnc-ignore
    # 원격 ~/.bashrc 끝에 붙일 블록. (따옴표가 많아 작은따옴표 here-string으로 그대로 들고 있는다)
    $snippet = @'
# >>> pws keep-title >>>
# Windows Terminal 탭 이름이 원격 셸 프롬프트에 덮이지 않게 한다. (windows: keep-title)
# 끄려면 아래 PWS_KEEP_TITLE=1 줄을 주석 처리하고 다시 접속한다. (블록 제거: keep-title -r)
PWS_KEEP_TITLE=1
if [ -n "${PWS_KEEP_TITLE:-}" ] && [ -n "${PS1:-}" ]; then
    # 1) PS1에 박힌 제목 설정 제거: \[\e]0;...\] 또는 \[\033]0;...\]
    #    제목 문자열 안에 \u \h \w 같은 백슬래시가 들어가므로 닫는 ] 까지 통째로 지운다.
    _pws_ps1=$(printf '%s' "$PS1" | sed -e 's/\\\[\\e\]0;[^]]*\]//g' -e 's/\\\[\\033\]0;[^]]*\]//g')

    # 프롬프트가 통째로 비면 위험하므로 남은 내용이 있을 때만 바꾼다.
    if [ -n "$_pws_ps1" ]; then PS1=$_pws_ps1; fi
    unset _pws_ps1

    # 2) PROMPT_COMMAND가 제목을 쓰면 그 부분만 빼고 나머지 일은 남긴다.
    case "${PROMPT_COMMAND:-}" in
        *']0;'*)
            PROMPT_COMMAND=$(printf '%s' "$PROMPT_COMMAND" | sed -E 's/[^;]*\]0;[^;]*(;|$)//g')
            ;;
    esac
fi
# <<< pws keep-title <<<
'@

    $snippet -replace "`r`n", "`n"
}

function Invoke-RemoteBashScript {
    # fnc-ignore
    # 원격에서 bash 스크립트를 실행한다. (시험 때 이 함수만 바꿔 끼운다)
    # 스크립트는 base64로 실어 보낸다 - 따옴표·줄바꿈이 중간에 깨지지 않는다.
    param(
        [string]$Destination,
        [string[]]$PortArgs = @(),
        [string]$Script
    )

    $body = ($Script -replace "`r`n", "`n")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
    $remote = "echo {0} | base64 -d | bash -s" -f $encoded

    $prevEncoding = [Console]::OutputEncoding

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $lines = @(& ssh -o ConnectTimeout=5 -o RemoteCommand=none -o RequestTTY=no @PortArgs $Destination $remote 2>&1)
        return @{ Lines = @($lines | ForEach-Object { [string]$_ }); ExitCode = $LASTEXITCODE }
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }
}

function Get-KeepTitleResult {
    # fnc-ignore
    # 원격 스크립트가 남긴 'KEY=값' 줄에서 값을 꺼낸다.
    param([object]$Response, [string]$Key)

    foreach ($line in @($Response.Lines)) {
        if ($line -match ("^{0}=(.*)$" -f [regex]::Escape($Key))) { return $Matches[1].Trim() }
    }

    ''
}

function keep-title {
    # 원격 서버의 ~/.bashrc에 '탭 제목 덮어쓰기 방지' 블록을 넣는다. (bash 전용, 서버마다 한 번, -r 제거, -h 사용법)
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Parameter(Position = 1)]
        [int]$Port = 0,

        [Alias('r')]
        [switch]$Remove,

        [Alias('h')]
        [switch]$Help
    )

    if ($Help -or $Target -match '^(--?help|[-/]\?|/h)$') {
        Write-Host "사용법: keep-title [대상] [포트]      원격 ~/.bashrc에 탭 제목 보호 블록을 넣는다" -ForegroundColor Yellow
        Write-Host "        keep-title -r [대상] [포트]   넣었던 블록을 제거한다" -ForegroundColor Yellow
        Write-Host "  대상을 생략하면 선택된 SV. 접속 계정의 bash 프롬프트가 탭 이름을 덮어쓰지 않게 한다." -ForegroundColor DarkCyan
        Write-Host "  bash 전용이며, 원격 ~/.bashrc는 고치기 전에 자동으로 백업한다." -ForegroundColor DarkCyan
        return
    }

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Write-Error "ssh 명령을 찾지 못했습니다. OpenSSH Client가 설치되어 있어야 합니다."
        return
    }

    # 접속 대상: 인자가 있으면 인자를, 없으면 ss로 선택한 $SV를 쓴다. (auth와 같은 규칙)
    $portArgs = @()

    if ($Target) {
        $dest = $Target
        if ($Port -gt 0) { $portArgs = @('-p', $Port) }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$global:SV)) {
        $dest = [string]$global:SV
        if ($Port -gt 0) { $portArgs = @('-p', $Port) }
        elseif ($global:SVPORT) { $portArgs = @('-p', $global:SVPORT) }
    }
    else {
        Write-Host "사용법: keep-title [대상] [포트]   (대상을 생략하면 선택된 SV - 먼저 ss로 서버 선택)" -ForegroundColor Yellow
        return
    }

    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"

    Write-Host ("{0}keep-title:$esc[0m {1}{2}$esc[0m  {0}({3})$esc[0m" -f
        $sub, $head, $dest, $(if ($Remove) { '블록 제거' } else { '블록 추가' }))

    if ($Remove) {
        $script = @'
file="$HOME/.bashrc"
if [ ! -f "$file" ]; then echo "RESULT=NOFILE"; exit 0; fi
if ! grep -q "pws keep-title" "$file"; then echo "RESULT=NOTFOUND"; exit 0; fi
backup="$file.bak-pws-$(date +%Y%m%d-%H%M%S)"
cp "$file" "$backup"
sed -i '/# >>> pws keep-title >>>/,/# <<< pws keep-title <<</d' "$file"
echo "RESULT=REMOVED"
echo "BACKUP=$backup"
'@
    }
    else {
        $script = @'
file="$HOME/.bashrc"
if [ ! -f "$file" ]; then : > "$file"; fi
if grep -q "pws keep-title" "$file"; then echo "RESULT=ALREADY"; exit 0; fi
backup="$file.bak-pws-$(date +%Y%m%d-%H%M%S)"
cp "$file" "$backup"
cat >> "$file" <<'PWSKEEPTITLEEOF'
__SNIPPET__
PWSKEEPTITLEEOF
echo "RESULT=INSTALLED"
echo "BACKUP=$backup"
'@
        # -replace는 정규식 치환이라 스니펫 안의 ${...}를 그룹 참조로 해석한다. 문자 그대로 바꿔 넣는다.
        $script = $script.Replace('__SNIPPET__', (Get-KeepTitleSnippet).TrimEnd("`n"))
    }

    $response = Invoke-RemoteBashScript -Destination $dest -PortArgs $portArgs -Script $script

    if ($response.ExitCode -ne 0) {
        Write-Error ("원격 설정에 실패했습니다 (exit code: {0}) {1}" -f $response.ExitCode, (@($response.Lines) -join ' '))
        return
    }

    $result = Get-KeepTitleResult -Response $response -Key 'RESULT'
    $backup = Get-KeepTitleResult -Response $response -Key 'BACKUP'

    switch ($result) {
        'INSTALLED' { Write-Host ("  ~/.bashrc에 추가했습니다.  {0}(백업: {1})$esc[0m" -f $sub, $backup) -ForegroundColor Green }
        'ALREADY' { Write-Host "  이미 적용되어 있습니다." -ForegroundColor Green }
        'REMOVED' { Write-Host ("  블록을 제거했습니다.  {0}(백업: {1})$esc[0m" -f $sub, $backup) -ForegroundColor Green }
        'NOTFOUND' { Write-Host "  적용된 블록이 없습니다." -ForegroundColor Yellow }
        'NOFILE' { Write-Host "  원격에 ~/.bashrc가 없습니다." -ForegroundColor Yellow }
        default {
            Write-Error ("원격 응답을 알 수 없습니다: {0}" -f (@($response.Lines) -join ' '))
            return
        }
    }

    # 실제로 제목 설정이 사라졌는지 새 대화형 셸에서 확인한다.
    $verify = @'
out=$(bash -ic 'printf "%s|%s" "$PS1" "$PROMPT_COMMAND"' 2>/dev/null)
case "$out" in
    *']0;'*) echo "RESULT=TITLE_SET" ;;
    *) echo "RESULT=TITLE_CLEAN" ;;
esac
'@

    $checked = Invoke-RemoteBashScript -Destination $dest -PortArgs $portArgs -Script $verify
    $state = Get-KeepTitleResult -Response $checked -Key 'RESULT'

    if ($Remove) {
        if ($state -eq 'TITLE_SET') { Write-Host "  확인: 프롬프트가 다시 탭 이름을 바꿉니다 (원래 동작)." -ForegroundColor DarkCyan }
        return
    }

    if ($state -eq 'TITLE_CLEAN') {
        Write-Host "  확인: 새 셸에서 제목 설정이 사라졌습니다. 다음 접속부터 탭 이름이 유지됩니다." -ForegroundColor Green
    }
    elseif ($state -eq 'TITLE_SET') {
        Write-Host "  확인: 아직 제목을 설정합니다." -ForegroundColor Yellow
        Write-Host "  로그인 셸이 ~/.bashrc를 읽지 않거나(~/.bash_profile 확인), /etc 쪽 설정이 더 늦게 실행되는 경우입니다." -ForegroundColor DarkCyan
    }
    else {
        Write-Host "  확인 단계를 건너뛰었습니다 (원격에서 대화형 bash를 실행하지 못했습니다)." -ForegroundColor DarkCyan
    }
}

function del-host {
    # known_hosts에서 지정한 IP 항목을 삭제한다(자동 백업 생성).
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Ip
    )

    $knownHosts = Join-Path $HOME ".ssh\known_hosts"

    if (-not (Test-Path -LiteralPath $knownHosts)) {
        Write-Error ("known_hosts 파일이 없습니다: {0}" -f $knownHosts)
        return
    }

    $backup = "{0}.{1}.bak" -f $knownHosts, (Get-Date -Format "yyyyMMddHHmmss")
    Copy-Item -LiteralPath $knownHosts -Destination $backup -Force

    $lines = @(Get-Content -LiteralPath $knownHosts)
    $result = New-Object System.Collections.Generic.List[string]
    $removedTokenCount = 0
    $removedLineCount = 0

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            $result.Add($line)
            continue
        }

        if ($line -notmatch '^\s*(\S+)(.*)$') {
            $result.Add($line)
            continue
        }

        $hostField = $matches[1]
        $rest = $matches[2]

        if ($hostField.StartsWith('|1|') -or $hostField.StartsWith('|2|')) {
            $result.Add($line)
            continue
        }

        $hostEntries = $hostField -split ','
        $keptHosts = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $hostEntries) {
            $isMatch = $false

            if ($entry -eq $Ip) {
                $isMatch = $true
            }
            elseif ($entry -match '^\[(.+)\]:(\d+)$' -and $matches[1] -eq $Ip) {
                $isMatch = $true
            }

            if ($isMatch) {
                $removedTokenCount++
            }
            else {
                $keptHosts.Add($entry)
            }
        }

        if ($keptHosts.Count -eq 0) {
            if ($hostEntries.Count -gt 0) {
                $removedLineCount++
            }
            continue
        }

        if ($keptHosts.Count -ne $hostEntries.Count) {
            $result.Add(($keptHosts -join ',') + $rest)
        }
        else {
            $result.Add($line)
        }
    }

    if ($removedTokenCount -eq 0) {
        Write-Host ("삭제할 IP를 찾지 못했습니다: {0}" -f $Ip) -ForegroundColor Yellow
        Write-Host ("backup: {0}" -f $backup) -ForegroundColor DarkCyan
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($knownHosts, $result, $utf8NoBom)

    Write-Host ("삭제 완료: {0}" -f $Ip) -ForegroundColor Green
    Write-Host ("삭제된 항목 수: {0}" -f $removedTokenCount)
    Write-Host ("완전히 제거된 라인 수: {0}" -f $removedLineCount)
    Write-Host ("backup: {0}" -f $backup) -ForegroundColor DarkCyan
}

#########################################################
# SSH 서버 선택 / 접속 영역 End
#########################################################


#########################################################
# SCP 파일 전송 / 원격 조회 (up/dn/rr/rl/rt/rs) 영역 Start
#########################################################

function Test-ScpReady {
    # fnc-ignore
    # up/dn/rr/rl 실행 전 scp 존재 여부와 $SV 계열(-RequireDst면 $DST 계열까지) 설정 여부를 확인한다.
    param([switch]$RequireDst)

    if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
        Write-Error "scp 명령을 찾지 못했습니다. OpenSSH Client가 설치되어 있어야 합니다."
        return $false
    }

    $names = @('SV', 'SVIP', 'SVPORT')
    if ($RequireDst) { $names += 'DST', 'DSTIP', 'DSTPORT' }

    foreach ($name in $names) {
        $var = Get-Variable $name -Scope Global -ErrorAction SilentlyContinue

        if (-not $var -or [string]::IsNullOrWhiteSpace([string]$var.Value)) {
            $hint = if ($name.StartsWith('DST')) { 'sd로 대상 서버를' } else { 'ss로 서버를' }
            Write-Host ("`${0}가 설정되지 않았습니다. 먼저 {1} 선택해 주세요." -f $name, $hint) -ForegroundColor Yellow
            return $false
        }
    }

    return $true
}

function set-svdir
{
    # 원격 작업 디렉터리($SVDIR)를 지정한다. up/dn/rr/rl의 상대 경로 기준이 된다. (축약: sw, -c: 해제 = xw)
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [Alias('c')]
        [switch]$Clear
    )

    if ($Clear) {
        Remove-Variable 'SVDIR' -Scope Global -ErrorAction SilentlyContinue
        Remove-Item 'Env:OMP_SVDIR' -ErrorAction SilentlyContinue
        Write-Host "원격 작업 디렉터리를 해제했습니다. (기준: 원격 홈)" -ForegroundColor Green
        return
    }

    # 인자 없이 부르면 현재 값을 보여준다 (설정 전이면 사용법).
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ([string]::IsNullOrWhiteSpace($global:SVDIR)) {
            Write-Host "사용법: sw <원격 디렉터리>   (Tab 자동완성 지원, 해제: xw)" -ForegroundColor Yellow
            Write-Host "  설정하면 up/dn/rr/rl의 상대 경로가 이 디렉터리 기준으로 해석됩니다." -ForegroundColor DarkCyan
        }
        else {
            Write-Host ("현재 원격 작업 디렉터리: {0}:{1}" -f $global:SV, $global:SVDIR) -ForegroundColor Green
        }
        return
    }

    if (-not (Test-ScpReady)) { return }

    # 없는 경로를 잡아두면 이후 전송이 조용히 실패하므로 미리 확인한다.
    $target = $Path.TrimEnd('/')
    if ([string]::IsNullOrEmpty($target)) { $target = '/' }

    if ($target -eq '~') {
        $remoteTest = 'test -d "$HOME"'
    }
    elseif ($target.StartsWith('~/')) {
        $remoteTest = 'test -d "$HOME/' + $target.Substring(2) + '"'
    }
    else {
        $remoteTest = 'test -d "' + $target + '"'
    }

    & ssh -o BatchMode=yes -o ConnectTimeout=3 -o RemoteCommand=none -o RequestTTY=no -p $global:SVPORT $global:SV $remoteTest 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Error ("원격 디렉터리를 찾지 못했습니다: {0}:{1}" -f $global:SV, $target)
        return
    }

    Set-Variable -Name 'SVDIR' -Value $target -Scope Global
    Set-Item -Path 'Env:OMP_SVDIR' -Value $target
    Write-Host ("원격 작업 디렉터리 설정: {0}:{1}" -f $global:SV, $target) -ForegroundColor Green
}

function sw {
    # alias-fn: 원격 작업 디렉터리($SVDIR)를 지정한다. (= set-svdir, 해제는 xw)
    param([Parameter(Position = 0)][string]$Path)
    set-svdir -Path $Path
}

function xw {
    # alias-fn: 원격 작업 디렉터리($SVDIR)를 해제한다. (= set-svdir -c)
    set-svdir -Clear
}

function Resolve-SvRemotePath {
    # fnc-ignore
    # $SVDIR이 설정돼 있으면 상대 경로를 그 디렉터리 기준으로 바꾼다.
    # /나 ~로 시작하는 경로는 그대로 두어 SVDIR을 벗어나는 탈출구로 쓴다.
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($global:SVDIR)) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return '~/' }
        return $Path
    }

    # SVDIR이 '/' 하나면 TrimEnd 결과가 빈 문자열이 되어 그대로 루트 기준이 된다.
    $base = ([string]$global:SVDIR).TrimEnd('/')

    if ([string]::IsNullOrWhiteSpace($Path)) { return "$base/" }
    if ($Path.StartsWith('/') -or $Path.StartsWith('~')) { return $Path }

    return "$base/$Path"
}

function up # scp local -> remote ($SV), 와일드카드(*.tar 등) 지원
{
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$LocalPath,

        [Parameter(Position = 1)]
        [string]$RemotePath = ''
    )

    if (-not (Test-ScpReady)) { return }

    # 대상 경로를 생략하면 $SVDIR(미설정이면 원격 홈)로 올린다.
    $RemotePath = Resolve-SvRemotePath -Path $RemotePath

    # PowerShell은 글롭을 자동 확장하지 않으므로, 와일드카드면 여기서 직접 확장해
    # 매칭된 모든 항목을 한 번의 scp 호출로 보낸다.
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($LocalPath)) {
        $resolved = @(Resolve-Path -Path $LocalPath -ErrorAction SilentlyContinue | ForEach-Object { $_.Path })

        if ($resolved.Count -eq 0) {
            Write-Error ("패턴과 일치하는 로컬 파일이 없습니다: {0}" -f $LocalPath)
            return
        }
    }
    else {
        if (-not (Test-Path -LiteralPath $LocalPath)) {
            Write-Error ("로컬 경로를 찾지 못했습니다: {0}" -f $LocalPath)
            return
        }

        $resolved = @((Resolve-Path -LiteralPath $LocalPath).Path)
    }

    # $SV는 ssh config 별칭이므로 User/IdentityFile은 config에서 가져오고 포트만 명시한다.
    $scpArgs = @('-P', $global:SVPORT)

    # 보낼 항목 중 디렉터리가 하나라도 있으면 -r을 붙인다.
    if (@($resolved | Where-Object { Test-Path -LiteralPath $_ -PathType Container }).Count -gt 0) {
        $scpArgs += '-r'
    }

    $target = "{0}:{1}" -f $global:SV, $RemotePath

    if ($resolved.Count -eq 1) {
        Write-Host ("upload: {0} -> {1} ({2}:{3})" -f $resolved[0], $target, $global:SVIP, $global:SVPORT) -ForegroundColor Green
    }
    else {
        Write-Host ("upload: {0}개 항목 -> {1} ({2}:{3})" -f $resolved.Count, $target, $global:SVIP, $global:SVPORT) -ForegroundColor Green
        $resolved | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor DarkCyan }
    }

    & scp @scpArgs @resolved $target

    if ($LASTEXITCODE -eq 0) {
        Write-Host "업로드 완료" -ForegroundColor Green
    }
    else {
        Write-Error ("업로드 실패 (exit code: {0})" -f $LASTEXITCODE)
    }
}

function dn # scp remote ($SV) -> $HOME/Downloads
{
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$RemotePath
    )

    if (-not (Test-ScpReady)) { return }

    # $SVDIR이 설정돼 있으면 상대 경로는 그 디렉터리 기준으로 해석한다.
    $RemotePath = Resolve-SvRemotePath -Path $RemotePath

    $downloadDir = Join-Path $HOME 'Downloads'
    $source = "{0}:{1}" -f $global:SV, $RemotePath

    # 와일드카드(*.tar 등)면 원격 확장은 scp가 수행하므로 디렉터리 검사를 건너뛴다 (여러 파일 다운로드).
    $hasWildcard = $RemotePath.IndexOfAny([char[]]@('*', '?')) -ge 0

    # 원격 경로가 디렉터리일 때만 -r을 붙인다.
    # 자동완성으로 고른 디렉터리는 ls -p 덕분에 끝에 / 가 붙어 있어 ssh 확인 없이 판별되고,
    # / 없이 직접 입력한 경로만 원격에서 test -d 로 확인한다.
    $isDir = -not $hasWildcard -and $RemotePath.EndsWith('/')

    if (-not $isDir -and -not $hasWildcard) {
        if ($RemotePath -eq '~') {
            $remoteTest = 'test -d "$HOME"'
        }
        elseif ($RemotePath.StartsWith('~/')) {
            $remoteTest = 'test -d "$HOME/' + $RemotePath.Substring(2) + '"'
        }
        else {
            $remoteTest = 'test -d "' + $RemotePath + '"'
        }

        & ssh -o BatchMode=yes -o ConnectTimeout=3 -o RemoteCommand=none -o RequestTTY=no -p $global:SVPORT $global:SV $remoteTest 2>$null
        $isDir = ($LASTEXITCODE -eq 0)
    }

    $scpArgs = @('-P', $global:SVPORT)

    if ($isDir) {
        $scpArgs += '-r'
        Write-Host "원격 디렉터리로 감지되어 -r 옵션으로 다운로드합니다." -ForegroundColor DarkCyan
    }

    Write-Host ("download: {0} -> {1} ({2}:{3})" -f $source, $downloadDir, $global:SVIP, $global:SVPORT) -ForegroundColor Green
    & scp @scpArgs $source $downloadDir

    if ($LASTEXITCODE -eq 0) {
        Write-Host "다운로드 완료" -ForegroundColor Green
    }
    else {
        Write-Error ("다운로드 실패 (exit code: {0})" -f $LASTEXITCODE)
    }
}

function rr # scp -3 remote ($SV) -> remote ($DST), 로컬 경유 전송 (대상 선택: sd)
{
    param(
        [Parameter(Position = 0)]
        [string]$SourcePath,

        [Parameter(Position = 1)]
        [string]$DestPath = '~/'
    )

    # 인자 없이 실행하면 사용법만 보여준다 (Mandatory 입력 프롬프트를 띄우지 않는다).
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        Write-Host "사용법: rr <SV 원본경로> [DST 대상경로(기본 ~/)]" -ForegroundColor Yellow
        Write-Host "  1) ss                  : 원본 서버(SV) 선택" -ForegroundColor DarkCyan
        Write-Host "  2) sd                  : 대상 서버(DST) 선택" -ForegroundColor DarkCyan
        Write-Host "  3) rr ~/a.txt ~/dir/   : Tab 자동완성 - 1번째 인자는 SV, 2번째 인자는 DST 경로" -ForegroundColor DarkCyan
        return
    }

    if (-not (Test-ScpReady -RequireDst)) { return }

    # 원본은 SV 기준이므로 $SVDIR을 적용한다 (대상은 DST 소속이라 적용하지 않는다).
    $SourcePath = Resolve-SvRemotePath -Path $SourcePath

    # 와일드카드(*.tar 등)면 원격 확장은 scp가 수행하므로 디렉터리 검사를 건너뛴다 (여러 파일 전송).
    $hasWildcard = $SourcePath.IndexOfAny([char[]]@('*', '?')) -ge 0

    # 원본이 디렉터리일 때만 -r을 붙인다 (dn과 동일: 끝 / 또는 SV에서 test -d 확인).
    $isDir = -not $hasWildcard -and $SourcePath.EndsWith('/')

    if (-not $isDir -and -not $hasWildcard) {
        if ($SourcePath -eq '~') {
            $remoteTest = 'test -d "$HOME"'
        }
        elseif ($SourcePath.StartsWith('~/')) {
            $remoteTest = 'test -d "$HOME/' + $SourcePath.Substring(2) + '"'
        }
        else {
            $remoteTest = 'test -d "' + $SourcePath + '"'
        }

        & ssh -o BatchMode=yes -o ConnectTimeout=3 -o RemoteCommand=none -o RequestTTY=no -p $global:SVPORT $global:SV $remoteTest 2>$null
        $isDir = ($LASTEXITCODE -eq 0)
    }

    # -3: 내 PC가 양쪽에 접속해 중계한다 (서버끼리 직접 신뢰 관계 불필요, scp 진행률 표시 없음).
    # 포트는 양쪽이 다를 수 있어 -P를 쓰지 않는다 — SV/DST 모두 ssh config 별칭이라 config가 공급한다.
    $scpArgs = @('-3')

    if ($isDir) {
        $scpArgs += '-r'
        Write-Host "원격 디렉터리로 감지되어 -r 옵션으로 전송합니다." -ForegroundColor DarkCyan
    }

    $source = "{0}:{1}" -f $global:SV, $SourcePath
    $target = "{0}:{1}" -f $global:DST, $DestPath

    Write-Host ("transfer: {0} -> {1} ({2} -> {3}, 로컬 경유)" -f $source, $target, $global:SVIP, $global:DSTIP) -ForegroundColor Green
    & scp @scpArgs $source $target

    if ($LASTEXITCODE -eq 0) {
        Write-Host "전송 완료" -ForegroundColor Green
    }
    else {
        Write-Error ("전송 실패 (exit code: {0})" -f $LASTEXITCODE)
    }
}

function Get-TextDisplayWidth {
    # fnc-ignore
    # 한글 등 전각 문자는 터미널에서 두 칸을 차지하므로 글자 수 대신 이 폭으로 자리를 맞춘다.
    param([string]$Text)

    $width = 0
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if (($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFE30 -and $code -le 0xFE6F) -or
            ($code -ge 0xFF00 -and $code -le 0xFF60) -or
            ($code -ge 0xFFE0 -and $code -le 0xFFE6)) {
            $width += 2
        }
        else {
            $width += 1
        }
    }

    $width
}

function Get-RemoteEntryStyle {
    # fnc-ignore
    # 파일 종류에 맞는 아이콘과 색을 고른다. 색은 lsd와 같은 구성 - 디렉터리 파랑, 실행 초록, 링크 청록, 그 밖은 기본색.
    param(
        [string]$Name,
        [string]$Type = 'file'
    )

    $esc = [char]27
    $blue = "$esc[38;2;0;135;255m"     # 디렉터리
    $green = "$esc[38;2;0;215;0m"      # 실행 파일
    $cyan = "$esc[38;2;0;215;215m"     # 심볼릭 링크
    $plain = ''                        # 일반 파일은 터미널 기본색

    switch ($Type) {
        'dir'    { return @{ Icon = [char]::ConvertFromUtf32(0xF024B); Color = $blue } }
        'link'   { return @{ Icon = [char]::ConvertFromUtf32(0xF0337); Color = $cyan } }
        'fifo'   { return @{ Icon = [char]::ConvertFromUtf32(0xF0337); Color = $plain } }
        'socket' { return @{ Icon = [char]::ConvertFromUtf32(0xF0337); Color = $plain } }
    }

    $color = if ($Type -eq 'exec') { $green } else { $plain }
    $ext = [IO.Path]::GetExtension($Name).TrimStart('.').ToLower()

    # 아이콘만 확장자로 구분한다 (색은 종류로만).
    $icon = switch ($ext) {
        { $_ -in 'zip', 'gz', 'tgz', 'tar', 'bz2', 'xz', 'zst', '7z', 'rar', 'jar', 'war', 'rpm', 'deb' } { [char]::ConvertFromUtf32(0xF410); break }
        { $_ -in 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'svg', 'ico', 'webp', 'mp4', 'avi', 'mkv' }          { [char]::ConvertFromUtf32(0xF1C5); break }
        { $_ -in 'c', 'h', 'cpp', 'hpp', 'cc', 'cs', 'py', 'js', 'ts', 'go', 'rs', 'java', 'rb', 'php', 'pl', 'lua', 'sql', 'ps1', 'psm1' } { [char]::ConvertFromUtf32(0xF1C9); break }
        { $_ -in 'sh', 'bash', 'zsh', 'ksh', 'run' }                                                      { [char]::ConvertFromUtf32(0xF489); break }
        { $_ -in 'conf', 'cfg', 'ini', 'yaml', 'yml', 'json', 'xml', 'toml', 'properties', 'env', 'service' } { [char]::ConvertFromUtf32(0xF0493); break }
        'pdf'                                                                                             { [char]::ConvertFromUtf32(0xF1C1); break }
        { $_ -in 'log', 'out', 'err', 'md', 'txt', 'rst', 'csv', 'doc', 'docx', 'xls', 'xlsx' }           { [char]::ConvertFromUtf32(0xF0219); break }
        default                                                                                           { $null }
    }

    if (-not $icon) {
        $icon = if ($Type -eq 'exec') { [char]::ConvertFromUtf32(0xF489) } else { [char]::ConvertFromUtf32(0xF0214) }
    }

    return @{ Icon = $icon; Color = $color }
}

function Write-RemoteListing {
    # fnc-ignore
    # 원격에서 받아온 이름 목록(ls -1 -F)에 아이콘·색을 입혀 여러 열로 그린다. (rl 전용 - 서버에는 아무것도 설치하지 않는다)
    param(
        [string[]]$Names,
        [int]$Width = 0
    )

    $esc = [char]27

    $entries = @(foreach ($raw in $Names) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $name = $raw.TrimEnd()
        $type = 'file'

        switch -CaseSensitive ($name.Substring($name.Length - 1)) {
            '/' { $type = 'dir' }
            '*' { $type = 'exec' }
            '@' { $type = 'link' }
            '|' { $type = 'fifo' }
            '=' { $type = 'socket' }
        }

        # ls -F가 붙인 종류 표시는 이름에서 떼어낸다.
        if ($type -ne 'file') { $name = $name.Substring(0, $name.Length - 1) }

        $style = Get-RemoteEntryStyle -Name $name -Type $type
        [pscustomobject]@{
            Name  = $name
            Icon  = $style.Icon
            Color = $style.Color
            Width = (Get-TextDisplayWidth $name) + 2   # 아이콘 + 사이 공백
        }
    })

    if ($entries.Count -eq 0) { return }

    if ($Width -le 0) { $Width = try { [Console]::WindowWidth } catch { 80 } }

    $cell = ($entries | Measure-Object Width -Maximum).Maximum + 2
    $cols = [Math]::Max(1, [Math]::Floor($Width / $cell))
    $rows = [Math]::Ceiling($entries.Count / $cols)

    for ($r = 0; $r -lt $rows; $r++) {
        $line = ''

        for ($c = 0; $c -lt $cols; $c++) {
            # ls -C처럼 세로로 먼저 채운다.
            $i = $c * $rows + $r
            if ($i -ge $entries.Count) { continue }

            $e = $entries[$i]
            $reset = if ($e.Color) { "$esc[0m" } else { '' }
            $line += "{0}{1} {2}{3}" -f $e.Color, $e.Icon, $e.Name, $reset
            if ($c -lt $cols - 1) { $line += ' ' * [Math]::Max(1, $cell - $e.Width) }
        }

        [Console]::Write($line.TrimEnd() + "`n")
    }
}

function Format-RemoteSize {
    # fnc-ignore
    # 바이트를 lsd처럼 "0 B / 28 B / 4.0 KB / 158 MB / 1.5 GB"로 쓰고 크기대에 맞는 색을 고른다. (rl -l 전용)
    param([long]$Bytes)

    $esc = [char]27
    $grey = "$esc[38;5;245m"     # 0 바이트
    $small = "$esc[38;5;229m"    # ~1MB
    $medium = "$esc[38;5;216m"   # ~1GB
    $large = "$esc[38;5;172m"    # 1GB 이상

    if ($Bytes -le 0) { return @{ Text = '0 B'; Color = $grey } }

    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $value = [double]$Bytes
    $unit = 0

    while ($value -ge 1024 -and $unit -lt ($units.Count - 1)) {
        $value = $value / 1024
        $unit++
    }

    # 10 미만이면 소수 한 자리까지 (lsd와 같은 표기)
    $text = if ($unit -eq 0) { "{0:0} {1}" -f $value, $units[$unit] }
        elseif ($value -lt 10) { "{0:0.0} {1}" -f $value, $units[$unit] }
        else { "{0:0} {1}" -f $value, $units[$unit] }

    $color = if ($Bytes -lt 1MB) { $small } elseif ($Bytes -lt 1GB) { $medium } else { $large }

    @{ Text = $text; Color = $color }
}

function Format-RemotePermission {
    # fnc-ignore
    # 권한 문자열에 lsd와 같은 색을 입힌다 - 종류 문자는 파랑, r 진초록, w 노랑, x 빨강, 없음은 회색. (rl -l 전용)
    param([string]$Permission)

    $esc = [char]27
    $blue = "$esc[34m"
    $read = "$esc[38;5;28m"
    $write = "$esc[33m"
    $exec = "$esc[31m"
    $none = "$esc[38;5;245m"
    $reset = "$esc[0m"

    $out = ''

    for ($i = 0; $i -lt $Permission.Length; $i++) {
        $ch = $Permission[$i]

        # 첫 글자는 파일 종류. lsd처럼 일반 파일은 점으로 보여준다.
        if ($i -eq 0) {
            $shown = if ($ch -eq '-') { '.' } else { $ch }
            $out += "$blue$shown$reset"
            continue
        }

        $color = switch ($ch) {
            'r' { $read; break }
            'w' { $write; break }
            'x' { $exec; break }
            's' { $exec; break }
            'S' { $exec; break }
            't' { $exec; break }
            'T' { $exec; break }
            default { $none }
        }

        $out += "$color$ch$reset"
    }

    $out
}

function Format-RemoteDate {
    # fnc-ignore
    # 수정 시각을 "2026-09-21 월 17:18:47"로 쓰고 lsd처럼 최근일수록 밝은 초록으로 표시한다. (rl -l 전용)
    param([datetime]$Date)

    $esc = [char]27
    $age = (Get-Date) - $Date

    $color = if ($age.TotalHours -lt 1) { "$esc[38;5;40m" }
        elseif ($age.TotalDays -lt 1) { "$esc[38;5;42m" }
        else { "$esc[38;5;36m" }

    $day = '일월화수목금토'[[int]$Date.DayOfWeek]

    @{ Text = ("{0:yyyy-MM-dd} {1} {0:HH:mm:ss}" -f $Date, $day); Color = $color }
}

function Write-RemoteLongListing {
    # fnc-ignore
    # 원격 ls -l 결과를 lsd -al과 같은 색 구성으로 다시 그린다. (rl -l 전용, 형식이 다르면 받은 줄을 그대로 출력)
    param([string[]]$Lines)

    $esc = [char]27
    $reset = "$esc[0m"
    $dim = "$esc[38;5;245m"

    # ls -l 한 줄: 권한 링크수 소유자 그룹 크기 날짜_시각 이름
    $pattern = '^(?<perm>[bcdlps-][rwxsStT-]{9}[.+@]?)\s+(?<links>\d+)\s+(?<user>\S+)\s+(?<group>\S+)\s+(?<size>\d+)\s+(?<date>\d{4}-\d{2}-\d{2})_(?<time>\d{2}:\d{2}:\d{2})\s+(?<name>.*)$'

    $rows = @()
    $raw = @()

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^total\s') { continue }          # lsd는 합계 줄을 쓰지 않는다

        $m = [regex]::Match($line, $pattern)
        if (-not $m.Success) {
            $raw += $line
            continue
        }

        $perm = $m.Groups['perm'].Value
        $name = $m.Groups['name'].Value
        $target = ''

        # 심볼릭 링크는 "이름 -> 대상" 형태로 온다.
        if ($perm[0] -eq 'l' -and $name -match '^(?<n>.*?) -> (?<t>.*)$') {
            $target = $Matches['t']
            $name = $Matches['n']
        }

        $type = switch ($perm[0]) {
            'd' { 'dir'; break }
            'l' { 'link'; break }
            'p' { 'fifo'; break }
            's' { 'socket'; break }
            default { if ($perm -match '^.{1,3}x') { 'exec' } else { 'file' } }
        }

        $style = Get-RemoteEntryStyle -Name $name -Type $type
        $size = Format-RemoteSize -Bytes ([long]$m.Groups['size'].Value)
        $stamp = [datetime]::ParseExact(("{0} {1}" -f $m.Groups['date'].Value, $m.Groups['time'].Value), 'yyyy-MM-dd HH:mm:ss', $null)
        $date = Format-RemoteDate -Date $stamp

        $rows += [pscustomobject]@{
            Perm   = $perm
            Size   = $size
            Date   = $date
            Icon   = $style.Icon
            Color  = $style.Color
            Name   = $name
            Target = $target
        }
    }

    foreach ($line in $raw) { Write-Host $line }
    if ($rows.Count -eq 0) { return }

    $sizeWidth = ($rows | ForEach-Object { $_.Size.Text.Length } | Measure-Object -Maximum).Maximum

    foreach ($row in $rows) {
        $nameText = if ($row.Color) { "{0}{1} {2}$reset" -f $row.Color, $row.Icon, $row.Name } else { "{0} {1}" -f $row.Icon, $row.Name }
        if ($row.Target) { $nameText += " $dim-> $($row.Target)$reset" }

        [Console]::Write(("{0}  {1}{2}$reset  {3}{4}$reset  {5}`n" -f
            (Format-RemotePermission -Permission $row.Perm),
            $row.Size.Color,
            $row.Size.Text.PadLeft($sizeWidth),
            $row.Date.Color,
            $row.Date.Text,
            $nameText))
    }
}

function rl # ls remote ($SV), 경로 생략 시 $SVDIR 목록. 기본은 색상 짧은 목록, -l이면 상세 목록 (-a는 항상 포함)
{
    # param으로 받으면 -t, -r 같은 ls 옵션이 PowerShell 매개변수로 해석되므로 $args를 직접 나눈다.
    $options = @()
    $paths = @()

    foreach ($arg in $args) {
        $text = [string]$arg
        if ($text.StartsWith('-')) { $options += $text } else { $paths += $text }
    }

    if (-not (Test-ScpReady)) { return }

    # 경로를 생략하면 $SVDIR(미설정이면 원격 홈)을 보여준다. 상대 경로 해석은 up/dn과 같다.
    if ($paths.Count -eq 0) { $paths = @('') }

    $shown = @()
    $quoted = @()

    foreach ($path in $paths) {
        $resolved = Resolve-SvRemotePath -Path $path
        $shown += $resolved

        # 원격 셸이 공백 경로를 쪼개지 않게 따옴표로 감싼다. ~는 따옴표 안에서 펼쳐지지 않아 $HOME으로 바꾸고,
        # 마지막 이름에 와일드카드(*.log 등)가 있으면 그 부분만 따옴표 밖에 두어 원격 셸이 펼치게 한다.
        $dirPart = $resolved
        $namePart = ''
        $slash = $resolved.LastIndexOf('/')
        $leaf = $resolved.Substring($slash + 1)

        if ($leaf.IndexOfAny([char[]]@('*', '?')) -ge 0) {
            $dirPart = $resolved.Substring(0, $slash + 1)
            $namePart = $leaf
        }

        if ($dirPart -eq '~' -or $dirPart.StartsWith('~/')) {
            $dirPart = '$HOME' + $dirPart.Substring(1)
        }

        $quoted += if ($dirPart) { '"' + $dirPart + '"' + $namePart } else { $namePart }
    }

    # 다른 명령으로 넘길 때(rl | sls log)는 색상 코드가 섞이지 않게 끈다.
    $piped = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $color = if ($piped) { '--color=never' } else { '--color=always' }

    # -a는 항상. -l(-la, --long 등 포함)을 준 경우에만 상세 목록으로 본다 (-h로 읽기 쉬운 크기).
    $isLong = @($options | Where-Object { $_ -cmatch '^-[A-Za-z]*l' -or $_ -eq '--long' }).Count -gt 0

    # 짧은 목록은 서버 색상(LS_COLORS)에 기대지 않고 이름만 받아 이 PC에서 아이콘·색을 입혀 그린다.
    # (갓 설치한 서버에서도 똑같이 보이도록 - 서버에는 아무것도 설치하지 않는다)
    $renderLocal = -not $piped

    $remoteCmd = if ($isLong) {
        # 상세 목록도 색은 이 PC에서 입힌다. 시각은 파싱하기 좋게 고정 형식으로 받는다.
        if ($piped) {
            (@('ls', '-a', '-h', $color) + $options + $quoted) -join ' '
        }
        else {
            # 사용자가 이미 -l 계열을 줬으므로 중복해서 붙이지 않는다. (lsd식 --long은 ls가 모르므로 -l로 바꾼다)
            $lsOptions = @($options | ForEach-Object { if ($_ -eq '--long') { '-l' } else { $_ } })
            (@('ls', '-a') + $lsOptions + @('--color=never', '--time-style=+%Y-%m-%d_%H:%M:%S') + $quoted) -join ' '
        }
    }
    elseif ($piped) {
        (@('ls', '-a', '--color=never') + $options + @('-1') + $quoted) -join ' '
    }
    else {
        # 우리 옵션을 뒤에 두어 사용자가 준 -C/-1/--color 보다 우선하게 한다.
        (@('ls', '-a') + $options + @('-1', '-F', '--color=never') + $quoted) -join ' '
    }

    # 어느 서버의 어느 경로인지가 한눈에 들어오도록 서버:경로는 굵은 코랄, 접속 정보는 흐리게 쓴다.
    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"
    Write-Host ("{0}list:$esc[0m {1}{2}:{3}$esc[0m  {0}({4}:{5})$esc[0m" -f $sub, $head, $global:SV, ($shown -join ' '), $global:SVIP, $global:SVPORT)

    # config의 Host * RemoteCommand와 충돌하지 않게 무효화하고, 한글 파일명이 깨지지 않게 조회 중에만 UTF-8로 받는다.
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

        if ($renderLocal) {
            $received = @(& ssh -o BatchMode=yes -o ConnectTimeout=5 -o RemoteCommand=none -o RequestTTY=no -p $global:SVPORT $global:SV $remoteCmd)
            $exit = $LASTEXITCODE
            $group = [System.Collections.Generic.List[string]]::new()

            foreach ($line in $received) {
                # 경로를 여러 개 주면 ls가 "경로:" 머리글과 빈 줄로 묶어서 내보낸다.
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                if ($paths.Count -gt 1 -and $line.EndsWith(':')) {
                    if ($group.Count -gt 0) {
                        if ($isLong) { Write-RemoteLongListing -Lines $group } else { Write-RemoteListing -Names $group }
                        $group.Clear()
                    }

                    Write-Host $line -ForegroundColor DarkCyan
                    continue
                }

                $group.Add($line)
            }

            if ($group.Count -gt 0) {
                if ($isLong) { Write-RemoteLongListing -Lines $group } else { Write-RemoteListing -Names $group }
            }

            $global:LASTEXITCODE = $exit
        }
        else {
            & ssh -o BatchMode=yes -o ConnectTimeout=5 -o RemoteCommand=none -o RequestTTY=no -p $global:SVPORT $global:SV $remoteCmd
        }
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error ("원격 목록 조회 실패 (exit code: {0})" -f $LASTEXITCODE)
    }
}

function Format-RemoteUptime {
    # fnc-ignore
    # /proc/uptime의 초를 "12일 03시간 / 3시간 07분 / 12분"으로 쓴다. (rs 표시용)
    param([double]$Seconds)

    $total = [int][Math]::Round($Seconds)
    $days = [int]($total / 86400)
    $hours = [int](($total % 86400) / 3600)
    $mins = [int](($total % 3600) / 60)

    if ($days -gt 0) { return ("{0}일 {1:d2}시간" -f $days, $hours) }
    if ($hours -gt 0) { return ("{0}시간 {1:d2}분" -f $hours, $mins) }
    return ("{0}분" -f $mins)
}

function New-RatioBar {
    # fnc-ignore
    # 0~1 비율을 막대로 만들고 70% / 90%를 넘으면 색을 올린다. (rs 표시용)
    param(
        [double]$Ratio,
        [int]$Width = 14
    )

    if ($Ratio -lt 0) { $Ratio = 0 }
    if ($Ratio -gt 1) { $Ratio = 1 }

    $esc = [char]27
    $filled = [int][Math]::Round($Width * $Ratio)
    $color = if ($Ratio -ge 0.9) { "$esc[38;5;203m" } elseif ($Ratio -ge 0.7) { "$esc[38;5;179m" } else { "$esc[38;5;108m" }

    "{0}{1}$esc[38;5;238m{2}$esc[0m" -f $color, (([string][char]0x2588) * $filled), (([string][char]0x2591) * ($Width - $filled))
}

function Format-RemoteLogLine {
    # fnc-ignore
    # 로그 한 줄에 심각도에 따라 색을 입혀 돌려준다. (rt 전용 - 서버 설정과 무관하게 이 PC에서 입힌다)
    # 대량 출력에서는 줄마다 정규식을 새로 만드는 비용이 커지므로 처음 한 번만 만들어 재사용한다.
    param([string]$Line)

    if (-not $script:rt_log_style) {
        $esc = [char]27
        $script:rt_log_style = @{
            Red    = "$esc[38;2;255;89;94m"
            Yellow = "$esc[38;2;255;202;58m"
            Cyan   = "$esc[38;5;80m"
            Dim    = "$esc[38;5;245m"
            Reset  = "$esc[0m"
            Head   = [regex]::new('^==>.*<==$')
            # 줄 맨 앞(시각 뒤여도 된다)에 오는 수준 표시. Info/Debug로 시작하는 형식이 여기서 잡힌다.
            Level  = [regex]::new('^[\s\[\(<]*(trace|debug|verbose|fine|information|info|notice|warning|warn|error|err|fatal|critical|crit|severe|alert|emerg|panic)(?![A-Za-z])[\]\)>]*\s*[:\-|]*\s*', 'IgnoreCase')
            Error  = [regex]::new('(?i)(\b(fatal|critical|crit|alert|emerg|errors?|err|fail|failed|failures?|denied|refused)\b|no such file|cannot open|permission denied)')
            Warn   = [regex]::new('(?i)\b(warn|warning)\b')
            Stamp  = [regex]::new('^(\S{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}|\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}[^\s]*|\[[^\]]+\])')
        }
    }

    $style = $script:rt_log_style

    # tail이 파일을 바꿔 읽을 때 넣는 머리글
    if ($style.Head.IsMatch($Line)) { return ("{0}{1}{2}" -f $style.Cyan, $Line, $style.Reset) }

    # 수준 표시를 먼저 본다. 줄 맨 앞에 없으면(시각이 앞선 형식이면) 시각을 떼고 다시 본다.
    # 수준이 있으면 그 수준을 따른다 (본문에 error 같은 낱말이 섞였다고 Info 줄이 빨개지지 않게).
    # [DEBUG]처럼 대괄호로 감싼 수준도 있어 시각 규칙보다 먼저 확인한다.
    $stamp = $style.Stamp.Match($Line)
    $head = ''
    $rest = $Line
    $level = $style.Level.Match($Line)

    if (-not $level.Success -and $stamp.Success) {
        $head = $stamp.Value
        $rest = $Line.Substring($stamp.Length)
        $level = $style.Level.Match($rest)
    }

    if ($level.Success) {
        switch -Regex ($level.Groups[1].Value.ToLowerInvariant()) {
            '^(fatal|critical|crit|severe|alert|emerg|panic|error|err)$' { return ("{0}{1}{2}" -f $style.Red, $Line, $style.Reset) }
            '^(warning|warn)$' { return ("{0}{1}{2}" -f $style.Yellow, $Line, $style.Reset) }
            '^(debug|trace|verbose|fine)$' { return ("{0}{1}{2}" -f $style.Dim, $Line, $style.Reset) }
            default {
                # info/notice는 흔하고 대개 정상 동작이라 시각·수준만 흐리게 하고 본문은 그대로 둔다.
                return ("{0}{1}{2}{3}{4}" -f $style.Dim, $head, $level.Value, $style.Reset, $rest.Substring($level.Length))
            }
        }
    }

    if ($style.Error.IsMatch($Line)) { return ("{0}{1}{2}" -f $style.Red, $Line, $style.Reset) }
    if ($style.Warn.IsMatch($Line)) { return ("{0}{1}{2}" -f $style.Yellow, $Line, $style.Reset) }

    # 수준 표시가 없는 줄은 맨 앞 시각만 흐리게 해서 본문이 눈에 들어오게 한다.
    if ($stamp.Success) { return ("{0}{1}{2}{3}" -f $style.Dim, $stamp.Value, $style.Reset, $Line.Substring($stamp.Length)) }

    $Line
}

function rs {
    # 선택된 SV의 상태를 한 화면으로 요약한다. (가동시간·부하·메모리·디스크·상위 프로세스·접속자 / 원격에는 설치할 것이 없다)
    param([Alias('n')][int]$Top = 5)

    if (-not (Test-ScpReady)) { return }

    # 갓 설치한 서버에서도 되도록 /proc과 coreutils만 쓴다. 한 번의 접속으로 모두 받아 '@@구간' 표시로 나눈다.
    # (여러 줄 문자열은 CR이 섞여 원격 셸이 오해할 수 있어 한 줄로 이어 붙인다)
    $segments = @(
        'echo @@host',
        'hostname 2>/dev/null',
        'grep -E ^PRETTY_NAME= /etc/os-release 2>/dev/null',
        'uname -srm 2>/dev/null',
        'echo @@uptime',
        'cat /proc/uptime 2>/dev/null',
        'echo @@load',
        'cat /proc/loadavg 2>/dev/null',
        'grep -c ^processor /proc/cpuinfo 2>/dev/null',
        'echo @@mem',
        'grep -E "^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):" /proc/meminfo 2>/dev/null',
        'echo @@disk',
        'df -P -k 2>/dev/null',
        'echo @@proc',
        ('ps -eo pcpu=,pmem=,rss=,comm= 2>/dev/null | sort -k1 -rn | head -{0}' -f [Math]::Max(1, $Top)),
        'echo @@who',
        'who 2>/dev/null | head -5',
        'echo @@end'
    )

    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"
    $dim = "$esc[38;5;245m"
    $label = "$esc[38;5;110m"
    $reset = "$esc[0m"
    $labelWidth = 12

    function Write-Row {
        # fnc-ignore
        param([string]$Name, [string]$Value)
        $pad = [Math]::Max(1, $labelWidth - (Get-TextDisplayWidth $Name))
        Write-Host ("  {0}{1}{2}{3}{4}" -f $label, $Name, $reset, (' ' * $pad), $Value)
    }

    Write-Host ("{0}status:$esc[0m {1}{2}$esc[0m  {0}({3}:{4})$esc[0m" -f $sub, $head, $global:SV, $global:SVIP, $global:SVPORT)

    $response = Invoke-SvSsh -Command ($segments -join '; ')

    if ($response.ExitCode -ne 0) {
        Write-Error ("원격 상태 조회 실패 (exit code: {0})" -f $response.ExitCode)
        return
    }

    $bucket = @{}
    $section = ''

    foreach ($raw in @($response.Lines)) {
        $line = [string]$raw

        if ($line.StartsWith('@@')) {
            $section = $line.Substring(2).Trim()
            if (-not $bucket.ContainsKey($section)) { $bucket[$section] = [System.Collections.Generic.List[string]]::new() }
            continue
        }

        if (-not $section -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $bucket[$section].Add($line.TrimEnd())
    }

    if (-not $bucket.ContainsKey('end')) {
        Write-Host "  조회가 중간에 끊겼습니다. 아래 내용은 받은 부분까지입니다." -ForegroundColor Yellow
    }

    # ── 호스트 / 커널 ──
    $hostLines = @($bucket['host'])
    $hostName = if ($hostLines.Count -gt 0) { $hostLines[0] } else { '' }
    $pretty = ''
    $kernel = ''

    foreach ($line in $hostLines) {
        if ($line -match '^PRETTY_NAME=\s*"?(.+?)"?\s*$') { $pretty = $Matches[1] }
        elseif ($line -ne $hostName) { $kernel = $line }
    }

    if ($hostName -or $pretty -or $kernel) {
        $parts = @($hostName, $pretty, $kernel) | Where-Object { $_ }
        Write-Row '호스트' ($parts -join " $dim·$reset ")
    }

    # ── 가동시간 ──
    $uptimeLine = if (@($bucket['uptime']).Count -gt 0) { @($bucket['uptime'])[0] } else { '' }

    if ($uptimeLine -match '^\s*([0-9.]+)') {
        $booted = (Get-Date).AddSeconds( - [double]$Matches[1])
        Write-Row '가동시간' ("{0}  {1}({2:yyyy-MM-dd HH:mm} 부팅){3}" -f (Format-RemoteUptime ([double]$Matches[1])), $dim, $booted, $reset)
    }

    # ── 부하 ──
    $loadLines = @($bucket['load'])

    if ($loadLines.Count -gt 0 -and $loadLines[0] -match '^([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)') {
        $one = [double]$Matches[1]
        $text = "{0} {1} {2}" -f $Matches[1], $Matches[2], $Matches[3]
        $cpu = 0

        if ($loadLines.Count -gt 1) { [void][int]::TryParse($loadLines[1].Trim(), [ref]$cpu) }

        if ($cpu -gt 0) {
            # 1분 부하를 코어 수로 나눠 100%에 얼마나 가까운지로 본다.
            $text = "{0}  {1}(CPU {2}개 · 1분 {3:0}%){4}" -f $text, $dim, $cpu, ($one / $cpu * 100), $reset
        }

        Write-Row '부하' $text
    }

    # ── 메모리 / 스왑 ──
    $meminfo = @{}

    foreach ($line in @($bucket['mem'])) {
        if ($line -match '^(\w+):\s+(\d+)\s*kB') { $meminfo[$Matches[1]] = [long]$Matches[2] }
    }

    if ($meminfo.ContainsKey('MemTotal') -and $meminfo['MemTotal'] -gt 0) {
        $total = $meminfo['MemTotal']

        # MemAvailable이 없는 옛 커널은 free+buffers+cached로 대신 센다.
        $available = if ($meminfo.ContainsKey('MemAvailable')) { $meminfo['MemAvailable'] }
            else { [long]$meminfo['MemFree'] + [long]$meminfo['Buffers'] + [long]$meminfo['Cached'] }

        $used = $total - $available
        $ratio = $used / $total

        Write-Row '메모리' ("{0} {1,3:0}%  {2}{3} / {4}{5}" -f (New-RatioBar -Ratio $ratio), ($ratio * 100), $dim, (Format-RemoteSize ($used * 1024)).Text, (Format-RemoteSize ($total * 1024)).Text, $reset)
    }

    if ($meminfo.ContainsKey('SwapTotal') -and $meminfo['SwapTotal'] -gt 0) {
        $swapTotal = $meminfo['SwapTotal']
        $swapUsed = $swapTotal - [long]$meminfo['SwapFree']
        $swapRatio = $swapUsed / $swapTotal

        Write-Row '스왑' ("{0} {1,3:0}%  {2}{3} / {4}{5}" -f (New-RatioBar -Ratio $swapRatio), ($swapRatio * 100), $dim, (Format-RemoteSize ($swapUsed * 1024)).Text, (Format-RemoteSize ($swapTotal * 1024)).Text, $reset)
    }

    # ── 디스크 ──
    # tmpfs 같은 가상 파일시스템은 용량 점검에 의미가 없어 제외한다.
    $skip = @('tmpfs', 'devtmpfs', 'none', 'overlay', 'udev', 'squashfs', 'shm', 'efivarfs', 'ramfs', 'cgroup')
    $disks = [System.Collections.Generic.List[object]]::new()

    foreach ($line in @($bucket['disk'])) {
        if ($line -match '^Filesystem') { continue }

        # df -P는 "장치 1K블록 사용 가용 사용% 마운트" 6열로 줄바꿈 없이 내보낸다.
        $cols = -split $line
        if ($cols.Count -lt 6) { continue }
        if ($skip -contains $cols[0].ToLowerInvariant()) { continue }

        $totalKb = 0L
        $usedKb = 0L

        if (-not [long]::TryParse($cols[1], [ref]$totalKb)) { continue }
        [void][long]::TryParse($cols[2], [ref]$usedKb)
        if ($totalKb -le 0) { continue }

        # 사용률은 df가 적은 값(예약 블록을 뺀 기준)을 그대로 쓴다. df -h와 숫자가 달라 보이지 않게 하려는 것.
        $ratio = if ($cols[4] -match '^([0-9]+)%$') { [double]$Matches[1] / 100 } else { $usedKb / $totalKb }

        $disks.Add([pscustomobject]@{ Mount = $cols[5]; Ratio = $ratio; Used = $usedKb; Total = $totalKb })
    }

    $shownDisks = @($disks | Sort-Object Ratio -Descending | Select-Object -First 5)

    for ($i = 0; $i -lt $shownDisks.Count; $i++) {
        $row = $shownDisks[$i]
        $name = if ($i -eq 0) { '디스크' } else { '' }

        Write-Row $name ("{0} {1,3:0}%  {2,-16} {3}{4} / {5}{6}" -f (New-RatioBar -Ratio $row.Ratio), ($row.Ratio * 100), $row.Mount, $dim, (Format-RemoteSize ($row.Used * 1024)).Text, (Format-RemoteSize ($row.Total * 1024)).Text, $reset)
    }

    # ── 상위 프로세스 ──
    $procLines = @($bucket['proc'])
    $shownProc = 0

    foreach ($line in $procLines) {
        $cols = -split $line.Trim()
        if ($cols.Count -lt 4) { continue }

        $pcpu = 0.0
        $pmem = 0.0
        $rss = 0L
        [void][double]::TryParse($cols[0], [ref]$pcpu)
        [void][double]::TryParse($cols[1], [ref]$pmem)
        [void][long]::TryParse($cols[2], [ref]$rss)

        # comm에 공백이 있을 수 있어 나머지 열을 모두 이름으로 본다.
        $command = ($cols[3..($cols.Count - 1)] -join ' ')
        $name = if ($shownProc -eq 0) { '프로세스' } else { '' }

        Write-Row $name ("{0,5:0.0}% cpu  {1,4:0.0}% mem  {2}{3,-9}{4} {5}" -f $pcpu, $pmem, $dim, (Format-RemoteSize ($rss * 1024)).Text, $reset, $command)
        $shownProc++
    }

    # ── 접속자 ──
    $whoLines = @($bucket['who'])

    if ($whoLines.Count -eq 0) {
        Write-Row '접속자' ("{0}없음{1}" -f $dim, $reset)
    }
    else {
        for ($i = 0; $i -lt $whoLines.Count; $i++) {
            $name = if ($i -eq 0) { '접속자' } else { '' }
            Write-Row $name (($whoLines[$i] -replace '\s+', ' ').Trim())
        }
    }

    if ($bucket.Count -eq 0) {
        Write-Host "  /proc을 읽지 못했습니다. 리눅스 서버가 아닐 수 있습니다." -ForegroundColor Yellow
    }
}

function rt {
    # SV의 원격 로그를 실시간으로 따라 본다. 색상 강조는 이 PC에서 입힌다. (-n 줄수, -p 패턴, -o 한 번만, 종료 Ctrl+C)
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [Alias('n')][int]$Lines = 50,
        [Alias('p')][string]$Pattern,
        [Alias('o')][switch]$Once
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "사용법: rt <원격 로그경로> [-n 줄수] [-p 패턴] [-o 한 번만]   (Tab 자동완성, 종료 Ctrl+C)" -ForegroundColor Yellow
        Write-Host "  예: rt /var/log/messages   /   rt app.log -p error   /   rt /var/log/secure -n 200 -o" -ForegroundColor DarkCyan
        return
    }

    if (-not (Test-ScpReady)) { return }

    if ($Pattern -and $Pattern.Contains("'")) {
        Write-Error "패턴에 작은따옴표(')는 쓸 수 없습니다. 다른 표현으로 적어 주세요."
        return
    }

    # 원격 셸이 공백 경로를 쪼개지 않게 따옴표로 감싼다. ~는 따옴표 안에서 펼쳐지지 않아 $HOME으로 바꾼다. (rl과 같은 규칙)
    $resolved = Resolve-SvRemotePath -Path $Path
    $quoted = if ($resolved -eq '~' -or $resolved.StartsWith('~/')) { '"$HOME' + $resolved.Substring(1) + '"' } else { '"' + $resolved + '"' }

    # -F는 파일이 교체(로그 로테이션)돼도 이름을 다시 열어 계속 따라간다.
    $remoteCmd = "tail -n {0}{1} {2}" -f [Math]::Max(1, $Lines), $(if ($Once) { '' } else { ' -F' }), $quoted

    if ($Pattern) {
        # grep은 줄 단위로 바로 흘려보내야 실시간으로 보인다 (--line-buffered).
        $remoteCmd = "{0} | grep --line-buffered -i -- '{1}'" -f $remoteCmd, $Pattern
    }

    # 다른 명령으로 넘길 때(rt x -o | sls fail)는 색을 입히지 않고 문자열만 흘려보낸다.
    $piped = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength

    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"

    if (-not $piped) {
        $note = if ($Once) { "최근 {0}줄" -f $Lines } else { "최근 {0}줄 + 따라가기 · Ctrl+C 종료" -f $Lines }
        if ($Pattern) { $note = "{0} · 필터 '{1}'" -f $note, $Pattern }

        Write-Host ("{0}tail:$esc[0m {1}{2}:{3}$esc[0m  {0}({4}:{5})$esc[0m" -f $sub, $head, $global:SV, $resolved, $global:SVIP, $global:SVPORT)
        Write-Host ("  {0}{1}$esc[0m" -f $sub, $note)
    }

    # 한글 로그가 깨지지 않게 받는 동안만 UTF-8로 바꾼다.
    $prevEncoding = [Console]::OutputEncoding

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

        # 로그가 쏟아질 때는 Write-Host가 병목이라(초당 8천 줄 수준) 콘솔에 직접 쓴다 - 6배 이상 빠르다.
        # 인코딩을 바꾸면 [Console]::Out이 다시 만들어지므로 바꾼 뒤에 잡고, 줄마다 바로 내보내 실시간성은 유지한다.
        $writer = [Console]::Out

        & ssh -o BatchMode=yes -o ConnectTimeout=5 -o RemoteCommand=none -o RequestTTY=no -p $global:SVPORT $global:SV $remoteCmd 2>&1 |
            ForEach-Object {
                if ($piped) { [string]$_ } else { $writer.WriteLine((Format-RemoteLogLine -Line ([string]$_))) }
            }

        $writer.Flush()
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }
}

# up/dn/rr/rl 원격 경로 자동완성 공용: Tab을 누를 때마다 ssh로 원격 디렉터리 목록을 조회한다. (캐시 없음)
function Get-SshRemotePathCompletion {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostAlias,

        [Parameter(Mandatory = $true)]
        [string]$Port,

        [string]$WordToComplete = '',

        [switch]$DirOnly,

        # $SVDIR 같은 기준 디렉터리 — 상대 경로 후보를 이 아래에서 찾는다.
        [string]$BaseDir = ''
    )

    $word = $WordToComplete.Trim("'`"")

    # 입력값을 "디렉터리 부분 + 이름 접두어"로 분리
    $slash = $word.LastIndexOf('/')
    $dir = if ($slash -ge 0) { $word.Substring(0, $slash + 1) } else { '' }
    $prefix = if ($slash -ge 0) { $word.Substring($slash + 1) } else { $word }

    # 기준 디렉터리($SVDIR)가 있고 입력이 /나 ~로 시작하지 않으면 그 아래에서 찾는다.
    # (완성 결과는 상대 경로 그대로 돌려줘야 up/dn이 다시 $SVDIR 기준으로 해석한다)
    $base = ''
    if (-not [string]::IsNullOrWhiteSpace($BaseDir) -and
        -not $word.StartsWith('/') -and -not $word.StartsWith('~')) {
        $base = $BaseDir.TrimEnd('/') + '/'
    }

    # 기준 디렉터리도 입력도 없으면 원격 홈, ~/ 시작이면 원격 $HOME으로 치환해서 조회한다.
    # ($HOME은 원격 셸에서 확장되어야 하므로 PS에서는 리터럴로 유지)
    if ([string]::IsNullOrEmpty($dir) -and [string]::IsNullOrEmpty($base)) {
        $remoteCmd = 'ls -1ap'
    }
    elseif ($dir.StartsWith('~/')) {
        $remoteCmd = 'ls -1ap -- "$HOME/' + $dir.Substring(2) + '"'
    }
    else {
        $remoteCmd = 'ls -1ap -- "' + $base + $dir + '"'
    }

    # config의 Host * 에 RemoteCommand(로그인 셸 유지용)가 걸려 있어도 명령 실행이 되도록 무효화한다.
    # 원격(리눅스) ls는 UTF-8인데 한국어 Windows 콘솔 기본 인코딩(CP949)으로 캡처하면 한글 파일명이
    # 깨지므로, 조회하는 동안만 콘솔 인코딩을 UTF-8로 바꾸고 끝나면 원래대로 복원한다.
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $items = & ssh -o BatchMode=yes -o ConnectTimeout=3 -o RemoteCommand=none -o RequestTTY=no -p $Port $HostAlias "$remoteCmd 2>/dev/null" 2>$null
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }

    if ($LASTEXITCODE -ne 0 -or -not $items) {
        return
    }

    foreach ($item in $items) {
        if ($item -in './', '../') { continue }
        if ($DirOnly -and -not $item.EndsWith('/')) { continue }
        if ($prefix -and -not $item.StartsWith($prefix, [System.StringComparison]::Ordinal)) { continue }

        # ls -p 덕분에 디렉터리는 끝에 / 가 붙어 이어서 탐색할 수 있다.
        $full = "$dir$item"
        $completionText = if ($full -match '\s') { "'$full'" } else { $full }

        [System.Management.Automation.CompletionResult]::new(
            $completionText,
            $item,
            [System.Management.Automation.CompletionResultType]::ProviderItem,
            $full
        )
    }
}

# up은 업로드 대상이므로 디렉터리만, dn은 파일/디렉터리 모두 후보로 보여준다.
Register-ArgumentCompleter -CommandName up, dn -ParameterName RemotePath -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $sv = Get-Variable SV -Scope Global -ErrorAction SilentlyContinue
    $svport = Get-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue

    if (-not $sv -or [string]::IsNullOrWhiteSpace([string]$sv.Value) -or
        -not $svport -or [string]::IsNullOrWhiteSpace([string]$svport.Value)) {
        return
    }

    Get-SshRemotePathCompletion -HostAlias $sv.Value -Port ([string]$svport.Value) -WordToComplete $wordToComplete `
        -DirOnly:($commandName -eq 'up') -BaseDir ([string]$global:SVDIR)
}

# rr 첫 인자(원본)는 SV 기준 파일+디렉터리, 둘째 인자(대상)는 DST 기준 디렉터리만 보여준다.
Register-ArgumentCompleter -CommandName rr -ParameterName SourcePath -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $sv = Get-Variable SV -Scope Global -ErrorAction SilentlyContinue
    $svport = Get-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue

    if (-not $sv -or [string]::IsNullOrWhiteSpace([string]$sv.Value) -or
        -not $svport -or [string]::IsNullOrWhiteSpace([string]$svport.Value)) {
        return
    }

    Get-SshRemotePathCompletion -HostAlias $sv.Value -Port ([string]$svport.Value) -WordToComplete $wordToComplete -BaseDir ([string]$global:SVDIR)
}

# sw는 기준 디렉터리 자체를 고르는 명령이라 $SVDIR을 적용하지 않고 원격 홈/절대경로에서 찾는다.
Register-ArgumentCompleter -CommandName sw, set-svdir -ParameterName Path -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $sv = Get-Variable SV -Scope Global -ErrorAction SilentlyContinue
    $svport = Get-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue

    if (-not $sv -or [string]::IsNullOrWhiteSpace([string]$sv.Value) -or
        -not $svport -or [string]::IsNullOrWhiteSpace([string]$svport.Value)) {
        return
    }

    Get-SshRemotePathCompletion -HostAlias $sv.Value -Port ([string]$svport.Value) -WordToComplete $wordToComplete -DirOnly
}

Register-ArgumentCompleter -CommandName rr -ParameterName DestPath -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $dst = Get-Variable DST -Scope Global -ErrorAction SilentlyContinue
    $dstport = Get-Variable DSTPORT -Scope Global -ErrorAction SilentlyContinue

    if (-not $dst -or [string]::IsNullOrWhiteSpace([string]$dst.Value) -or
        -not $dstport -or [string]::IsNullOrWhiteSpace([string]$dstport.Value)) {
        return
    }

    Get-SshRemotePathCompletion -HostAlias $dst.Value -Port ([string]$dstport.Value) -WordToComplete $wordToComplete -DirOnly
}

# rl은 ls 옵션을 살리려고 $args로 받으므로 매개변수 이름이 없어 Native 완성기로 등록한다.
# SV 기준 파일+디렉터리 후보를 보여주고, -로 시작하는 단어(ls 옵션)는 완성하지 않는다.
Register-ArgumentCompleter -Native -CommandName rl -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete.StartsWith('-')) { return }

    $sv = Get-Variable SV -Scope Global -ErrorAction SilentlyContinue
    $svport = Get-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue

    if (-not $sv -or [string]::IsNullOrWhiteSpace([string]$sv.Value) -or
        -not $svport -or [string]::IsNullOrWhiteSpace([string]$svport.Value)) {
        return
    }

    Get-SshRemotePathCompletion -HostAlias $sv.Value -Port ([string]$svport.Value) -WordToComplete $wordToComplete -BaseDir ([string]$global:SVDIR)
}

# rt는 로그 파일 하나를 따라가는 명령이라 SV 기준 파일+디렉터리를 후보로 보여준다.
Register-ArgumentCompleter -CommandName rt -ParameterName Path -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $sv = Get-Variable SV -Scope Global -ErrorAction SilentlyContinue
    $svport = Get-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue

    if (-not $sv -or [string]::IsNullOrWhiteSpace([string]$sv.Value) -or
        -not $svport -or [string]::IsNullOrWhiteSpace([string]$svport.Value)) {
        return
    }

    Get-SshRemotePathCompletion -HostAlias $sv.Value -Port ([string]$svport.Value) -WordToComplete $wordToComplete -BaseDir ([string]$global:SVDIR)
}

#########################################################
# SCP 파일 전송 / 원격 조회 (up/dn/rr/rl/rt/rs) 영역 End
#########################################################


#########################################################
# ssh 원격 관리 도움말 영역 Start
#########################################################
# 위 SSH/SCP 영역의 원격 명령(ss/sd/sb/xs/xd/c/auth/p/pt/rs/rb/sw/xw/rl/rt/up/dn/rr)을 사용 흐름 순서로 정리한 가이드.
# 원격 명령을 고치면 이 설명도 함께 갱신할 것. (구 ssh-help.ps1에서 프로필로 병합)

function Add-HelpHighlight {
    # fnc-ignore
    # 검색어와 일치하는 부분만 반전 표시로 감싼다. 색상 코드(ESC[..m) 안은 건드리지 않는다. (Show-HelpPager 전용)
    param([string]$Text, [string]$Term)

    if ([string]::IsNullOrEmpty($Term)) { return $Text }

    $esc = [char]27
    $pattern = "$esc\[[0-9;]*[A-Za-z]"

    # 색상 코드를 구분자로 쪼갠 뒤(캡처해서 그대로 유지) 본문 조각에서만 검색어를 강조한다.
    $parts = [regex]::Split($Text, "($pattern)")

    $result = foreach ($part in $parts) {
        if ($part -match "^$pattern$") {
            $part
        }
        else {
            [regex]::Replace($part, [regex]::Escape($Term), { param($m) "$esc[7m$($m.Value)$esc[27m" }, 'IgnoreCase')
        }
    }

    -join $result
}

function Show-HelpPager {
    # fnc-ignore
    # 대체 스크린 버퍼에 내용을 띄우고 스크롤 / 검색한다 (/ 검색, n·N 다음·이전 일치).
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$StatusHint = '↑↓ 스크롤 | / 검색 · n/N 이동 | ESC/q 닫기'
    )

    $esc = [char]27
    $prevCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true
    [Console]::Write("$esc[?1049h$esc[?25l")

    # 검색은 색상 코드를 걷어낸 본문으로 한다 (색 때문에 글자가 끊겨 보이지 않도록).
    $plain = @($Lines | ForEach-Object { $_ -replace "$esc\[[0-9;]*[A-Za-z]", '' })

    $term = ''      # 현재 검색어
    $hits = @()     # 검색어가 있는 줄 번호
    $hitIndex = -1  # 지금 보고 있는 일치 순번
    $notice = ''    # 상태줄에 한 번만 띄울 안내

    try {
        $top = 0
        while ($true) {
            $height = [Console]::WindowHeight - 1   # 마지막 줄은 상태 표시줄
            $maxTop = [Math]::Max(0, $Lines.Count - $height)
            if ($top -gt $maxTop) { $top = $maxTop }

            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append("$esc[H")
            for ($i = 0; $i -lt $height; $i++) {
                $idx = $top + $i
                if ($idx -lt $Lines.Count) {
                    [void]$sb.Append((Add-HelpHighlight -Text $Lines[$idx] -Term $term))
                }
                [void]$sb.Append("$esc[K`n")
            }

            $shownTo = [Math]::Min($top + $height, $Lines.Count)
            $status = if ($notice) { $notice }
                elseif ($term) { "{0}  [검색: {1} - {2}/{3}]" -f $StatusHint, $term, ($hitIndex + 1), $hits.Count }
                else { $StatusHint }

            # 상태줄이 화면보다 길면 줄이 밀리므로 폭에 맞춰 자른다.
            $statusText = " {0}  ({1}-{2}/{3}줄) " -f $status, ($top + 1), $shownTo, $Lines.Count
            $limit = [Math]::Max(10, [Console]::WindowWidth - 1)
            if ($statusText.Length -gt $limit) { $statusText = $statusText.Substring(0, $limit) }

            [void]$sb.Append(("$esc[7m{0}$esc[0m$esc[K" -f $statusText))
            [Console]::Write($sb.ToString())

            $key = [Console]::ReadKey($true)
            $notice = ''

            if ($key.Key -eq [ConsoleKey]::C -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                return
            }

            # 검색어 입력은 Read-Host로 받는다 (한글 IME 입력이 그대로 들어온다).
            if ($key.KeyChar -eq '/') {
                [Console]::Write(("$esc[{0};1H$esc[K$esc[?25h" -f ($height + 1)))
                [Console]::TreatControlCAsInput = $false
                $typed = Read-Host '검색'
                [Console]::TreatControlCAsInput = $true
                [Console]::Write("$esc[?25l")

                $term = ([string]$typed).Trim()
                $hits = @()
                $hitIndex = -1

                if ($term) {
                    $hits = @(for ($i = 0; $i -lt $plain.Count; $i++) {
                        if ($plain[$i].IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $i }
                    })

                    if ($hits.Count -eq 0) {
                        $notice = "일치하는 내용이 없습니다: $term"
                        $term = ''
                    }
                    else {
                        # 지금 보이는 위치 이후의 첫 일치부터 보여준다.
                        $hitIndex = [array]::FindIndex([int[]]$hits, [Predicate[int]] { param($h) $h -ge $top })
                        if ($hitIndex -lt 0) { $hitIndex = 0 }
                        $top = [Math]::Max(0, [Math]::Min($hits[$hitIndex] - 2, $maxTop))
                    }
                }

                continue
            }

            # n = 다음 일치, N = 이전 일치 (목록 끝에서 처음으로 돌아간다)
            if ($key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
                if ($hits.Count -eq 0) {
                    $notice = '검색어가 없습니다 (/ 로 검색)'
                }
                else {
                    $step = if ($key.KeyChar -ceq 'N') { -1 } else { 1 }
                    $hitIndex = ((($hitIndex + $step) % $hits.Count) + $hits.Count) % $hits.Count
                    $top = [Math]::Max(0, [Math]::Min($hits[$hitIndex] - 2, $maxTop))
                }

                continue
            }

            switch ($key.Key) {
                ([ConsoleKey]::UpArrow)   { if ($top -gt 0) { $top-- } }
                ([ConsoleKey]::DownArrow) { if ($top -lt $maxTop) { $top++ } }
                ([ConsoleKey]::K)         { if ($top -gt 0) { $top-- } }
                ([ConsoleKey]::J)         { if ($top -lt $maxTop) { $top++ } }
                ([ConsoleKey]::PageUp)    { $top = [Math]::Max(0, $top - $height) }
                ([ConsoleKey]::PageDown)  { $top = [Math]::Min($maxTop, $top + $height) }
                ([ConsoleKey]::Spacebar)  { $top = [Math]::Min($maxTop, $top + $height) }
                ([ConsoleKey]::Home)      { $top = 0 }
                ([ConsoleKey]::End)       { $top = $maxTop }
                ([ConsoleKey]::Escape)    { return }
                ([ConsoleKey]::Q)         { return }
            }
        }
    }
    finally {
        # 원래 화면으로 복귀 (이전 출력/히스토리는 그대로 유지된다)
        [Console]::Write("$esc[?1049l$esc[?25h")
        [Console]::TreatControlCAsInput = $prevCtrlC
    }
}

function ssh-help {
    # 원격 서버 선택/접속/파일 전송 명령 가이드를 새 화면에 표시한다. (↑↓/PgUp/PgDn 스크롤, / 검색·n/N 이동, ESC/q/Ctrl+C 닫기)
    $esc = [char]27
    $cmdWidth = 22

    $lines = [System.Collections.Generic.List[string]]::new()

    function Add-Title {
        # fnc-ignore
        param([string]$Text)
        $lines.Add('')
        $lines.Add("$esc[93m$Text$esc[0m")
    }

    function Add-Section {
        # fnc-ignore
        param([string]$Title)
        $lines.Add('')
        $lines.Add("$esc[36m  --- $Title ---$esc[0m")
    }

    function Get-DisplayWidth {
        # fnc-ignore
        # 한글 등 전각 문자는 터미널에서 두 칸을 차지하므로 PadRight(글자 수) 대신 이 폭으로 맞춘다.
        param([string]$Text)
        $width = 0
        foreach ($ch in $Text.ToCharArray()) {
            $code = [int]$ch
            if (($code -ge 0x1100 -and $code -le 0x115F) -or
                ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
                ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE30 -and $code -le 0xFE6F) -or
                ($code -ge 0xFF00 -and $code -le 0xFF60) -or
                ($code -ge 0xFFE0 -and $code -le 0xFFE6)) {
                $width += 2
            }
            else {
                $width += 1
            }
        }
        $width
    }

    function Add-Cmd {
        # fnc-ignore
        param([string]$Cmd, [string]$Desc)
        $pad = [Math]::Max(1, $cmdWidth - (Get-DisplayWidth $Cmd))
        $lines.Add(("  $esc[92m{0}$esc[0m{1}{2}" -f $Cmd, (' ' * $pad), $Desc))
    }

    function Add-Note {
        # fnc-ignore
        param([string]$Text)
        $lines.Add(("  {0}$esc[96m{1}$esc[0m" -f (' ' * $cmdWidth), $Text))
    }

    function Add-Plain {
        # fnc-ignore
        param([string]$Text = '')
        $lines.Add($Text)
    }

    # ── 전체 흐름 ────────────────────────────────────────────────
    Add-Title "[ 전체 흐름 ]"
    Add-Plain "  $esc[92mss$esc[0m 서버 선택  ->  $esc[92mc$esc[0m 접속 / $esc[92msw$esc[0m 원격 경로 고정  ->  $esc[92mrl$esc[0m 목록 확인 / $esc[92mup dn$esc[0m 파일 전송"
    Add-Plain "  서버간 전송은 $esc[92msd$esc[0m 로 대상까지 고른 뒤 $esc[92mrr$esc[0m."
    Add-Plain "  상태 점검은 $esc[92mp$esc[0m ping -> $esc[92mpt$esc[0m 포트 -> $esc[92mrs$esc[0m 요약, 로그는 $esc[92mrt$esc[0m, 재부팅 감시는 $esc[92mrb$esc[0m."
    Add-Plain ""
    Add-Plain "  선택 상태는 프롬프트 윗줄에 표시된다 - SV | ID | IP | PORT | DIR (DST는 아래 줄)."

    # ── 1. 서버 선택 ─────────────────────────────────────────────
    Add-Title "[ 1. 서버 선택 ]"
    Add-Section "명령"
    Add-Cmd "ss [별칭]"        "작업 서버(SV) 선택. 인자 없으면 목록에서 방향키로 고른다"
    Add-Note "Tab: ssh config의 Host 별칭 자동완성"
    Add-Cmd "sd [별칭]"        "전송 대상(DST) 선택 - rr 전용이며 up/dn/rl과는 무관"
    Add-Cmd "sb <SV> <DST>"    "SV와 DST를 한 번에 선택 (= ss + sd, 두 인자 모두 Tab 자동완성)"
    Add-Cmd "xs"               "SV 해제 (원격 작업 디렉터리 SVDIR도 함께 해제)"
    Add-Cmd "xd"               "DST 해제"
    Add-Cmd "ssh-config"       "ssh config 파일을 편집기로 연다"

    Add-Section "설정되는 변수"
    Add-Cmd "`$SV  `$SVID"      "선택한 Host 별칭 / 접속 계정 (ssh -G의 User)"
    Add-Cmd "`$SVIP  `$SVPORT"  "실제 IP / 포트 - IP는 선택하는 시점에 1회만 조회한다"
    Add-Cmd "`$DST 계열"        "DST용 동일 구성 (`$DST/`$DSTID/`$DSTIP/`$DSTPORT)"
    Add-Note "SV와 DST는 서로 독립 - 한쪽을 바꿔도 다른 쪽은 유지된다"
    Add-Note "ss로 서버를 새로 고르면 이전 서버 기준의 SVDIR은 자동 해제된다"

    # ── 2. 접속 ──────────────────────────────────────────────────
    Add-Title "[ 2. 접속 / 세션 ]"
    Add-Cmd "c"                "선택된 SV로 ssh 접속 (= ssh-con, 시스템 ssh 사용)"
    Add-Note "뒤에 붙인 인자는 그대로 ssh로 전달된다 (예: c -L 8080:localhost:80)"
    Add-Cmd "auth [대상] [포트]" "공개키를 등록해 비밀번호 없이 접속하게 만든다"
    Add-Note "인자 없이 auth = 선택된 SV 대상. 사용법은 auth -h"
    Add-Note "예: auth user@10.0.0.5 2222  /  auth myhost (config 별칭은 포트 자동)"
    Add-Note "IP 재사용 등으로 호스트 키가 바뀐 서버는 known_hosts 항목을 자동 정리한 뒤 등록한다"
    Add-Cmd "keep-title [대상]" "원격 bash가 탭 이름을 덮어쓰지 않게 ~/.bashrc를 설정 (서버마다 한 번)"
    Add-Note "접속하면 프롬프트가 탭 제목을 바꿔 쓰는데, 그걸 막아 tb로 지정한 이름이 유지된다"
    Add-Note "bash 전용. 고치기 전에 원격 ~/.bashrc를 백업하고, 적용 후 새 셸에서 실제로 사라졌는지 확인한다 (제거: keep-title -r)"
    Add-Cmd "p [대상]"         "ping 상태 감시 (= ping-watch, 대상을 생략하면 SVIP)"
    Add-Note "한 줄에서 갱신되고 상태가 바뀔 때만 기록이 남는다 (재부팅 확인용)"
    Add-Note "대상에 IP나 호스트명을 직접 줄 수 있다. -i 간격(초) -c 횟수, 종료는 Ctrl+C"
    Add-Cmd "ping-test"        "선택된 SVIP로 계속 ping (출력이 쌓이는 예전 방식)"
    Add-Cmd "pt [대상] [포트]"  "TCP 포트가 열렸는지 확인 - 열림/닫힘/무응답을 구분한다"
    Add-Note "대상·포트를 생략하면 SVIP와 SVPORT+22/80/443. pt 8080 처럼 포트만 줘도 된다"
    Add-Note "pt 22,80,443 (쉼표) / pt 8000-8010 (범위, 한 번에 64개까지) / -t 타임아웃(ms)"
    Add-Note "ping은 되는데 접속이 안 될 때 sshd가 떴는지 여기서 먼저 확인한다"
    Add-Cmd "rs"               "SV 상태 요약 - 가동시간·부하·메모리·디스크·상위 프로세스·접속자"
    Add-Note "/proc과 기본 명령만 쓰므로 갓 설치한 서버에서도 그대로 동작한다 (-n 프로세스 줄수)"
    Add-Cmd "rb"               "재부팅 감시 - SV가 내려갔다 올라오는 과정을 한 줄에서 지켜본다"
    Add-Note "다운 확인 -> 응답 재개 -> ssh 포트 열림 -> 로그인 확인 순서로 단계마다 기록을 남긴다"
    Add-Note "원격 셸에서 reboot을 친 뒤 빠져나와 실행한다 - 재부팅 명령을 보내지는 않는다"
    Add-Note "이미 내려간 뒤에 실행하면 복구만 지켜본다. -c 복구되면 바로 접속, -w 단계별 최대 대기(분, 기본 10)"
    Add-Cmd "d [-r|-l|-u|-d|-g]" "현재 세션을 화면 분할로 복제 (= dup, 기본 -r 우측)"
    Add-Note "-g: 2x2 4분할 (세로 분할 후 양쪽을 가로 분할, 포커스는 원래 pane)"
    Add-Note "새 pane이 SV/DST/SVDIR 선택 상태를 그대로 이어받는다"
    Add-Cmd "ws"               "열린 탭/분할과 각 pane의 SV·경로를 저장했다가 그대로 다시 연다"
    Add-Note "ws (목록) / ws save <이름> [-m 메모] / ws show <이름> / ws load <이름> [-here] / ws rm <이름> / ws rename"
    Add-Note "저장은 새 탭에서 실행한다 - 그 탭은 스냅샷에서 빠진다. 탭 순서·분할 모양·분할 비율까지 복원된다"
    Add-Note "각 pane은 프로필을 읽을 때 감시기를 건다 - 프로필을 바꾼 뒤 기존 pane은 . $PROFILE 을 한 번 실행해야 저장 대상이 된다"
    Add-Note "명령 실행 중인 pane은 상태를 답할 수 없어 어느 pane인지 알려준다 (Ctrl+C로 멈춘 뒤 다시 저장, -f면 구조만 저장)"
    Add-Note "복원하면 SV/DST/SVDIR·작업 경로·제목·탭 색이 돌아오고, 실행 중이던 명령은 히스토리에 들어간다(위 화살표)"
    Add-Cmd "rsa-pubkey"       "로컬 공개키(id_rsa.pub) 내용을 출력한다"

    # ── 3. 원격 작업 디렉터리 ────────────────────────────────────
    Add-Title "[ 3. 원격 작업 디렉터리 (SVDIR) / 목록 조회 ]"
    Add-Plain "  매번 긴 원격 경로를 치지 않도록 기준 디렉터리를 세션에 고정한다."
    Add-Section "명령"
    Add-Cmd "sw <원격경로>"    "기준 디렉터리 지정 (원격에 실제로 있는지 확인한 뒤 설정)"
    Add-Note "Tab: 원격 디렉터리 자동완성 (원격 홈 또는 절대경로 기준)"
    Add-Cmd "sw"               "현재 설정값 확인"
    Add-Cmd "xw"               "해제 (기준이 다시 원격 홈으로 돌아간다)"

    Add-Section "목록 조회"
    Add-Cmd "rl [경로] [옵션]"  "SV의 원격 목록 (경로를 생략하면 SVDIR, 숨김 파일 항상 포함)"
    Add-Note "기본은 색상 짧은 목록(여러 열), rl -l 이면 상세 목록"
    Add-Note "아이콘·색은 짧은 목록과 상세 목록 모두 이 PC에서 입힌다 (서버에는 설치할 것이 없다)"
    Add-Note "Tab: SVDIR 안의 파일/디렉터리 후보"
    Add-Note "- 로 시작하는 인자는 ls 옵션: rl logs -t (최신순), rl -S (크기순)"
    Add-Note "rl '*.log' 처럼 와일드카드도 가능 (서버 셸이 펼친다)"

    Add-Section "로그 보기"
    Add-Cmd "rt <로그경로>"     "원격 로그를 실시간으로 따라 본다 (tail -F, 종료 Ctrl+C)"
    Add-Note "ERROR/FATAL 빨강, WARN 노랑, DEBUG/TRACE 흐리게, INFO/NOTICE는 수준 표시만 흐리게"
    Add-Note "줄 맨 앞(또는 시각 뒤)의 수준 표시를 먼저 본다 - Info 줄이 본문의 error 때문에 빨개지지 않는다"
    Add-Note "수준 표시가 없는 줄은 낱말(error/fail/denied 등)로 판단하고, 맨 앞 시각은 흐리게 - 색은 모두 이 PC에서 입힌다"
    Add-Note "-n 처음 보여줄 줄수(기본 50) / -p 패턴 필터(대소문자 무시) / -o 따라가지 않고 한 번만"
    Add-Note "Tab: SVDIR 기준 자동완성. 권한이 필요한 로그는 접속 계정에 읽기 권한이 있어야 한다"

    Add-Section "경로 해석 규칙"
    Add-Cmd "test.txt"         "상대 경로 -> SVDIR 기준 (SVDIR이 없으면 원격 홈)"
    Add-Cmd "sub/a.log"        "하위 경로도 동일"
    Add-Cmd "/var/log/a.log"   "/ 로 시작하면 SVDIR을 벗어난다"
    Add-Cmd "~/a.log"          "~ 로 시작하면 원격 홈 기준 - 역시 SVDIR 무시"
    Add-Note "up / dn / rr(1번째 인자) / rl과 자동완성 모두 같은 규칙을 따른다"

    # ── 4. 파일 전송 ─────────────────────────────────────────────
    Add-Title "[ 4. 파일 전송 ]"
    Add-Cmd "up <로컬> [원격]"  "로컬 -> SV. 원격 경로를 생략하면 SVDIR로 올린다"
    Add-Note "Tab(2번째 인자): 원격 디렉터리만 후보로 표시"
    Add-Cmd "dn <원격>"        "SV -> 로컬 ~/Downloads"
    Add-Note "Tab: SVDIR 안의 파일/디렉터리 후보"
    Add-Cmd "rr <원본> [대상]"  "SV -> DST 서버간 전송 (로컬을 거치는 scp -3)"
    Add-Note "대상을 생략하면 DST의 홈(~/). SV와 DST가 모두 선택돼 있어야 한다"
    Add-Note "Tab: 1번째 인자는 SV 경로, 2번째 인자는 DST 디렉터리"

    Add-Section "공통 동작"
    Add-Cmd "디렉터리"          "원격 경로가 디렉터리면 자동으로 -r (재귀 전송)"
    Add-Cmd "와일드카드"        "up *.tar, dn '*.log' 처럼 여러 파일을 한 번에"
    Add-Note "원격 와일드카드는 서버 셸이 펼치므로 따옴표로 감싸는 편이 안전하다"
    Add-Cmd "포트"             "config 별칭이 포트를 공급하므로 따로 지정할 필요 없다"

    # ── 5. 사용 예시 ─────────────────────────────────────────────
    Add-Title "[ 5. 사용 예시 ]"
    Add-Section "로그 한 개 받아오기"
    Add-Plain "    ss myhost           # 서버 선택"
    Add-Plain "    sw /var/log         # 기준 경로 고정"
    Add-Plain "    rl -t               # /var/log 목록을 최신순으로 확인"
    Add-Plain "    dn mes<Tab>         # /var/log 안에서 자동완성 -> dn messages"
    Add-Section "패치 파일 올리고 확인하기"
    Add-Plain "    up patch.tar        # sw로 잡아둔 경로로 업로드"
    Add-Plain "    c                   # 같은 서버에 접속해 확인"
    Add-Section "서버에서 서버로 옮기기"
    Add-Plain "    ss srchost          # 원본 서버"
    Add-Plain "    sd dsthost          # 대상 서버"
    Add-Plain "    sb srchost dsthost  # 위 두 줄을 한 번에"
    Add-Plain "    rr backup.tar ~/    # 원본:backup.tar -> 대상:~/"

    Add-Section "재부팅 점검"
    Add-Plain "    ss myhost           # 서버 선택"
    Add-Plain "    c                   # 접속해서 reboot 실행 -> 연결이 끊기면 빠져나온다"
    Add-Plain "    rb                  # 다운 -> 복구를 한 줄로 지켜본다"
    Add-Plain "    pt                  # 서비스 포트까지 확인"
    Add-Plain "    rs                  # 올라온 서버 상태 요약"
    Add-Section "장애 로그 확인"
    Add-Plain "    rt /var/log/messages -p error   # error 줄만 실시간으로"

    # ── 6. 문제 해결 ─────────────────────────────────────────────
    Add-Title "[ 6. 자주 겪는 문제 ]"
    Add-Cmd "자동완성이 로컬 경로" "SV 미선택이거나 키 인증이 안 된 상태 - ss 후 auth 실행"
    Add-Cmd "변수 미설정 안내"    "up/dn/rl은 ss가, rr은 ss + sd가 모두 필요하다"
    Add-Cmd "호스트 키 경고"     "REMOTE HOST IDENTIFICATION HAS CHANGED - auth가 자동 정리한다"
    Add-Note "수동으로 지우려면 del-host <IP> (known_hosts 자동 백업 후 해당 항목 삭제)"
    Add-Cmd "ping 되는데 접속 불가" "pt로 포트 확인 - sshd 기동 전이면 잠시 후 다시 시도"
    Add-Cmd "rb가 안 끝날 때"    "다운을 못 잡으면 재부팅 전이거나 ping이 막힌 경우 - pt로 포트 확인"
    Add-Cmd "전체 명령 목록"     "fnc (함수 목록) / fnc-alias (alias 목록)"

    Add-Plain ""
    Show-HelpPager -Lines $lines
}

#########################################################
# ssh 원격 관리 도움말 영역 End
#########################################################


#########################################################
# 터미널 세션 복제 (dup) 영역 Start
#########################################################

function dup # 현재 세션($SV, 작업 경로)을 복제해 화면 분할 (-r 우측 | -l 좌측 | -u 상단 | -d 하단 | -g 4분할, 기본 -r)
{
    param(
        [Alias('r')][switch]$Right,
        [Alias('l')][switch]$Left,
        [Alias('u')][switch]$Up,
        [Alias('d')][switch]$Down,
        [Alias('g')][switch]$Grid
    )

    if (@($Right, $Left, $Up, $Down, $Grid).Where({ $_ }).Count -gt 1) {
        Write-Host "사용법: dup [-r|-l|-u|-d|-g]  (하나만, 생략하면 -r 우측, -g는 2x2 4분할)" -ForegroundColor Yellow
        return
    }

    if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
        Write-Error "wt(Windows Terminal)를 찾을 수 없습니다. Windows Terminal 설치를 확인해 주세요."
        return
    }
    if (-not $env:WT_SESSION) {
        Write-Host "Windows Terminal 안에서 실행할 때만 분할할 수 있습니다." -ForegroundColor Yellow
        return
    }

    # wt가 띄우는 새 pane은 현재 쉘의 변수/환경을 물려받지 않으므로,
    # 세션 상태를 임시 스크립트에 담아 새 pane이 프로필 로드 후 실행하게 한다.
    # (프로필에 정의된 alias/function은 새 pane이 프로필을 읽으면서 자동 적용된다)
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($name in 'SV', 'SVID', 'SVIP', 'SVDIR', 'DST', 'DSTID', 'DSTIP') {
        $var = Get-Variable $name -Scope Global -ErrorAction SilentlyContinue
        if ($var -and $null -ne $var.Value) {
            $lines.Add(("`$global:{0} = '{1}'" -f $name, ([string]$var.Value -replace "'", "''")))
        }
    }
    foreach ($name in 'SVPORT', 'DSTPORT') {
        $port = Get-Variable $name -Scope Global -ErrorAction SilentlyContinue
        if ($port -and $null -ne $port.Value) {
            $lines.Add(("`$global:{0} = {1}" -f $name, [int]$port.Value))
        }
    }
    foreach ($name in 'OMP_SV', 'OMP_SVID', 'OMP_SVIP', 'OMP_SVPORT', 'OMP_SVDIR', 'OMP_DST', 'OMP_DSTID', 'OMP_DSTIP', 'OMP_DSTPORT', 'OMP_TITLE', 'OMP_TABCOLOR') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) {
            $lines.Add(("`$env:{0} = '{1}'" -f $name, ($value -replace "'", "''")))
        }
    }
    # 탭은 활성 pane의 제목/색을 따르므로 새 pane에도 같은 탭 색을 적용한다 (제목은 omp가 OMP_TITLE로 쓴다).
    if ($env:OMP_TABCOLOR) {
        $lines.Add('Write-TabColorSequence $env:OMP_TABCOLOR')
    }
    if ($global:SV) {
        $lines.Add(("Write-Host 'dup: `$SV={0} 세션을 복제했습니다.' -ForegroundColor DarkCyan" -f ([string]$global:SV -replace "'", "''")))
    }
    $lines.Add('Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue')

    # 새 pane마다 init 스크립트를 실행한 뒤 스스로 지우므로, 만들 pane 수만큼 사본을 둔다.
    $paneCount = if ($Grid) { 3 } else { 1 }
    $initPaths = @(for ($i = 0; $i -lt $paneCount; $i++) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ("dup_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $path -Value $lines -Encoding utf8BOM
        $path
    })

    # 새 pane은 현재와 같은 쉘 실행 파일, 같은 작업 경로로 시작한다.
    $cwd = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath } else { $HOME }
    $shell = (Get-Process -Id $PID).Path

    if ($Grid) {
        # 4분할(2x2): 세로 분할로 우측 pane을 만들고 그 pane을 가로 분할한 뒤,
        # 좌측(원래 pane)으로 포커스를 옮겨 가로 분할한다. 새 pane이 포커스를 가져가므로 마지막에 원래 pane(좌상단)으로 돌아온다.
        $wtArgs = @(
            'split-pane', '-V', '-d', $cwd, $shell, '-NoExit', '-File', $initPaths[0], ';',
            'split-pane', '-H', '-d', $cwd, $shell, '-NoExit', '-File', $initPaths[1], ';',
            'move-focus', 'left', ';',
            'split-pane', '-H', '-d', $cwd, $shell, '-NoExit', '-File', $initPaths[2], ';',
            'move-focus', 'up'
        )
    }
    else {
        # wt split-pane은 새 pane을 우측(-V)/하단(-H)에만 만들 수 있으므로,
        # 좌측/상단은 분할 직후 swap-pane으로 기존 pane과 자리를 맞바꿔 구현한다.
        $splitDir = if ($Up -or $Down) { '-H' } else { '-V' }
        $wtArgs = @('split-pane', $splitDir, '-d', $cwd, $shell, '-NoExit', '-File', $initPaths[0])
        if ($Left) { $wtArgs += ';', 'swap-pane', 'left' }
        elseif ($Up) { $wtArgs += ';', 'swap-pane', 'up' }
    }

    & wt -w 0 @wtArgs
    if ($LASTEXITCODE -ne 0) {
        $initPaths | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
        Write-Error ("pane 분할에 실패했습니다 (exit code: {0})" -f $LASTEXITCODE)
    }
}

function d {
    # alias-fn: 현재 세션을 복제해 화면 분할한다. (= dup, -r/-l/-u/-d/-g 인자 그대로 전달)
    dup @args
}

#########################################################
# 터미널 세션 복제 (dup) 영역 End
#########################################################


#########################################################
# 터미널 탭 제목 / 색상 (tt/tc/tb) 영역 Start
#########################################################
# WT 탭은 활성 pane의 제목과 탭 색을 따른다.
# - 제목: OSC 2. WT pwsh 프로필들에 suppressApplicationTitle=false가 필요하고,
#   oh-my-posh가 프롬프트마다 console_title_template({{ .Env.OMP_TITLE }})로 다시 쓰므로 상태는 $env:OMP_TITLE에 둔다.
#   빈 제목을 보내면 WT가 프로필 이름으로 되돌린다.
# - 탭 색: WT 팔레트 264번(FRAME_BACKGROUND)이 탭 배경색이라 OSC 4로 RGB를 넣고 OSC 104로 되돌린다.
#   --tabColor로 연 탭이나 탭 우클릭으로 색을 고른 탭은 WT가 그 색을 우선한다. 상태는 $env:OMP_TABCOLOR.
# 두 값 모두 dup이 새 pane에 넘겨, 분할 후 포커스가 옮겨가도 탭 모양이 유지된다.

function Get-TabColorPalette {
    # fnc-ignore
    # tc 색 목록 (Id는 입력/자동완성용, Name은 표시용). 프롬프트 팔레트 계열로 맞췄다. Hex가 비면 기본(색 없음).
    @(
        [pscustomobject]@{ Id = 'default'; Name = '기본';     Hex = '' }
        [pscustomobject]@{ Id = 'red';     Name = '빨강';     Hex = '#FF2740' }
        [pscustomobject]@{ Id = 'coral';   Name = '코랄';     Hex = '#E76F51' }
        [pscustomobject]@{ Id = 'orange';  Name = '주황';     Hex = '#F4A261' }
        [pscustomobject]@{ Id = 'yellow';  Name = '황색';     Hex = '#E9C46A' }
        [pscustomobject]@{ Id = 'green';   Name = '초록';     Hex = '#90BE6D' }
        [pscustomobject]@{ Id = 'teal';    Name = '청록';     Hex = '#2EC4B6' }
        [pscustomobject]@{ Id = 'sky';     Name = '하늘';     Hex = '#5BC0EB' }
        [pscustomobject]@{ Id = 'blue';    Name = '파랑';     Hex = '#3A86FF' }
        [pscustomobject]@{ Id = 'purple';  Name = '보라';     Hex = '#B06CF5' }
        [pscustomobject]@{ Id = 'lilac';   Name = '라일락';   Hex = '#D19BFF' }
        [pscustomobject]@{ Id = 'pink';    Name = '분홍';     Hex = '#F28FAD' }
        [pscustomobject]@{ Id = 'slate';   Name = '슬레이트'; Hex = '#8D99AE' }
        [pscustomobject]@{ Id = 'gray';    Name = '회색';     Hex = '#4A4F5A' }
    )
}

function Write-TabColorSequence {
    # fnc-ignore
    # 현재 pane의 탭 색을 바꾼다. 빈 값이면 원래 색(없음)으로 되돌린다.
    param([string]$Hex)

    $esc = [char]27

    if ([string]::IsNullOrWhiteSpace($Hex)) {
        [Console]::Write("$esc]104;264$esc\")
        return
    }

    $h = $Hex.TrimStart('#')
    [Console]::Write(("$esc]4;264;rgb:{0}/{1}/{2}$esc\" -f $h.Substring(0, 2), $h.Substring(2, 2), $h.Substring(4, 2)))
}

function Write-TabTitleSequence {
    # fnc-ignore
    # 현재 pane의 제목을 바꾼다. 빈 값이면 WT가 프로필 이름으로 되돌린다.
    param([string]$Title)

    $esc = [char]27
    $clean = $Title -replace '[\x00-\x1f\x7f]', ''
    [Console]::Write("$esc]2;$clean$esc\")
}

function Select-TabPickerItem {
    # fnc-ignore
    # tt/tc 공용 선택 화면. 대체 화면 버퍼에 목록을 띄우고 커서가 움직일 때마다 OnMove로 탭에 바로 미리보기한다.
    # 선택한 번호를 돌려주고, Esc/q/Ctrl+C로 나가면 OnCancel로 원래 모양을 되돌린 뒤 -1을 돌려준다.
    param(
        [string]$Header,
        [string[]]$Rows,
        [int]$StartIndex = 0,
        [scriptblock]$OnMove,
        [scriptblock]$OnCancel
    )

    $esc = [char]27
    $pos = $StartIndex
    $chosen = -1

    [Console]::Write("$esc[?1049h$esc[?25l")

    try {
        while ($true) {
            if ($OnMove) { & $OnMove $pos }

            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append("$esc[H$esc[2J")
            [void]$sb.Append("$esc[93m$Header$esc[0m`n")
            [void]$sb.Append("$esc[90m  ↑↓ 이동 (탭에 바로 미리보기) | Enter 적용 | Esc/q 취소$esc[0m`n`n")

            for ($i = 0; $i -lt $Rows.Count; $i++) {
                $cursor = if ($i -eq $pos) { "$esc[92m>$esc[0m" } else { ' ' }
                [void]$sb.Append((" {0} {1}$esc[0m`n" -f $cursor, $Rows[$i]))
            }

            [Console]::Write($sb.ToString())

            switch (Read-SshPickerKey) {
                'UpArrow'   { $pos = ($pos - 1 + $Rows.Count) % $Rows.Count }
                'DownArrow' { $pos = ($pos + 1) % $Rows.Count }
                'Enter'     { $chosen = $pos; return $chosen }
                'Escape'    { return -1 }
                'Q'         { return -1 }
            }
        }
    }
    finally {
        # Ctrl+C로 중단돼도 화면과 탭 모양을 원래대로 돌린다.
        [Console]::Write("$esc[?1049l$esc[?25h")
        if ($chosen -lt 0 -and $OnCancel) { & $OnCancel }
    }
}

function set-tabcolor
{
    # 현재 탭 색상을 바꾼다. 인자 없으면 색 견본 목록에서 선택, 이름(Tab 완성)/RRGGBB 지정, default: 원래대로. (축약: tc, 제목까지 한 번에: tb)
    # 적용하면 $true, 취소·실패면 $false를 돌려준다 (tb가 다음 단계로 갈지 판단).
    param(
        [Parameter(Position = 0)]
        [string]$Color
    )

    if (-not $env:WT_SESSION) {
        Write-Host "Windows Terminal 안에서 실행할 때만 탭 색을 바꿀 수 있습니다." -ForegroundColor Yellow
        return $false
    }

    $esc = [char]27
    $palette = @(Get-TabColorPalette)
    $current = [string]$env:OMP_TABCOLOR

    if ($Color) {
        # 셸에서 #은 주석 시작이라 RRGGBB만 입력해도 되게 한다 ('#RRGGBB'처럼 따옴표로 감싸도 된다).
        if ($Color -match '^#?[0-9A-Fa-f]{6}$') {
            $picked = [pscustomobject]@{ Id = 'custom'; Name = '사용자 지정'; Hex = '#' + $Color.TrimStart('#').ToUpper() }
        }
        else {
            $picked = $palette | Where-Object { $_.Id -eq $Color -or $_.Name -eq $Color } | Select-Object -First 1
        }

        if (-not $picked) {
            Write-Host ("알 수 없는 색입니다: {0}  (tc 만 입력하면 목록, 이름은 Tab 자동완성, RRGGBB 직접 지정 가능)" -f $Color) -ForegroundColor Yellow
            return $false
        }
    }
    else {
        $rows = foreach ($p in $palette) {
            $swatch = if ($p.Hex) {
                $h = $p.Hex.TrimStart('#')
                "$esc[48;2;{0};{1};{2}m      $esc[0m" -f [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)
            }
            else {
                "$esc[90m  --  $esc[0m"
            }
            $isCurrent = ($p.Hex -and $p.Hex -eq $current) -or (-not $p.Hex -and -not $current)
            $mark = if ($isCurrent) { "  $esc[92m(현재)$esc[0m" } else { '' }
            # 한글은 두 칸이라 정렬 칸(-8)에는 영문/숫자만 넣고 설명은 맨 뒤에 붙인다.
            $nameText = if ($p.Hex) { $p.Name } else { "{0} (색 없음)" -f $p.Name }
            "{0}  {1,-8} {2,-8} {3}{4}" -f $swatch, $p.Id, $p.Hex, $nameText, $mark
        }

        $start = [Math]::Max(0, [array]::FindIndex($palette, [Predicate[object]] { param($p) ($p.Hex -and $p.Hex -eq $current) -or (-not $p.Hex -and -not $current) }))

        $index = Select-TabPickerItem -Header '탭 색상 선택' -Rows $rows -StartIndex $start `
            -OnMove { param($i) Write-TabColorSequence $palette[$i].Hex } `
            -OnCancel { Write-TabColorSequence $current }

        if ($index -lt 0) {
            Write-Host "탭 색상 변경을 취소했습니다." -ForegroundColor DarkCyan
            return $false
        }

        $picked = $palette[$index]
    }

    Write-TabColorSequence $picked.Hex

    if ($picked.Hex) {
        $env:OMP_TABCOLOR = $picked.Hex
        Write-Host ("탭 색상: {0} {1} ({2})" -f $picked.Id, $picked.Name, $picked.Hex) -ForegroundColor Green
    }
    else {
        Remove-Item 'Env:OMP_TABCOLOR' -ErrorAction SilentlyContinue
        Write-Host "탭 색상을 원래대로 되돌렸습니다." -ForegroundColor Green
    }

    return $true
}

function set-tabtitle
{
    # 현재 탭 제목을 바꾼다. 인자 없으면 후보 목록(직접 입력/SV/SV+경로/현재 폴더/기본)에서 선택, '' = 프로필 이름. (축약: tt, 색까지 한 번에: tb)
    # 적용하면 $true, 취소·실패면 $false를 돌려준다 (tb가 다음 단계로 갈지 판단).
    param(
        [Parameter(Position = 0)]
        [string]$Title
    )

    if (-not $env:WT_SESSION) {
        Write-Host "Windows Terminal 안에서 실행할 때만 탭 제목을 바꿀 수 있습니다." -ForegroundColor Yellow
        return $false
    }

    $current = [string]$env:OMP_TITLE

    # 빈 문자열을 명시하면 기본(프로필 이름)으로, 아예 생략하면 목록에서 고른다.
    if (-not $PSBoundParameters.ContainsKey('Title')) {
        # 라벨은 한글 폭(2칸)을 감안해 12칸에 맞춰 둔다.
        $items = [System.Collections.Generic.List[object]]::new()
        $items.Add([pscustomobject]@{ Label = '직접 입력   '; Title = $null })

        if (-not [string]::IsNullOrWhiteSpace($global:SV)) {
            $items.Add([pscustomobject]@{ Label = 'SV 별칭     '; Title = [string]$global:SV })

            if (-not [string]::IsNullOrWhiteSpace($global:SVDIR)) {
                $items.Add([pscustomobject]@{ Label = 'SV + 경로   '; Title = ("{0}:{1}" -f $global:SV, $global:SVDIR) })
            }
        }

        $folder = Split-Path -Leaf $PWD.ProviderPath
        if ($folder) {
            $items.Add([pscustomobject]@{ Label = '현재 폴더   '; Title = $folder })
        }

        $items.Add([pscustomobject]@{ Label = '기본        '; Title = '' })

        $esc = [char]27
        $rows = foreach ($item in $items) {
            $text = if ($null -eq $item.Title) { "$esc[90m새 제목을 입력한다$esc[0m" }
                elseif ($item.Title -eq '') { "$esc[90m프로필 이름으로 되돌린다$esc[0m" }
                else { $item.Title }
            $mark = if ($null -ne $item.Title -and $item.Title -eq $current) { "  $esc[92m(현재)$esc[0m" } else { '' }
            "{0}{1}{2}" -f $item.Label, $text, $mark
        }

        # 제목을 정한 적이 있으면 그 줄에서, 없으면 직접 입력 줄에서 시작한다.
        $start = if ($current) { [Math]::Max(0, $items.FindIndex([Predicate[object]] { param($item) $item.Title -eq $current })) } else { 0 }

        # 직접 입력 줄에서는 입력 전이라 현재 제목을 그대로 보여준다.
        $index = Select-TabPickerItem -Header '탭 제목 선택' -Rows $rows -StartIndex $start `
            -OnMove { param($i) Write-TabTitleSequence $(if ($null -eq $items[$i].Title) { $current } else { $items[$i].Title }) } `
            -OnCancel { Write-TabTitleSequence $current }

        if ($index -lt 0) {
            Write-Host "탭 제목 변경을 취소했습니다." -ForegroundColor DarkCyan
            return $false
        }

        # $Title은 [string]이라 $null을 넣으면 ''(기본)로 바뀌므로, 직접 입력 판별은 형 없는 변수로 한다.
        $choice = $items[$index].Title

        if ($null -eq $choice) {
            $choice = Read-Host "탭 제목 (빈 값이면 취소)"
            if ([string]::IsNullOrWhiteSpace($choice)) {
                Write-TabTitleSequence $current
                Write-Host "탭 제목 변경을 취소했습니다." -ForegroundColor DarkCyan
                return $false
            }
        }

        $Title = $choice
    }

    Write-TabTitleSequence $Title

    if ($Title) {
        $env:OMP_TITLE = $Title
        Write-Host ("탭 제목: {0}" -f $Title) -ForegroundColor Green
    }
    else {
        Remove-Item 'Env:OMP_TITLE' -ErrorAction SilentlyContinue
        Write-Host "탭 제목을 프로필 이름으로 되돌렸습니다." -ForegroundColor Green
    }

    return $true
}

function tc {
    # alias-fn: 현재 탭 색상을 바꾼다. (= set-tabcolor, 인자 없으면 색 견본 목록, default: 원래대로)
    param(
        [Parameter(Position = 0)]
        [string]$Color
    )

    $null = set-tabcolor -Color $Color
}

function tt {
    # alias-fn: 현재 탭 제목을 바꾼다. (= set-tabtitle, 인자 없으면 후보 목록, 인자는 공백 포함 그대로 제목)
    # 따옴표 없이 여러 단어를 쓰도록 param 대신 $args를 이어 붙인다.
    if ($args.Count -gt 0) {
        $null = set-tabtitle -Title ((@($args) | ForEach-Object { [string]$_ }) -join ' ')
    }
    else {
        $null = set-tabtitle
    }
}

function tb {
    # alias-fn: 탭 제목과 색상을 한 번에 바꾼다. (= tt <제목> + tc <색>, 생략한 쪽은 목록에서 선택)
    param(
        [Parameter(Position = 0)]
        [string]$Title,

        [Parameter(Position = 1)]
        [string]$Color
    )

    # 생략한 쪽은 tt/tc처럼 목록에서 고른다. 제목 선택이 취소·실패하면($true가 아니면) 색은 건드리지 않는다.
    $titleArgs = @{}
    if ($PSBoundParameters.ContainsKey('Title')) { $titleArgs.Title = $Title }

    if (-not (@(set-tabtitle @titleArgs) -contains $true)) { return }
    $null = set-tabcolor -Color $Color
}

Register-ArgumentCompleter -CommandName tc, tb, set-tabcolor -ParameterName Color -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    Get-TabColorPalette | Where-Object { $_.Id -like "$wordToComplete*" } | ForEach-Object {
        $hexText = if ($_.Hex) { $_.Hex } else { '색 없음' }
        [System.Management.Automation.CompletionResult]::new($_.Id, $_.Id, 'ParameterValue', ("{0} {1}" -f $_.Name, $hexText))
    }
}

# 제목 후보(SV 별칭, SV+경로, 현재 폴더)를 Tab으로 채운다.
Register-ArgumentCompleter -CommandName tb, set-tabtitle -ParameterName Title -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $word = $wordToComplete.Trim("'`"")
    $candidates = @(
        if (-not [string]::IsNullOrWhiteSpace($global:SV)) {
            [string]$global:SV
            if (-not [string]::IsNullOrWhiteSpace($global:SVDIR)) { "{0}:{1}" -f $global:SV, $global:SVDIR }
        }
        Split-Path -Leaf $PWD.ProviderPath
    ) | Where-Object { $_ -and $_ -like "$word*" } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        $text = if ($candidate -match '[\s''"$;,(){}#]') { "'{0}'" -f ($candidate -replace "'", "''") } else { $candidate }
        [System.Management.Automation.CompletionResult]::new($text, $candidate, 'ParameterValue', $candidate)
    }
}

#########################################################
# 터미널 탭 제목 / 색상 (tt/tc/tb) 영역 End
#########################################################


#########################################################
# 터미널 작업공간 스냅샷 (ws) 영역 Start
#########################################################
# 창에 열린 탭 순서 · 분할 구조 · 각 pane의 선택 상태(SV/DST/SVDIR/작업 경로)를 파일로 저장하고 그대로 다시 연다.
#
# 화면 구조는 UI 자동화로 읽는다 - WT가 구조를 알려주는 공개 방법이 없기 때문이다.
# 각 pane의 변수는 밖에서 읽을 수 없으므로(pane마다 프로세스가 따로다) pane에 걸어둔 감시기가 요청을 받으면 스스로 답한다.
# 감시기는 셸이 놀고 있을 때만 돌 수 있어, 명령을 실행 중인 pane은 응답하지 못한다 (저장할 때 어느 pane인지 알려준다).
# 요청/응답 파일은 임시 폴더에서만 오가고 저장이 끝나면 지운다 - 남는 것은 스냅샷 파일 하나뿐이다.

$global:ws_req_dir = Join-Path ([IO.Path]::GetTempPath()) 'pws-ws'
$global:ws_store_dir = Join-Path (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) 'workspaces'

function Invoke-WsPaneRequest {
    # fnc-ignore
    # 스냅샷 요청 파일 하나를 처리한다. (각 pane의 감시기가 유휴 상태에서 부른다)
    param([string]$Path)

    $name = [IO.Path]::GetFileName($Path)

    if ($name -like 'wsrel-*') {
        # 표식으로 바꿔 둔 제목을 되돌린다. 빈 값이면 WT가 프로필 이름으로 돌아간다.
        Write-TabTitleSequence ([string]$env:OMP_TITLE)
        return
    }

    if ($name -notlike 'wsreq-*') { return }

    # 화면의 어느 자리가 이 pane인지 정확히 맞추려고 제목을 잠깐 표식으로 바꾼다 (wsrel- 요청에서 되돌린다).
    $marker = "ws:{0}" -f $PID
    Write-TabTitleSequence $marker

    $state = [ordered]@{
        Pid      = $PID
        Marker   = $marker
        Session  = [string]$env:WT_SESSION
        Title    = [string]$env:OMP_TITLE
        TabColor = [string]$env:OMP_TABCOLOR
        Cwd      = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath } else { $HOME }
        Cols     = 0
        Rows     = 0
        Last     = ''
    }

    # 창 크기를 글자 수(cols,rows)로 되살리려면 셀 하나의 크기를 알아야 한다.
    # pane의 화면 사각형을 이 값으로 나누면 셀 크기가 나온다.
    try {
        $state.Cols = [Console]::WindowWidth
        $state.Rows = [Console]::WindowHeight
    }
    catch { }

    $last = Get-History -Count 1 -ErrorAction SilentlyContinue
    if ($last) { $state.Last = [string]$last.CommandLine }

    foreach ($nm in 'SV', 'SVID', 'SVIP', 'SVPORT', 'SVDIR', 'DST', 'DSTID', 'DSTIP', 'DSTPORT') {
        $var = Get-Variable $nm -Scope Global -ErrorAction SilentlyContinue
        $state[$nm] = if ($var -and $null -ne $var.Value) { [string]$var.Value } else { '' }
    }

    $reply = Join-Path $global:ws_req_dir ("reply-{0}-{1}.json" -f $name.Substring(6), $PID)
    $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $reply -Encoding utf8
}

function Register-WsPaneAgent {
    # fnc-ignore
    # 이 pane이 스냅샷 요청에 답할 수 있게 감시기를 건다. (프로필 로드 때 1회, 약 8ms)
    if ($global:ws_agent) { return }
    if (-not $env:WT_SESSION) { return }

    try {
        if (-not [IO.Directory]::Exists($global:ws_req_dir)) {
            $null = [IO.Directory]::CreateDirectory($global:ws_req_dir)
        }

        $watcher = [IO.FileSystemWatcher]::new($global:ws_req_dir, 'ws*')
        $watcher.EnableRaisingEvents = $true

        $null = Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier ("ws-agent-" + $PID) -Action {
            try { Invoke-WsPaneRequest -Path $Event.SourceEventArgs.FullPath } catch { }
        }

        $global:ws_agent = $watcher
    }
    catch {
        Write-Warning ("작업공간 감시기를 걸지 못했습니다: {0}" -f $_.Exception.Message)
    }
}

function Get-WsTerminalLayout {
    # fnc-ignore
    # UI 자동화로 내 창의 탭 순서와 각 탭의 pane(사각형 + 표식)을 읽는다. (시험 때 이 함수만 바꿔 끼운다)
    #
    # pane 자체의 UIA 이름은 셸이 보낸 제목을 따라가지 않는다(프로필 이름 그대로다). 대신 탭 이름이
    # '지금 활성화된 pane의 제목'을 보여주므로, pane을 하나씩 활성화하며 탭 이름(그 pane이 붙인 표식)과
    # 포커스된 pane의 사각형을 짝지어 읽는다. 비활성 탭은 내용이 만들어져 있지 않아 탭도 하나씩 활성화한다.
    #
    # RequestPath를 주면 pane을 읽기 직전에 요청 파일을 다시 만들어 표식을 새로 달게 한다.
    # (프롬프트가 한 번 더 그려지면 제목이 원래대로 돌아가 표식이 사라지기 때문이다)
    param([string]$SelfMarker, [string]$RequestPath)

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes

    $termCond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'TermControl')
    $windowCond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'CASCADIA_HOSTING_WINDOW_CLASS')
    $itemCond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'ListViewItem')

    $selection = [System.Windows.Automation.SelectionItemPattern]::Pattern
    $descendants = [System.Windows.Automation.TreeScope]::Descendants

    # 창이 여러 개여도 프로세스는 하나라서 MainWindowHandle로는 못 고른다. 내 표식이 탭 이름에 보이는 창이 내 창이다.
    $root = $null
    $items = @()

    foreach ($candidate in @([System.Windows.Automation.AutomationElement]::RootElement.FindAll(
                [System.Windows.Automation.TreeScope]::Children, $windowCond))) {

        $tabs = @($candidate.FindAll($descendants, $itemCond))

        foreach ($tab in $tabs) {
            if ($tab.Current.Name -eq $SelfMarker) { $root = $candidate; $items = $tabs; break }
        }

        if ($root) { break }
    }

    if (-not $root -or $items.Count -eq 0) { return $null }

    $activeIndex = 0
    for ($i = 0; $i -lt $items.Count; $i++) {
        if ($items[$i].GetCurrentPattern($selection).Current.IsSelected) { $activeIndex = $i }
    }

    $canFocus = [bool](Get-Command wt -ErrorAction SilentlyContinue)
    $tabsOut = @()
    $selfTab = $activeIndex
    $selfPaneId = 0

    for ($i = 0; $i -lt $items.Count; $i++) {
        $pattern = $items[$i].GetCurrentPattern($selection)

        if (-not $pattern.Current.IsSelected) {
            $pattern.Select()
            Start-Sleep -Milliseconds 250
        }

        $terms = @($root.FindAll($descendants, $termCond) | Where-Object {
                $_.Current.BoundingRectangle.Width -gt 1 -and $_.Current.BoundingRectangle.Height -gt 1
            })

        $panes = @()

        if ($terms.Count -eq 1) {
            $rect = $terms[0].Current.BoundingRectangle
            $panes += [pscustomobject]@{
                Name = [string]$items[$i].Current.Name
                X    = [double]$rect.X; Y = [double]$rect.Y
                W    = [double]$rect.Width; H = [double]$rect.Height
            }
        }
        else {
            # pane을 하나씩 활성화하면 탭 이름이 그 pane의 제목(표식)으로 바뀐다.
            # wt 실행이 늦어 아직 포커스가 안 옮겨졌을 수 있으므로, '새 사각형 + 새 표식'이 확인될 때까지 기다린 뒤 기록한다.
            # (기다리지 않으면 직전 pane의 정보를 그대로 다시 읽어 여러 pane이 같은 상태로 저장된다)
            $mapped = @{}
            $usedMarks = @{}
            $idByKey = @{}
            $originKey = ''

            $current = @($terms | Where-Object { $_.Current.HasKeyboardFocus })
            if ($current.Count -eq 1) {
                $rect = $current[0].Current.BoundingRectangle
                $originKey = "{0:0},{1:0}" -f $rect.X, $rect.Y
            }

            # pane 번호는 만든 순서대로 붙고 중간에 빠질 수 있어, 필요한 만큼 번호를 넓혀가며 찾는다.
            $paneId = 0
            $guard = 0

            while ($panes.Count -lt $terms.Count -and $guard -lt (($terms.Count * 3) + 6)) {
                $guard++
                $target = $paneId
                $paneId++

                if ($canFocus) { & wt -w 0 focus-pane -t $target 2>$null }

                # 표식을 다시 달게 한다 (이 pane이 그 사이 제목을 원래대로 되돌렸을 수 있다).
                Update-WsRequest -Path $RequestPath

                $deadline = (Get-Date).AddMilliseconds(2500)
                $retry = 0

                while ((Get-Date) -lt $deadline) {
                    Start-Sleep -Milliseconds 120
                    $retry++

                    # 중간에 한 번 더 요청해 둔다 (느린 PC에서 첫 요청이 늦게 처리되는 경우).
                    if ($retry -eq 6) { Update-WsRequest -Path $RequestPath }

                    $focused = @($terms | Where-Object { $_.Current.HasKeyboardFocus })
                    if ($focused.Count -ne 1) { continue }

                    $rect = $focused[0].Current.BoundingRectangle
                    $key = "{0:0},{1:0}" -f $rect.X, $rect.Y
                    if ($mapped.ContainsKey($key)) { continue }

                    # 탭 제목이 아직 이전 pane의 표식이면 바뀔 때까지 더 기다린다.
                    $name = [string]$items[$i].Current.Name
                    if ($name -like 'ws:*' -and $usedMarks.ContainsKey($name)) { continue }

                    $mapped[$key] = $true
                    $idByKey[$key] = $target
                    if ($name -like 'ws:*') { $usedMarks[$name] = $true }

                    $panes += [pscustomobject]@{
                        Name = $name
                        X    = [double]$rect.X; Y = [double]$rect.Y
                        W    = [double]$rect.Width; H = [double]$rect.Height
                    }

                    if ($name -eq $SelfMarker) { $selfTab = $i; $selfPaneId = $target }
                    break
                }

                if (-not $canFocus) { break }
            }

            # 끝내 확인하지 못한 pane은 자리만 남긴다 (상태는 '응답 없음'으로 처리된다).
            foreach ($term in $terms) {
                $rect = $term.Current.BoundingRectangle
                $key = "{0:0},{1:0}" -f $rect.X, $rect.Y
                if ($mapped.ContainsKey($key)) { continue }

                $mapped[$key] = $true
                $panes += [pscustomobject]@{
                    Name = ''
                    X    = [double]$rect.X; Y = [double]$rect.Y
                    W    = [double]$rect.Width; H = [double]$rect.Height
                }
            }

            # 이 탭에서 원래 보고 있던 pane으로 되돌린다.
            if ($canFocus -and $originKey -and $idByKey.ContainsKey($originKey)) {
                & wt -w 0 focus-pane -t $idByKey[$originKey] 2>$null
            }
        }

        $tabsOut += [pscustomobject]@{ Index = $i; Title = [string]$items[$i].Current.Name; Panes = $panes }
    }

    # 보고 있던 탭과 pane으로 되돌린다.
    $items[$selfTab].GetCurrentPattern($selection).Select()
    if ($canFocus) {
        Start-Sleep -Milliseconds 150
        & wt -w 0 focus-pane -t $selfPaneId 2>$null
    }

    # 창 위치·크기는 Win32 기준으로 읽는다 (--pos가 쓰는 기준과 같아야 복원 위치가 맞는다).
    $windowRect = $null
    $handle = $root.Current.NativeWindowHandle

    if ($handle) { $windowRect = Get-WsWindowRect -Handle $handle }

    if (-not $windowRect) {
        $fallback = $root.Current.BoundingRectangle
        $windowRect = [pscustomobject]@{
            X = [int]$fallback.X; Y = [int]$fallback.Y
            W = [int]$fallback.Width; H = [int]$fallback.Height
        }
    }

    [pscustomobject]@{
        ActiveIndex = $activeIndex
        Tabs        = $tabsOut
        Window      = $windowRect
    }
}

function Initialize-WsWin32 {
    # fnc-ignore
    # 창 위치·크기를 읽고 맞추는 데 쓰는 Win32 함수를 한 번만 준비한다.
    if (-not ('WsNative.Win32' -as [type])) {
        Add-Type -Namespace WsNative -Name Win32 -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ShowWindow(IntPtr hWnd, int cmd);
'@
    }
}

function Get-WsWindowRect {
    # fnc-ignore
    # 창의 위치·크기를 Win32 기준으로 읽는다. (UI 자동화 사각형은 그림자만큼 어긋나 복원 기준으로 못 쓴다)
    param([int]$Handle)

    Initialize-WsWin32

    # 복원할 때 SetWindowPos로 그대로 맞출 것이므로 같은 기준(GetWindowRect)으로 읽는다.
    $rect = New-Object WsNative.Win32+RECT

    if (-not [WsNative.Win32]::GetWindowRect([IntPtr]$Handle, [ref]$rect)) { return $null }

    [pscustomobject]@{
        X = $rect.Left
        Y = $rect.Top
        W = ($rect.Right - $rect.Left)
        H = ($rect.Bottom - $rect.Top)
    }
}

function Update-WsRequest {
    # fnc-ignore
    # 요청 파일을 다시 만들어 각 pane이 표식(제목)을 새로 달게 한다. (같은 이름으로 다시 만들어야 감시기가 반응한다)
    param([string]$Path)

    if (-not $Path) { return }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $Path -Value 'again' -Encoding utf8
    }
    catch { }
}

function Set-WsPaneState {
    # fnc-ignore
    # pane 하나에 그 pane이 보내온 상태를 붙인다.
    param([object]$Leaf, [object]$State)

    Add-Member -InputObject $Leaf -NotePropertyName Responded -NotePropertyValue $true -Force

    foreach ($nm in 'Pid', 'Title', 'TabColor', 'Cwd', 'Last', 'Cols', 'Rows', 'SV', 'SVID', 'SVIP', 'SVPORT', 'SVDIR', 'DST', 'DSTID', 'DSTIP', 'DSTPORT') {
        Add-Member -InputObject $Leaf -NotePropertyName $nm -NotePropertyValue ([string]$State.$nm) -Force
    }
}

function Get-WsTerminalWindowHandles {
    # fnc-ignore
    # 지금 떠 있는 Windows Terminal 창들의 핸들을 모은다. (복원 직후 새로 생긴 창을 찾는 데 쓴다)
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes

    $cond = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'CASCADIA_HOSTING_WINDOW_CLASS')

    @([System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Children, $cond) |
        ForEach-Object { [int]$_.Current.NativeWindowHandle } | Where-Object { $_ })
}

function Set-WsWindowPlacement {
    # fnc-ignore
    # 복원한 창을 저장해 둔 픽셀 크기·위치에 정확히 맞춘다.
    # (wt --size는 글자 수 단위라 분할 구분선·여백 때문에 저장/복원을 되풀이하면 창이 조금씩 줄어든다)
    param([int]$Handle, [object]$Window)

    Initialize-WsWin32

    if ($Window.Maximized) {
        # 3 = SW_MAXIMIZE
        [void][WsNative.Win32]::ShowWindow([IntPtr]$Handle, 3)
        return
    }

    $width = [int]$Window.W
    $height = [int]$Window.H
    if ($width -le 0 -or $height -le 0) { return }

    # 0x0004 SWP_NOZORDER | 0x0010 SWP_NOACTIVATE
    [void][WsNative.Win32]::SetWindowPos([IntPtr]$Handle, [IntPtr]::Zero, [int]$Window.X, [int]$Window.Y, $width, $height, 0x0014)
}

function Test-WsMaximized {
    # fnc-ignore
    # 창이 모니터 작업 영역을 거의 꽉 채우면 최대화 상태로 본다. (복원할 때 --maximized로 연다)
    param([object]$Rect)

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $center = [System.Drawing.Point]::new([int]($Rect.X + ($Rect.W / 2)), [int]($Rect.Y + ($Rect.H / 2)))
        $area = [System.Windows.Forms.Screen]::FromPoint($center).WorkingArea

        return (($Rect.W -ge ($area.Width - 24)) -and ($Rect.H -ge ($area.Height - 24)))
    }
    catch { return $false }
}

function ConvertTo-WsPaneTree {
    # fnc-ignore
    # pane 사각형 목록을 좌우(V)/상하(H) 분할 트리로 바꾼다. 복원할 때 분할 방향과 비율로 쓴다.
    param([object[]]$Panes)

    $list = @($Panes)
    if ($list.Count -eq 0) { return $null }
    if ($list.Count -eq 1) { return [pscustomobject]@{ Kind = 'pane'; Pane = $list[0] } }

    # 같은 방향으로 죽 늘어선 경계선을 하나 찾는다. 모든 pane이 그 선의 왼쪽/오른쪽(또는 위/아래)으로 깔끔히 갈려야 한다.
    foreach ($dir in 'V', 'H') {
        $edges = @($list | ForEach-Object { if ($dir -eq 'V') { $_.X + $_.W } else { $_.Y + $_.H } } | Sort-Object -Unique)

        foreach ($edge in $edges) {
            $first = @($list | Where-Object { if ($dir -eq 'V') { ($_.X + $_.W) -le ($edge + 2) } else { ($_.Y + $_.H) -le ($edge + 2) } })
            $second = @($list | Where-Object { if ($dir -eq 'V') { $_.X -ge ($edge - 2) } else { $_.Y -ge ($edge - 2) } })

            if ($first.Count -eq 0 -or $second.Count -eq 0) { continue }
            if (($first.Count + $second.Count) -ne $list.Count) { continue }

            $start = ($list | ForEach-Object { if ($dir -eq 'V') { $_.X } else { $_.Y } } | Measure-Object -Minimum).Minimum
            $end = ($list | ForEach-Object { if ($dir -eq 'V') { $_.X + $_.W } else { $_.Y + $_.H } } | Measure-Object -Maximum).Maximum
            $mid = ($second | ForEach-Object { if ($dir -eq 'V') { $_.X } else { $_.Y } } | Measure-Object -Minimum).Minimum

            $total = $end - $start
            if ($total -le 0) { continue }

            # 분할 비율은 '새로 만드는 pane(뒤쪽)'의 몫이다 - wt split-pane -s 가 그 기준이다.
            $ratio = [Math]::Round((($end - $mid) / $total), 3)
            if ($ratio -le 0.02 -or $ratio -ge 0.98) { continue }

            return [pscustomobject]@{
                Kind   = 'split'
                Dir    = $dir
                Ratio  = $ratio
                First  = (ConvertTo-WsPaneTree -Panes $first)
                Second = (ConvertTo-WsPaneTree -Panes $second)
            }
        }
    }

    # 나눌 선을 못 찾으면(겹쳐 보이는 경우) 순서대로 나열만 해 둔다 - 복원은 좌우 균등 분할로 한다.
    $half = [int][Math]::Ceiling($list.Count / 2)

    [pscustomobject]@{
        Kind   = 'split'
        Dir    = 'V'
        Ratio  = 0.5
        First  = (ConvertTo-WsPaneTree -Panes $list[0..($half - 1)])
        Second = (ConvertTo-WsPaneTree -Panes $list[$half..($list.Count - 1)])
    }
}

function Get-WsTreeCells {
    # fnc-ignore
    # 분할 트리 전체가 몇 글자인지 센다. 좌우 분할이면 가로를 더하고 구분선 한 칸을 넣는다.
    # (픽셀로 환산하면 반올림 때문에 한 칸씩 어긋나므로, 각 pane이 보고한 글자 수로 직접 센다)
    param([object]$Node)

    if (-not $Node) { return $null }

    if ($Node.Kind -eq 'pane') {
        $cols = [int]$Node.Pane.Cols
        $rows = [int]$Node.Pane.Rows

        if ($cols -le 0 -or $rows -le 0) { return $null }
        return [pscustomobject]@{ Cols = $cols; Rows = $rows }
    }

    $first = Get-WsTreeCells -Node $Node.First
    $second = Get-WsTreeCells -Node $Node.Second

    if (-not $first -or -not $second) { return $null }

    if ($Node.Dir -eq 'V') {
        return [pscustomobject]@{ Cols = ($first.Cols + $second.Cols + 1); Rows = [Math]::Max($first.Rows, $second.Rows) }
    }

    [pscustomobject]@{ Cols = [Math]::Max($first.Cols, $second.Cols); Rows = ($first.Rows + $second.Rows + 1) }
}

function Get-WsLeafPanes {
    # fnc-ignore
    # 분할 트리 안의 pane을 생성 순서대로 모은다.
    param([object]$Node)

    if (-not $Node) { return @() }
    if ($Node.Kind -eq 'pane') { return @($Node.Pane) }

    @(Get-WsLeafPanes -Node $Node.First) + @(Get-WsLeafPanes -Node $Node.Second)
}

function Get-WsPaneSpot {
    # fnc-ignore
    # 탭 안에서 이 pane이 어느 자리인지 사람 말로 적는다. (응답하지 않은 pane을 알려줄 때 쓴다)
    param([object]$Pane, [object[]]$All)

    $minX = ($All | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum
    $maxX = ($All | ForEach-Object { $_.X + $_.W } | Measure-Object -Maximum).Maximum
    $minY = ($All | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
    $maxY = ($All | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum

    $cx = $Pane.X + ($Pane.W / 2)
    $cy = $Pane.Y + ($Pane.H / 2)

    $side = if (($maxX - $minX) -le ($Pane.W + 4)) { '' }
        elseif ($cx -lt (($minX + $maxX) / 2)) { '왼쪽' } else { '오른쪽' }

    $level = if (($maxY - $minY) -le ($Pane.H + 4)) { '' }
        elseif ($cy -lt (($minY + $maxY) / 2)) { '위' } else { '아래' }

    $spot = (@($side, $level) | Where-Object { $_ }) -join ' '
    if ($spot) { $spot } else { '전체' }
}

function Save-WsSnapshot {
    # fnc-ignore
    # 현재 창의 탭/분할/각 pane 상태를 읽어 스냅샷 파일로 저장한다. (ws save)
    param([string]$Name, [string]$Memo, [switch]$Force, [switch]$Yes)

    if (-not $env:WT_SESSION) {
        Write-Host "Windows Terminal 안에서만 저장할 수 있습니다." -ForegroundColor Yellow
        return
    }

    if ($Name -match '[\\/:*?"<>|]') {
        Write-Error ("이름에 쓸 수 없는 문자가 있습니다: {0}" -f $Name)
        return
    }

    if (-not [IO.Directory]::Exists($global:ws_store_dir)) {
        $null = [IO.Directory]::CreateDirectory($global:ws_store_dir)
    }

    $file = Join-Path $global:ws_store_dir ("{0}.json" -f $Name)

    if ((Test-Path -LiteralPath $file) -and -not $Yes) {
        Write-Host ("[{0}] 스냅샷이 이미 있습니다. 덮어쓸까요? " -f $Name) -ForegroundColor Yellow -NoNewline
        if ((Read-Host "(y/N)") -notmatch '^(y|yes)$') {
            Write-Host "취소했습니다." -ForegroundColor DarkGray
            return
        }
    }

    if (-not [IO.Directory]::Exists($global:ws_req_dir)) {
        $null = [IO.Directory]::CreateDirectory($global:ws_req_dir)
    }

    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $selfMarker = "ws:{0}" -f $PID
    $requestPath = Join-Path $global:ws_req_dir ("wsreq-{0}" -f $id)
    $releasePath = Join-Path $global:ws_req_dir ("wsrel-{0}" -f $id)

    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"

    Write-Host ("{0}save:$esc[0m {1}{2}$esc[0m  {0}(pane 상태 요청 중...)$esc[0m" -f $sub, $head, $Name)

    # 이 pane도 화면에서 찾아야 하므로 같은 표식을 직접 단다 (실행 중이라 감시기는 못 돈다).
    Write-TabTitleSequence $selfMarker
    Set-Content -LiteralPath $requestPath -Value $id -Encoding utf8

    # 유휴 pane은 0.3초 안에 답한다. 느린 PC를 감안해 1.5초 기다린 뒤 화면을 읽는다.
    Start-Sleep -Milliseconds 1500

    $layout = $null

    try { $layout = Get-WsTerminalLayout -SelfMarker $selfMarker -RequestPath $requestPath }
    catch { Write-Error ("화면 구조를 읽지 못했습니다: {0}" -f $_.Exception.Message) }

    # 화면을 읽는 동안(pane마다 요청을 다시 보낸다) 늦게 도착한 응답까지 함께 모은다.
    $states = @{}
    $replies = @(Get-ChildItem -LiteralPath $global:ws_req_dir -Filter ("reply-{0}-*.json" -f $id) -ErrorAction SilentlyContinue)

    foreach ($reply in $replies) {
        try {
            $state = Get-Content -LiteralPath $reply.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $states[$state.Marker] = $state
        }
        catch { }
    }

    # 표식을 되돌린다 (다른 pane은 감시기가, 이 pane은 직접).
    Set-Content -LiteralPath $releasePath -Value $id -Encoding utf8
    Start-Sleep -Milliseconds 400
    Write-TabTitleSequence ([string]$env:OMP_TITLE)

    Remove-Item -LiteralPath $requestPath, $releasePath -Force -ErrorAction SilentlyContinue
    $replies | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }

    if (-not $layout) {
        Write-Error "내 창을 찾지 못했습니다. (Windows Terminal 창에서 실행해 주세요)"
        return
    }

    $tabs = @()
    $missing = @()
    $usedStates = @{}
    $paneCount = 0
    $cellW = 0.0
    $cellH = 0.0
    $contentW = 0.0
    $contentH = 0.0

    foreach ($tab in $layout.Tabs) {
        # 저장을 실행 중인 이 pane은 스냅샷에서 뺀다 (복원할 때 다시 만들 이유가 없다).
        $panes = @($tab.Panes | Where-Object { $_.Name -ne $selfMarker })
        if ($panes.Count -eq 0) { continue }

        # 탭 내용 영역(= 터미널 영역)은 모든 탭이 같다. 창 크기를 글자 수로 환산할 때 쓴다.
        if ($contentW -le 0) {
            $contentW = (($tab.Panes | ForEach-Object { $_.X + $_.W } | Measure-Object -Maximum).Maximum -
                ($tab.Panes | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum)
            $contentH = (($tab.Panes | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum -
                ($tab.Panes | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum)
        }

        $tree = ConvertTo-WsPaneTree -Panes $panes
        $leaves = @(Get-WsLeafPanes -Node $tree)
        $title = ''
        $color = ''

        foreach ($leaf in $leaves) {
            $paneCount++

            # 한 pane의 응답이 두 자리에 들어가지 않게, 이미 쓴 응답은 다시 쓰지 않는다.
            $state = $null

            if ($leaf.Name -and $states.ContainsKey($leaf.Name) -and -not $usedStates.ContainsKey($leaf.Name)) {
                $state = $states[$leaf.Name]
                $usedStates[$leaf.Name] = $true
            }

            # 셀 하나의 크기(px)는 pane 사각형 ÷ 그 pane의 글자 수로 구한다. 창 크기 복원에 쓴다.
            if ($state -and $cellW -le 0 -and [int]$state.Cols -gt 0 -and [int]$state.Rows -gt 0) {
                $cellW = $leaf.W / [int]$state.Cols
                $cellH = $leaf.H / [int]$state.Rows
            }

            if ($state) {
                Set-WsPaneState -Leaf $leaf -State $state
                if (-not $title -and $state.Title) { $title = [string]$state.Title }
                if (-not $color -and $state.TabColor) { $color = [string]$state.TabColor }
            }
            else {
                Add-Member -InputObject $leaf -NotePropertyName Responded -NotePropertyValue $false -Force
                Add-Member -InputObject $leaf -NotePropertyName Title -NotePropertyValue $leaf.Name -Force
                Add-Member -InputObject $leaf -NotePropertyName Cwd -NotePropertyValue '' -Force
                $missing += [pscustomobject]@{ Tab = $tab.Index; TabTitle = $tab.Title; Spot = (Get-WsPaneSpot -Pane $leaf -All $panes); Name = $leaf.Name; Leaf = $leaf }
            }
        }

        if (-not $title) { $title = [string]$tab.Title }

        $tabs += [pscustomobject]@{
            Title  = $title
            Color  = $color
            Layout = $tree
        }
    }

    if ($tabs.Count -eq 0) {
        Write-Host "저장할 탭이 없습니다. (이 pane 말고 다른 탭/pane이 있어야 합니다)" -ForegroundColor Yellow
        return
    }

    # 자리를 못 찾은 pane과 쓰이지 않은 응답이 하나씩만 남았다면 둘은 같은 pane이다 (표식을 제때 못 읽은 경우).
    $leftover = @($states.Keys | Where-Object { $_ -ne $selfMarker -and -not $usedStates.ContainsKey($_) })

    if ($leftover.Count -eq 1 -and $missing.Count -eq 1) {
        Set-WsPaneState -Leaf $missing[0].Leaf -State $states[$leftover[0]]
        $usedStates[$leftover[0]] = $true
        $missing = @()
    }

    if ($missing.Count -gt 0) {
        # 상태를 보내왔는데도 쓰이지 못한 응답 = 화면에서 그 pane의 자리를 찾지 못한 경우.
        $orphans = @($states.Keys | Where-Object { $_ -ne $selfMarker -and -not $usedStates.ContainsKey($_) })

        Write-Host ""
        Write-Host ("상태를 담지 못한 pane {0}개" -f $missing.Count) -ForegroundColor Yellow

        foreach ($item in $missing) {
            Write-Host ("  탭[{0}] '{1}' 의 {2} pane   (제목: {3})" -f $item.Tab, $item.TabTitle, $item.Spot, $item.Name) -ForegroundColor Yellow
        }

        if ($orphans.Count -gt 0) {
            Write-Host ("  그중 {0}개는 상태를 보내왔지만 화면에서 자리를 찾지 못했습니다 - 쉬고 있는 pane인데 경고가 뜬다면 이 경우입니다." -f $orphans.Count) -ForegroundColor Yellow
            Write-Host "  pane을 찾을 때 제목을 잠깐 표식으로 바꿔 쓰므로, Windows Terminal 설정에 suppressApplicationTitle: false 가 있어야 합니다." -ForegroundColor DarkCyan
            Write-Host "  탭 이름을 마우스로 직접 지정했거나 --title로 연 탭도 제목이 고정돼 찾지 못합니다 (탭 이름 재설정으로 풀립니다)." -ForegroundColor DarkCyan
        }
        else {
            Write-Host "  1) 프로필이 바뀌기 전에 연 pane입니다 - 감시기는 프로필을 읽을 때 걸리므로, 그 pane에서 . `$PROFILE 을 한 번 실행하거나 새로 열어야 합니다." -ForegroundColor DarkCyan
            Write-Host "     (reload는 프롬프트만 새로고침하고 프로필을 다시 읽지 않습니다)" -ForegroundColor DarkCyan
            Write-Host "  2) 명령을 실행 중인 pane입니다 - Ctrl+C로 잠깐 멈춘 뒤 다시 저장하면 변수까지 저장됩니다." -ForegroundColor DarkCyan
            Write-Host "     ssh로 원격 셸에 들어가 있는 pane은 Ctrl+C로 빠져나오지 못하니 먼저 exit 해 주세요." -ForegroundColor DarkCyan
        }

        Write-Host "  구조만 저장하려면: ws save <이름> -f" -ForegroundColor DarkCyan

        if (-not $Force) {
            Write-Host "저장하지 않았습니다." -ForegroundColor Yellow
            return
        }
    }

    # 창 크기·위치도 함께 남긴다. 크기는 글자 수(cols,rows)로 바꿔 둬야 복원할 때 wt가 그대로 연다.
    $window = $null

    if ($layout.Window) {
        # 글자 수는 각 pane이 보고한 값을 트리대로 더해 정확히 센다. 못 세면(응답 없는 pane) 픽셀로 어림한다.
        $cols = 0
        $rows = 0

        foreach ($saved in $tabs) {
            $cells = Get-WsTreeCells -Node $saved.Layout
            if (-not $cells) { continue }
            if ($cells.Cols -gt $cols) { $cols = [int]$cells.Cols }
            if ($cells.Rows -gt $rows) { $rows = [int]$cells.Rows }
        }

        if ($cols -le 0 -and $cellW -gt 0 -and $contentW -gt 0) { $cols = [int][Math]::Round($contentW / $cellW) }
        if ($rows -le 0 -and $cellH -gt 0 -and $contentH -gt 0) { $rows = [int][Math]::Round($contentH / $cellH) }

        $window = [pscustomobject]@{
            X         = [int][Math]::Round($layout.Window.X)
            Y         = [int][Math]::Round($layout.Window.Y)
            W         = [int][Math]::Round($layout.Window.W)
            H         = [int][Math]::Round($layout.Window.H)
            Cols      = $cols
            Rows      = $rows
            Maximized = [bool](Test-WsMaximized -Rect $layout.Window)
        }
    }

    $snapshot = [pscustomobject]@{
        Version = 1
        Name    = $Name
        Memo    = [string]$Memo
        SavedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Window  = $window
        Tabs    = $tabs
    }

    $snapshot | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $file -Encoding utf8
    Write-Host ("저장 완료: {0}  (탭 {1} / pane {2})" -f $file, $tabs.Count, $paneCount) -ForegroundColor Green
    Show-WsSnapshot -Name $Name
}

function Show-WsTree {
    # fnc-ignore
    # 분할 트리를 들여쓰기로 그린다. (ws show)
    param([object]$Node, [int]$Depth = 2)

    $esc = [char]27
    $dim = "$esc[38;5;245m"
    $reset = "$esc[0m"
    $pad = ' ' * ($Depth * 2)

    if ($Node.Kind -eq 'pane') {
        $pane = $Node.Pane
        $bits = @()

        if ($pane.SV) { $bits += "SV={0}" -f $pane.SV }
        if ($pane.SVDIR) { $bits += "DIR={0}" -f $pane.SVDIR }
        if ($pane.DST) { $bits += "DST={0}" -f $pane.DST }
        if ($pane.Cwd) { $bits += $pane.Cwd }
        if (-not $pane.Responded) { $bits += '응답 없음(구조만)' }

        $label = if ($pane.Title) { $pane.Title } else { 'pwsh' }
        Write-Host ("{0}· {1}  {2}{3}{4}" -f $pad, $label, $dim, ($bits -join '  ·  '), $reset)

        if ($pane.Last) {
            Write-Host ("{0}  {1}마지막 명령: {2}{3}" -f $pad, $dim, $pane.Last, $reset)
        }

        return
    }

    $dirText = if ($Node.Dir -eq 'V') { '좌우' } else { '상하' }
    Write-Host ("{0}{1}{2} 분할 (뒤쪽 {3}%){4}" -f $pad, $dim, $dirText, [int]($Node.Ratio * 100), $reset)
    Show-WsTree -Node $Node.First -Depth ($Depth + 1)
    Show-WsTree -Node $Node.Second -Depth ($Depth + 1)
}

function Show-WsSnapshot {
    # fnc-ignore
    # 스냅샷 하나를 나무 모양으로 보여준다. (ws show)
    param([string]$Name)

    $file = Join-Path $global:ws_store_dir ("{0}.json" -f $Name)

    if (-not (Test-Path -LiteralPath $file)) {
        Write-Error ("스냅샷을 찾지 못했습니다: {0}" -f $Name)
        return
    }

    $snapshot = Get-Content -LiteralPath $file -Raw -Encoding utf8 | ConvertFrom-Json
    $esc = [char]27
    $head = "$esc[1;38;2;231;111;81m"
    $sub = "$esc[38;5;245m"

    $panes = 0
    foreach ($tab in $snapshot.Tabs) { $panes += @(Get-WsLeafPanes -Node $tab.Layout).Count }

    Write-Host ("{0}workspace:$esc[0m {1}{2}$esc[0m  {0}(탭 {3} · pane {4} · {5}){6}" -f
        $sub, $head, $snapshot.Name, $snapshot.Tabs.Count, $panes, $snapshot.SavedAt, "$esc[0m")

    if ($snapshot.Memo) { Write-Host ("  {0}메모: {1}$esc[0m" -f $sub, $snapshot.Memo) }

    if ($snapshot.Window) {
        $geo = if ($snapshot.Window.Maximized) { '최대화' }
            else { "{0}x{1} 글자 · 위치 {2},{3}" -f $snapshot.Window.Cols, $snapshot.Window.Rows, $snapshot.Window.X, $snapshot.Window.Y }

        Write-Host ("  {0}창: {1}$esc[0m" -f $sub, $geo)
    }

    for ($i = 0; $i -lt $snapshot.Tabs.Count; $i++) {
        $tab = $snapshot.Tabs[$i]
        $color = if ($tab.Color) { "  {0}" -f $tab.Color } else { '' }
        Write-Host ("  탭[{0}] {1}{2}" -f $i, $tab.Title, $color) -ForegroundColor Cyan
        Show-WsTree -Node $tab.Layout -Depth 2
    }
}

function New-WsPaneInitScript {
    # fnc-ignore
    # 복원한 pane이 프로필을 읽은 뒤 실행할 초기화 스크립트를 만든다. (실행 후 스스로 지운다 - dup과 같은 방식)
    param([object]$Pane, [string]$Snapshot)

    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($nm in 'SV', 'SVID', 'SVIP', 'SVDIR', 'DST', 'DSTID', 'DSTIP') {
        $value = [string]$Pane.$nm
        if ($value) { $lines.Add(("`$global:{0} = '{1}'" -f $nm, ($value -replace "'", "''"))) }
    }

    foreach ($nm in 'SVPORT', 'DSTPORT') {
        $value = [string]$Pane.$nm
        if ($value) { $lines.Add(("`$global:{0} = {1}" -f $nm, [int]$value)) }
    }

    # 프롬프트(oh-my-posh)가 읽는 환경변수도 같이 맞춘다.
    foreach ($pair in @(@('OMP_SV', 'SV'), @('OMP_SVID', 'SVID'), @('OMP_SVIP', 'SVIP'), @('OMP_SVPORT', 'SVPORT'),
            @('OMP_SVDIR', 'SVDIR'), @('OMP_DST', 'DST'), @('OMP_DSTID', 'DSTID'), @('OMP_DSTIP', 'DSTIP'), @('OMP_DSTPORT', 'DSTPORT'))) {
        $value = [string]$Pane.($pair[1])
        if ($value) { $lines.Add(("`$env:{0} = '{1}'" -f $pair[0], ($value -replace "'", "''"))) }
    }

    if ($Pane.Title) {
        $lines.Add(("`$env:OMP_TITLE = '{0}'" -f ([string]$Pane.Title -replace "'", "''")))
        $lines.Add('Write-TabTitleSequence $env:OMP_TITLE')
    }

    if ($Pane.TabColor) {
        $lines.Add(("`$env:OMP_TABCOLOR = '{0}'" -f ([string]$Pane.TabColor -replace "'", "''")))
        $lines.Add('Write-TabColorSequence $env:OMP_TABCOLOR')
    }

    # 실행 중이던 명령은 스냅샷(ws show)에만 남긴다. 새 세션의 히스토리에 밀어 넣는 방법은
    # 프로필이 올라오기 전이라 동작하지 않아서 안내도 하지 않는다.
    $lines.Add(("Write-Host 'ws: 작업공간 [{0}] 복원' -ForegroundColor DarkCyan" -f ($Snapshot -replace "'", "''")))
    $lines.Add('Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue')

    $path = Join-Path ([IO.Path]::GetTempPath()) ("ws_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $path -Value $lines -Encoding utf8BOM
    $path
}

function Add-WsSplitArgs {
    # fnc-ignore
    # 분할 트리를 wt 인자로 펼친다. 분할할 때마다 대상 pane을 focus-pane으로 지정해 순서가 어긋나지 않게 한다.
    param([object]$Node, [int]$PaneId, [object]$Context)

    if ($Node.Kind -ne 'split') { return }

    $Context.Counter++
    $newId = $Context.Counter

    # 새로 만드는 pane에는 뒤쪽(Second) 가지의 첫 pane이 들어간다.
    $leaf = @(Get-WsLeafPanes -Node $Node.Second)[0]
    $init = New-WsPaneInitScript -Pane $leaf -Snapshot $Context.Snapshot
    $Context.Scripts.Add($init)

    $ratio = [Math]::Min(0.95, [Math]::Max(0.05, [double]$Node.Ratio))
    $cwd = if ($leaf.Cwd -and (Test-Path -LiteralPath $leaf.Cwd)) { [string]$leaf.Cwd } else { $HOME }

    $Context.Args.AddRange([string[]]@(
            ';', 'focus-pane', '-t', ([string]$PaneId),
            ';', 'split-pane', ("-{0}" -f $Node.Dir), '-s', $ratio.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture),
            '-d', $cwd, $Context.Shell, '-NoExit', '-File', $init
        ))

    Add-WsSplitArgs -Node $Node.First -PaneId $PaneId -Context $Context
    Add-WsSplitArgs -Node $Node.Second -PaneId $newId -Context $Context
}

function Restore-WsSnapshot {
    # fnc-ignore
    # 스냅샷대로 탭과 분할을 다시 만든다. (ws load)
    param([string]$Name, [switch]$Here)

    $file = Join-Path $global:ws_store_dir ("{0}.json" -f $Name)

    if (-not (Test-Path -LiteralPath $file)) {
        Write-Error ("스냅샷을 찾지 못했습니다: {0}   (목록: ws)" -f $Name)
        return
    }

    if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
        Write-Error "wt(Windows Terminal)를 찾을 수 없습니다."
        return
    }

    $snapshot = Get-Content -LiteralPath $file -Raw -Encoding utf8 | ConvertFrom-Json
    $shell = (Get-Process -Id $PID).Path

    $context = [pscustomobject]@{
        Args     = [System.Collections.Generic.List[string]]::new()
        Scripts  = [System.Collections.Generic.List[string]]::new()
        Counter  = 0
        Shell    = $shell
        Snapshot = [string]$snapshot.Name
    }

    $first = $true

    foreach ($tab in $snapshot.Tabs) {
        $leaf = @(Get-WsLeafPanes -Node $tab.Layout)[0]
        $init = New-WsPaneInitScript -Pane $leaf -Snapshot $snapshot.Name
        $context.Scripts.Add($init)
        $context.Counter = 0

        $cwd = if ($leaf.Cwd -and (Test-Path -LiteralPath $leaf.Cwd)) { [string]$leaf.Cwd } else { $HOME }

        if (-not $first) { $context.Args.Add(';') }
        $first = $false

        # --title/--tabColor로 지정하면 WT가 그 값을 고정해 이후 셸이 보내는 제목·색(tb/tc)이 무시된다.
        # 그래서 제목과 색은 각 pane의 초기화 스크립트가 셸에서 지정하게 둔다.
        $context.Args.AddRange([string[]]@('new-tab', '-d', $cwd, $shell, '-NoExit', '-File', $init))

        Add-WsSplitArgs -Node $tab.Layout -PaneId 0 -Context $context
    }

    # 기본은 새 창이다. -here면 지금 창에 탭으로 붙인다.
    $window = if ($Here) { '0' } else { "ws-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 6) }
    $panes = @($context.Scripts).Count

    Write-Host ("복원: [{0}]  탭 {1} · pane {2}  ->  {3}" -f
        $snapshot.Name, $snapshot.Tabs.Count, $panes, $(if ($Here) { '현재 창에 탭 추가' } else { '새 창' })) -ForegroundColor Green

    # 새 창으로 열 때는 저장해 둔 크기로 먼저 띄우고(--size), 연 뒤에 픽셀 단위로 정확히 맞춘다.
    # (창 옵션은 첫 하위 명령보다 앞에 와야 한다)
    $prefix = @()
    $restoreWindow = (-not $Here -and $snapshot.Window)
    $before = @()

    if ($restoreWindow) {
        if ($snapshot.Window.Maximized) {
            $prefix += '--maximized'
        }
        elseif ([int]$snapshot.Window.Cols -gt 0 -and [int]$snapshot.Window.Rows -gt 0) {
            $prefix += @('--size', ("{0},{1}" -f [int]$snapshot.Window.Cols, [int]$snapshot.Window.Rows))
            $prefix += @('--pos', ("{0},{1}" -f [int]$snapshot.Window.X, [int]$snapshot.Window.Y))
        }

        try { $before = @(Get-WsTerminalWindowHandles) } catch { $before = @() }
    }

    # 인자는 splat으로 넘긴다 - 배열을 그대로 넘기면 한 덩어리로 전달될 수 있다 (dup과 같은 방식).
    $wtArgs = @($prefix) + @($context.Args)
    & wt -w $window @wtArgs

    if ($LASTEXITCODE -ne 0) {
        $context.Scripts | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
        Write-Error ("복원에 실패했습니다 (exit code: {0})" -f $LASTEXITCODE)
        return
    }

    if (-not $restoreWindow) { return }

    # 새로 열린 창을 찾아 저장해 둔 크기·위치에 그대로 맞춘다.
    $deadline = (Get-Date).AddSeconds(6)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300

        $new = @(Get-WsTerminalWindowHandles | Where-Object { $before -notcontains $_ })
        if ($new.Count -eq 0) { continue }

        try { Set-WsWindowPlacement -Handle $new[0] -Window $snapshot.Window }
        catch { Write-Warning ("창 크기·위치를 맞추지 못했습니다: {0}" -f $_.Exception.Message) }

        break
    }
}

function Get-WsSnapshotList {
    # fnc-ignore
    # 저장된 스냅샷 목록을 읽는다.
    if (-not [IO.Directory]::Exists($global:ws_store_dir)) { return @() }

    foreach ($file in @(Get-ChildItem -LiteralPath $global:ws_store_dir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            $snapshot = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $panes = 0
            foreach ($tab in $snapshot.Tabs) { $panes += @(Get-WsLeafPanes -Node $tab.Layout).Count }

            [pscustomobject]@{
                Name    = [string]$snapshot.Name
                Tabs    = @($snapshot.Tabs).Count
                Panes   = $panes
                SavedAt = [string]$snapshot.SavedAt
                Memo    = [string]$snapshot.Memo
            }
        }
        catch {
            [pscustomobject]@{ Name = $file.BaseName; Tabs = 0; Panes = 0; SavedAt = '읽기 실패'; Memo = '' }
        }
    }
}

function ws {
    # 터미널 작업공간(탭 순서·분할·각 pane의 SV/경로)을 저장하고 그대로 다시 연다. (ws / ws save 이름 / ws show 이름 / ws load 이름 [-here] / ws rm 이름 / ws rename 이전 새이름)
    param(
        [Parameter(Position = 0)][string]$Action,
        [Parameter(Position = 1)][string]$Name,
        [Parameter(Position = 2)][string]$NewName,
        [Alias('m')][string]$Memo,
        [Alias('f')][switch]$Force,
        [Alias('y')][switch]$Yes,
        [switch]$Here
    )

    $esc = [char]27
    $sub = "$esc[38;5;245m"

    if (-not $Action -or $Action -in 'list', 'ls') {
        $items = @(Get-WsSnapshotList)

        if ($items.Count -eq 0) {
            Write-Host "저장된 작업공간이 없습니다." -ForegroundColor Yellow
            Write-Host ("  {0}새 탭에서 ws save <이름> 으로 저장합니다.$esc[0m" -f $sub)
            return
        }

        Write-Host ("{0}workspace:$esc[0m {1}개  {0}({2})$esc[0m" -f $sub, $items.Count, $global:ws_store_dir)

        foreach ($item in $items) {
            Write-Host ("  {0,-16}" -f $item.Name) -NoNewline -ForegroundColor Green
            Write-Host ("탭 {0} · pane {1}   {2}{3}" -f $item.Tabs, $item.Panes, $sub, $item.SavedAt) -NoNewline
            Write-Host ("{0}  {1}$esc[0m" -f $sub, $item.Memo)
        }

        return
    }

    switch -Regex ($Action) {
        '^(save|s)$' {
            if (-not $Name) { Write-Host "사용법: ws save <이름> [-m 메모] [-f 응답 없는 pane도 저장]" -ForegroundColor Yellow; return }
            Save-WsSnapshot -Name $Name -Memo $Memo -Force:$Force -Yes:$Yes
        }
        '^(load|l)$' {
            if (-not $Name) { Write-Host "사용법: ws load <이름> [-here 현재 창에 탭으로 추가]" -ForegroundColor Yellow; return }
            Restore-WsSnapshot -Name $Name -Here:$Here
        }
        '^(show|view)$' {
            if (-not $Name) { Write-Host "사용법: ws show <이름>" -ForegroundColor Yellow; return }
            Show-WsSnapshot -Name $Name
        }
        '^(rm|remove|del|delete)$' {
            if (-not $Name) { Write-Host "사용법: ws rm <이름>" -ForegroundColor Yellow; return }
            $file = Join-Path $global:ws_store_dir ("{0}.json" -f $Name)

            if (-not (Test-Path -LiteralPath $file)) { Write-Error ("스냅샷을 찾지 못했습니다: {0}" -f $Name); return }

            if (-not $Yes) {
                Write-Host ("[{0}] 스냅샷을 지울까요? " -f $Name) -ForegroundColor Yellow -NoNewline
                if ((Read-Host "(y/N)") -notmatch '^(y|yes)$') { Write-Host "취소했습니다." -ForegroundColor DarkGray; return }
            }

            Remove-Item -LiteralPath $file -Force
            Write-Host ("지웠습니다: {0}" -f $Name) -ForegroundColor Green
        }
        '^(rename|mv)$' {
            if (-not $Name -or -not $NewName) { Write-Host "사용법: ws rename <이전이름> <새이름>" -ForegroundColor Yellow; return }

            $file = Join-Path $global:ws_store_dir ("{0}.json" -f $Name)
            $target = Join-Path $global:ws_store_dir ("{0}.json" -f $NewName)

            if (-not (Test-Path -LiteralPath $file)) { Write-Error ("스냅샷을 찾지 못했습니다: {0}" -f $Name); return }
            if (Test-Path -LiteralPath $target) { Write-Error ("이미 있는 이름입니다: {0}" -f $NewName); return }

            $snapshot = Get-Content -LiteralPath $file -Raw -Encoding utf8 | ConvertFrom-Json
            $snapshot.Name = $NewName
            $snapshot | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $target -Encoding utf8
            Remove-Item -LiteralPath $file -Force
            Write-Host ("이름을 바꿨습니다: {0} -> {1}" -f $Name, $NewName) -ForegroundColor Green
        }
        default {
            Write-Host "사용법: ws [list] | ws save <이름> [-m 메모] [-f] | ws show <이름> | ws load <이름> [-here] | ws rm <이름> | ws rename <이전> <새이름>" -ForegroundColor Yellow
        }
    }
}

# ws 자동완성: 동작 이름과 저장된 스냅샷 이름을 후보로 보여준다.
Register-ArgumentCompleter -CommandName ws -ParameterName Action -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    foreach ($action in 'save', 'load', 'show', 'list', 'rm', 'rename') {
        if ($action -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($action, $action, 'ParameterValue', $action)
        }
    }
}

Register-ArgumentCompleter -CommandName ws -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if (-not (Get-Command Get-WsSnapshotList -ErrorAction SilentlyContinue)) { return }

    foreach ($item in @(Get-WsSnapshotList)) {
        if ($item.Name -like "$wordToComplete*") {
            $text = if ($item.Name -match '\s') { "'{0}'" -f $item.Name } else { $item.Name }
            [System.Management.Automation.CompletionResult]::new($text, $item.Name, 'ParameterValue',
                ("탭 {0} · pane {1} · {2}" -f $item.Tabs, $item.Panes, $item.SavedAt))
        }
    }
}

# 이 pane도 스냅샷 요청에 답할 수 있게 감시기를 건다 (WT 안에서만).
Register-WsPaneAgent

#########################################################
# 터미널 작업공간 스냅샷 (ws) 영역 End
#########################################################
