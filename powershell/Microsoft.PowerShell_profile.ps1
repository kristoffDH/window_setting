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
    # profile.ps1(CurrentUserAllHosts 로더)과 자동 로드 폴더($my_scripts_dir)의 스크립트도 백업한다.
    cp $profile.CurrentUserAllHosts ./powershell/
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
# SCP 파일 전송 / 원격 조회 (up/dn/rr/rl) 영역 Start
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

function rl # ls remote ($SV), 경로 생략 시 $SVDIR 목록, -로 시작하는 인자는 원격 ls 옵션으로 전달
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
    $color = if ($MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength) { '--color=never' } else { '--color=always' }
    $remoteCmd = (@('ls', '-alh', $color) + $options + $quoted) -join ' '

    Write-Host ("list: {0}:{1} ({2}:{3})" -f $global:SV, ($shown -join ' '), $global:SVIP, $global:SVPORT) -ForegroundColor Green

    # config의 Host * RemoteCommand와 충돌하지 않게 무효화하고, 한글 파일명이 깨지지 않게 조회 중에만 UTF-8로 받는다.
    $prevEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        & ssh -o BatchMode=yes -o ConnectTimeout=5 -o RemoteCommand=none -o RequestTTY=no -p $global:SVPORT $global:SV $remoteCmd
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error ("원격 목록 조회 실패 (exit code: {0})" -f $LASTEXITCODE)
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

#########################################################
# SCP 파일 전송 / 원격 조회 (up/dn/rr/rl) 영역 End
#########################################################


#########################################################
# ssh 원격 관리 도움말 영역 Start
#########################################################
# 위 SSH/SCP 영역의 원격 명령(ss/sd/sb/xs/xd/c/auth/sw/xw/rl/up/dn/rr)을 사용 흐름 순서로 정리한 가이드.
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
    Add-Cmd "p [대상]"         "ping 상태 감시 (= ping-watch, 대상을 생략하면 SVIP)"
    Add-Note "한 줄에서 갱신되고 상태가 바뀔 때만 기록이 남는다 (재부팅 확인용)"
    Add-Note "대상에 IP나 호스트명을 직접 줄 수 있다. -i 간격(초) -c 횟수, 종료는 Ctrl+C"
    Add-Cmd "ping-test"        "선택된 SVIP로 계속 ping (출력이 쌓이는 예전 방식)"
    Add-Cmd "d [-r|-l|-u|-d|-g]" "현재 세션을 화면 분할로 복제 (= dup, 기본 -r 우측)"
    Add-Note "-g: 2x2 4분할 (세로 분할 후 양쪽을 가로 분할, 포커스는 원래 pane)"
    Add-Note "새 pane이 SV/DST/SVDIR 선택 상태를 그대로 이어받는다"
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
    Add-Cmd "rl [경로] [옵션]"  "SV의 원격 목록을 ls -alh로 표시 (경로를 생략하면 SVDIR)"
    Add-Note "Tab: SVDIR 안의 파일/디렉터리 후보"
    Add-Note "- 로 시작하는 인자는 ls 옵션: rl logs -t (최신순), rl -S (크기순)"
    Add-Note "rl '*.log' 처럼 와일드카드도 가능 (서버 셸이 펼친다)"

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

    # ── 6. 문제 해결 ─────────────────────────────────────────────
    Add-Title "[ 6. 자주 겪는 문제 ]"
    Add-Cmd "자동완성이 로컬 경로" "SV 미선택이거나 키 인증이 안 된 상태 - ss 후 auth 실행"
    Add-Cmd "변수 미설정 안내"    "up/dn/rl은 ss가, rr은 ss + sd가 모두 필요하다"
    Add-Cmd "호스트 키 경고"     "REMOTE HOST IDENTIFICATION HAS CHANGED - auth가 자동 정리한다"
    Add-Note "수동으로 지우려면 del-host <IP> (known_hosts 자동 백업 후 해당 항목 삭제)"
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
