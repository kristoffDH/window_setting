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
Set-Alias -Name cn -Value ssh-con

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
    # OMP_TAG를 갱신하고 oh-my-posh 설정을 다시 읽어 프롬프트를 새로고침한다.
    Update-OmpTag
    oh-my-posh init pwsh --config "$HOME\.mytheme.omp.json" | Invoke-Expression
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
        @{ Name = "brightPurple";        Hex = "#FF2740" },
        @{ Name = "brightRed";           Hex = "#FF2740" },
        @{ Name = "brightWhite";         Hex = "#FFFFFF" },
        @{ Name = "brightYellow";        Hex = "#FFD242" },
        @{ Name = "cursorColor";         Hex = "#D41919" },
        @{ Name = "cyan";                Hex = "#00D8EB" },
        @{ Name = "foreground";          Hex = "#FFFFFF" },
        @{ Name = "green";               Hex = "#1A921C" },
        @{ Name = "purple";              Hex = "#FF000F" },
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

    foreach ($suffix in '', 'ID', 'IP', 'PORT') {
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
    # alias-fn: 원본 서버(SV)를 선택한다. (= set-sshhost, 접속은 cn)
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

# ss/sd/set-sshhost 별칭 자동완성: ssh config의 Host 목록을 후보로 보여준다. (config 파싱만, 네트워크 조회 없음)
Register-ArgumentCompleter -CommandName ss, sd, Set-SshHost -ParameterName Alias -ScriptBlock {
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

function ssh-con {
    # 선택된 $SV 서버에 ssh로 접속한다. (alias: cn)
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
    # 선택된 $SVIP로 ping을 계속 보낸다. (축약: p)
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

function p {
    # alias-fn: 선택된 $SVIP로 ping을 계속 보낸다. (= ping-test)
    ping-test @args
}

function auth
{
    # 서버에 SSH 공개키를 등록해 비밀번호 없이 접속하도록 설정한다.
    param(
        [Parameter(Position = 0)]
        [string]$Target,

        [Parameter(Position = 1)]
        [int]$Port = 0
    )

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
        Write-Host "사용법: auth 계정@서버IP [포트]  (sss로 서버를 선택했다면 auth 만 입력)" -ForegroundColor Yellow
        return
    }

    $sshDir = Join-Path $HOME '.ssh'
    $pubKeys = @(Get-ChildItem -Path (Join-Path $sshDir '*.pub') -File -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath ($_.FullName -replace '\.pub$', '') })

    # 1) 로컬 키 중 하나라도 이미 등록되어 있으면 바로 종료
    foreach ($pub in $pubKeys) {
        $priv = $pub.FullName -replace '\.pub$', ''
        & ssh @portArgs -i $priv -o IdentitiesOnly=yes -o BatchMode=yes -o PasswordAuthentication=no -o ConnectTimeout=5 $dest exit 2>$null
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
    Get-Content -LiteralPath $pubKeyPath -TotalCount 1 | & ssh @portArgs $dest $remoteCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error ("공개키 등록에 실패했습니다 (exit code: {0})" -f $LASTEXITCODE)
        return
    }

    # 4) 등록한 키로 실제 접속되는지 확인
    $privKeyPath = $pubKeyPath -replace '\.pub$', ''
    & ssh @portArgs -i $privKeyPath -o IdentitiesOnly=yes -o BatchMode=yes -o PasswordAuthentication=no -o ConnectTimeout=5 $dest exit 2>$null
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
# SCP 파일 전송 (up/dn/rr) 영역 Start
#########################################################

function Test-ScpReady {
    # fnc-ignore
    # up/dn/rr 실행 전 scp 존재 여부와 $SV 계열(-RequireDst면 $DST 계열까지) 설정 여부를 확인한다.
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

function up # scp local -> remote ($SV), 와일드카드(*.tar 등) 지원
{
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$LocalPath,

        [Parameter(Position = 1)]
        [string]$RemotePath = '~/'
    )

    if (-not (Test-ScpReady)) { return }

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

        & ssh -o BatchMode=yes -o ConnectTimeout=3 -p $global:SVPORT $global:SV $remoteTest 2>$null
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

        & ssh -o BatchMode=yes -o ConnectTimeout=3 -p $global:SVPORT $global:SV $remoteTest 2>$null
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

# up/dn/rr 원격 경로 자동완성 공용: Tab을 누를 때마다 ssh로 원격 디렉터리 목록을 조회한다. (캐시 없음)
function Get-SshRemotePathCompletion {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostAlias,

        [Parameter(Mandatory = $true)]
        [string]$Port,

        [string]$WordToComplete = '',

        [switch]$DirOnly
    )

    $word = $WordToComplete.Trim("'`"")

    # 입력값을 "디렉터리 부분 + 이름 접두어"로 분리
    $slash = $word.LastIndexOf('/')
    $dir = if ($slash -ge 0) { $word.Substring(0, $slash + 1) } else { '' }
    $prefix = if ($slash -ge 0) { $word.Substring($slash + 1) } else { $word }

    # 디렉터리 미지정이면 원격 홈, ~/ 시작이면 원격 $HOME으로 치환해서 조회한다.
    # ($HOME은 원격 셸에서 확장되어야 하므로 PS에서는 리터럴로 유지)
    if ([string]::IsNullOrEmpty($dir)) {
        $remoteCmd = 'ls -1ap'
    }
    elseif ($dir.StartsWith('~/')) {
        $remoteCmd = 'ls -1ap -- "$HOME/' + $dir.Substring(2) + '"'
    }
    else {
        $remoteCmd = 'ls -1ap -- "' + $dir + '"'
    }

    $items = & ssh -o BatchMode=yes -o ConnectTimeout=3 -p $Port $HostAlias "$remoteCmd 2>/dev/null" 2>$null

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

    Get-SshRemotePathCompletion -HostAlias $sv.Value -Port ([string]$svport.Value) -WordToComplete $wordToComplete -DirOnly:($commandName -eq 'up')
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

    Get-SshRemotePathCompletion -HostAlias $sv.Value -Port ([string]$svport.Value) -WordToComplete $wordToComplete
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

#########################################################
# SCP 파일 전송 (up/dn/rr) 영역 End
#########################################################


#########################################################
# 터미널 세션 복제 (dup) 영역 Start
#########################################################

function dup # 현재 세션($SV, 작업 경로)을 복제해 화면 분할 (-r 우측 | -l 좌측 | -u 상단 | -d 하단, 기본 -r)
{
    param(
        [Alias('r')][switch]$Right,
        [Alias('l')][switch]$Left,
        [Alias('u')][switch]$Up,
        [Alias('d')][switch]$Down
    )

    if (@($Right, $Left, $Up, $Down).Where({ $_ }).Count -gt 1) {
        Write-Host "사용법: dup [-r|-l|-u|-d]  (방향은 하나만, 생략하면 -r 우측)" -ForegroundColor Yellow
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
    foreach ($name in 'SV', 'SVID', 'SVIP', 'DST', 'DSTID', 'DSTIP') {
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
    foreach ($name in 'OMP_SV', 'OMP_SVID', 'OMP_SVIP', 'OMP_SVPORT', 'OMP_DST', 'OMP_DSTID', 'OMP_DSTIP', 'OMP_DSTPORT') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) {
            $lines.Add(("`$env:{0} = '{1}'" -f $name, ($value -replace "'", "''")))
        }
    }
    if ($global:SV) {
        $lines.Add(("Write-Host 'dup: `$SV={0} 세션을 복제했습니다.' -ForegroundColor DarkCyan" -f ([string]$global:SV -replace "'", "''")))
    }
    $lines.Add('Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue')

    $initPath = Join-Path ([IO.Path]::GetTempPath()) ("dup_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $initPath -Value $lines -Encoding utf8BOM

    # 새 pane은 현재와 같은 쉘 실행 파일, 같은 작업 경로로 시작한다.
    $cwd = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath } else { $HOME }
    $shell = (Get-Process -Id $PID).Path

    # wt split-pane은 새 pane을 우측(-V)/하단(-H)에만 만들 수 있으므로,
    # 좌측/상단은 분할 직후 swap-pane으로 기존 pane과 자리를 맞바꿔 구현한다.
    $splitDir = if ($Up -or $Down) { '-H' } else { '-V' }
    $swapArgs = @()
    if ($Left) { $swapArgs = @(';', 'swap-pane', 'left') }
    elseif ($Up) { $swapArgs = @(';', 'swap-pane', 'up') }

    & wt -w 0 split-pane $splitDir -d $cwd $shell -NoExit -File $initPath @swapArgs
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $initPath -Force -ErrorAction SilentlyContinue
        Write-Error ("pane 분할에 실패했습니다 (exit code: {0})" -f $LASTEXITCODE)
    }
}

function d {
    # alias-fn: 현재 세션을 복제해 화면 분할한다. (= dup, -r/-l/-u/-d 인자 그대로 전달)
    dup @args
}

#########################################################
# 터미널 세션 복제 (dup) 영역 End
#########################################################
