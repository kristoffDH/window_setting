
# oh-my-posh module
oh-my-posh init pwsh --config $HOME/.mytheme.omp.json | Invoke-Expression

# setting env path

# Alias 
Set-Alias ls lsd
Set-Alias vi vim
Set-Alias grep findstr

# config path setting
$omp_config_file = "$env:HOMEPATH/.mytheme.omp.json"
$history_backup_file_path = "$env:APPDATA/Microsoft/Windows/PowerShell/PSReadLine"

# PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView

Invoke-Expression (& { (zoxide init powershell | Out-String) })

Set-Alias zz zi

Set-PSReadLineOption -Colors @{ Parameter = '#7E8BA3' }
Set-PSReadLineOption -Colors @{ Operator = '#7E8BA3' }

$env:OMP_TAG = "IP : 10.10.70.52"

$env:OMP_LINK1_PATH = "C:\Users\Hanssak"
$env:OMP_LINK1_NAME = "Home"
$env:OMP_LINK2_PATH = "C:\Users\Hanssak\Downloads"
$env:OMP_LINK2_NAME = "Downloads"
$env:OMP_LINK3_PATH = "C:\Users\Hanssak\Desktop"
$env:OMP_LINK3_NAME = "Desktop"
$env:OMP_LINK4_PATH = "C:\CorePlatform"
$env:OMP_LINK4_NAME = "CorePlatform"
$env:OMP_LINK5_PATH = "Z:\주간보고\CORE센터_CORE플랫폼팀\2026년\김대호"
$env:OMP_LINK5_NAME = "주간보고"

#############################################################################
# function
#############################################################################

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
    code $env:HOMEPATH/.mytheme.omp.json
}

function rsa-pubkey # show ssh rsa-public key
{
    cat $env:HOMEPATH/.ssh/id_rsa.pub
}

function open-his
{
    code "$history_backup_file_path/ConsoleHost_history.txt"
}

function del-his {
    $path = "$history_backup_file_path/ConsoleHost_history.txt"

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
    Write-Host ("backup: {0}.bak" -f $path) -ForegroundColor DarkGray
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

function ssh-config
{
    code $Home/.ssh/config
}

function reload {
    oh-my-posh init pwsh --config "$HOME\.mytheme.omp.json" | Invoke-Expression
}

############################################################################################

function Show-MyPalette {
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

    # 3) 추천 추가 색상들 (+ 이전 extra + 추가 10개)
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

        @{ Name = "softBg";        Hex = "#252733" },  # 약간 푸른기 도는 다크 배경
        @{ Name = "softBgAlt";     Hex = "#2B3040" },  # 서브 패널 배경용
        @{ Name = "panelBorder";   Hex = "#4B5563" },  # 경계선/구분선
        @{ Name = "lineHighlight"; Hex = "#31364A" },  # 선택/하이라이트 라인

        @{ Name = "statusGreen";   Hex = "#3DD68C" },  # 성공/OK 상태
        @{ Name = "statusYellow";  Hex = "#F6C453" },  # 경고/주의
        @{ Name = "statusRed";     Hex = "#F75C7E" },  # 에러/위험
        @{ Name = "statusBlue";    Hex = "#2F9BFF" },  # 정보/알림

        @{ Name = "tagPink";       Hex = "#FF8EC7" },  # 관리자 표시용 핑크 계열
        @{ Name = "tagPinkDark";   Hex = "#D75A9C" },  # 핑크 계열 진한 톤
        @{ Name = "royalPurple";   Hex = "#6C4AB6" },  # 깊은 보라
        @{ Name = "indigo";        Hex = "#4953C4" },  # 인디고/네이비 사이

        @{ Name = "softCyan";      Hex = "#7FE7FF" },  # 밝은 시안
        @{ Name = "deepCyan";      Hex = "#008B9E" },  # 진한 시안/티얼
        @{ Name = "mint";          Hex = "#9CF6E0" },  # 파스텔 민트
        @{ Name = "deepMint";      Hex = "#0F9F8C" },  # 딥 민트

        @{ Name = "warningOrange"; Hex = "#FFB347" },  # 경고 강조용 오렌지
        @{ Name = "accentGold";    Hex = "#E9C46A" },  # 포인트용 골드
        @{ Name = "graphLine1";    Hex = "#A3B9FF" },  # 그래프/라인1
        @{ Name = "graphLine2";    Hex = "#89F0FF" },  # 그래프/라인2

        # ───── 추가 색상 10개 ─────
        @{ Name = "softPink";      Hex = "#FFB3D9" },  # 부드러운 핑크
        @{ Name = "deepPink";      Hex = "#E05297" },  # 진한 핑크
        @{ Name = "consoleBgAlt";  Hex = "#1F2430" },  # 아주 어두운 콘솔 배경
        @{ Name = "mutedBlue";     Hex = "#5C7CFA" },  # 살짝 채도 낮은 블루
        @{ Name = "mutedTeal";     Hex = "#3CB9A4" },  # 차분한 틸
        @{ Name = "softLime";      Hex = "#B8F28D" },  # 연한 라임 그린
        @{ Name = "errorBg";       Hex = "#4A1F2F" },  # 에러 라인 배경
        @{ Name = "successBg";     Hex = "#123E3A" },  # 성공 라인 배경
        @{ Name = "infoBg";        Hex = "#102A43" },  # 정보 라인 배경
        @{ Name = "badgeBg";       Hex = "#3D3B5C" }   # 배지/라벨 배경
    )

    Show-ColorRow -Title "Flat Remix base palette" -Colors $baseColors
    Show-ColorRow -Title "Extra matching colors"   -Colors $extraColors

    Write-Host "$esc[0m"
}

function fnc {
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

    $names = foreach ($func in $functions) {
        $start = $func.Extent.StartOffset
        $end   = $func.Extent.EndOffset

        $hasIgnore = $tokens | Where-Object {
            $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment -and
            $_.Extent.StartOffset -ge $start -and
            $_.Extent.EndOffset -le $end -and
            $_.Text -match '(?i)#\s*fnc-ignore\b'
        } | Select-Object -First 1

        if (-not $hasIgnore) {
            $func.Name
        }
    }

    $names = $names | Sort-Object -Unique

    if (-not $names) {
        Write-Host "표시할 함수가 없습니다."
        return
    }

    Write-Host ("Functions in PROFILE ({0})" -f $names.Count) -ForegroundColor Cyan
    Write-Host ""

    $index = 1
    foreach ($name in $names) {
        Write-Host ("{0,2}. {1}" -f $index, $name)
        $index++
    }
}

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
    param(
        [Parameter(Mandatory = $true)]
        [string]$Alias
    )

    $output = & ssh -G $Alias 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $output) {
        return [pscustomobject]@{
            Alias        = $Alias
            HostName     = $Alias
            IP           = ''
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
    $ip = Resolve-HostToIp $hostName

    return [pscustomobject]@{
        Alias        = $Alias
        HostName     = $hostName
        IP           = $ip
        Port         = $port
        User         = $user
        IdentityFile = $identityFile
        ProxyJump    = $proxyJump
    }
}

function Get-SshDetailCached {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [string]$Alias
    )

    $key = $Alias.ToLowerInvariant()

    if (-not $script:SshPickerDetailCache.ContainsKey($key)) {
        $script:SshPickerDetailCache[$key] = Get-SshEffectiveConfig -Alias $Alias
    }

    return $script:SshPickerDetailCache[$key]
}

function Set-SshSelectionVars {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [object]$Entry
    )

    $detail = Get-SshDetailCached -Alias $Entry.Alias

    $global:SV = $Entry.Alias
    $global:SVIP = if ([string]::IsNullOrWhiteSpace($detail.IP)) { $detail.HostName } else { $detail.IP }
    $global:SVPORT = [int]$detail.Port
    $env:OMP_SV = $global:SV

    Show-SshSelectedScreen -Entry $Entry
}

function clear-sv {
    # fnc-ignore
    Remove-Variable SV -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable SVIP -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:OMP_SV -ErrorAction SilentlyContinue

    Write-Host "SV 정보 제거 완료" -ForegroundColor Yellow
}

function Render-SshPicker {
    # fnc-ignore
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Entries,

        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    $detail = Get-SshDetailCached -Alias $Entries[$Index].Alias
    $total = $Entries.Count

    [Console]::Clear()

    Write-Host ("SSH Host Picker  [{0}/{1}]" -f ($Index + 1), $total) -ForegroundColor Cyan
    Write-Host "↑/↓ 이동  Enter 선택  Esc 종료" -ForegroundColor DarkGray
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

    $ipText = if ([string]::IsNullOrWhiteSpace($detail.IP)) { '<DNS 해석 실패>' } else { $detail.IP }

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
        [object]$Entry
    )

    $detail = Get-SshDetailCached -Alias $Entry.Alias

    [Console]::Clear()

    Write-Host "SSH Selected" -ForegroundColor Cyan
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

function Set-SshHost {
    param(
        [Parameter(Position = 0)]
        [string]$Alias,

        [string]$ConfigPath = "$HOME/.ssh/config"
    )

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

        return Set-SshSelectionVars -Entry $matchedEntry
    }

    $index = 0

    while ($true) {
        Render-SshPicker -Entries $entries.ToArray() -Index $index

        $keyInfo = [Console]::ReadKey($true)

        switch ($keyInfo.Key) {
            'UpArrow' {
                if ($index -gt 0) {
                    $index--
                }
            }

            'DownArrow' {
                if ($index -lt ($entries.Count - 1)) {
                    $index++
                }
            }

            'Enter' {
                $selected = $entries[$index]
                return Set-SshSelectionVars -Entry $selected
            }

            'Escape' {
                Write-Host ""
                Write-Host "취소했습니다." -ForegroundColor DarkYellow
                return $null
            }
        }
    }
}

Set-Alias -Name svpick -Value Set-SshHost -Scope Global

function del-host {
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
        Write-Host ("backup: {0}" -f $backup) -ForegroundColor DarkGray
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($knownHosts, $result, $utf8NoBom)

    Write-Host ("삭제 완료: {0}" -f $Ip) -ForegroundColor Green
    Write-Host ("삭제된 항목 수: {0}" -f $removedTokenCount)
    Write-Host ("완전히 제거된 라인 수: {0}" -f $removedLineCount)
    Write-Host ("backup: {0}" -f $backup) -ForegroundColor DarkGray
}

function ssh-con {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if (-not (Get-Command tssh -ErrorAction SilentlyContinue)) {
        Write-Error "tssh 명령을 찾지 못했습니다."
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

    Write-Host ("connecting: tssh {0}" -f $global:SV) -ForegroundColor Green
    & tssh $global:SV @Args
}