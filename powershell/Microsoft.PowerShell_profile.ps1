
# oh-my-posh module
oh-my-posh init pwsh --config $HOME/.mytheme.omp.json | Invoke-Expression

# setting env path

# Alias 
Set-Alias ls lsd
Set-Alias vi nvim
Set-Alias grep findstr
Set-Alias d dup
Set-Alias p ping-test

# config path setting
$omp_config_file = "$env:HOMEPATH/.mytheme.omp.json"
$history_backup_file_path = "$env:APPDATA/Microsoft/Windows/PowerShell/PSReadLine"
$his_file = "$history_backup_file_path/ConsoleHost_history.txt"

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
$env:OMP_LINK5_PATH = ""
$env:OMP_LINK5_NAME = ""

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
    code "$his_file"
}

function del-his {
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

function reload
{
    oh-my-posh init pwsh --config "$HOME\.mytheme.omp.json" | Invoke-Expression
}

function upload_pwsh_cfg
{
    $originalPath = Get-Location
    cd "C:\Users\hanssak\win_term\window_setting\powershell"
    ls;
    git add .; git commit -m "update pwsh function"; git push;
    Set-Location -Path $originalPath
}

############################################################################################

function gs
{
    git status
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

    # 선택한 ssh Host 별칭
    $global:SV = $Entry.Alias
    $global:SVPORT = [int]$detail.Port
    $env:OMP_SV = $global:SV

    # ssh -G 결과의 HostName을 실제 IP로 변환한 값만 SVIP에 저장한다.
    # IP 확인에 실패하면 이전 서버의 SVIP가 남지 않도록 제거한다.
    if ([string]::IsNullOrWhiteSpace($detail.IP)) {
        Remove-Variable SVIP -Scope Global -ErrorAction SilentlyContinue

        Show-SshSelectedScreen -Entry $Entry
        Write-Warning ("원격 IP를 확인하지 못해 `$SVIP를 설정하지 않았습니다. HostName: {0}" -f $detail.HostName)
        return
    }

    $global:SVIP = $detail.IP

    Show-SshSelectedScreen -Entry $Entry
    Write-Host ("변수 설정 완료: `$SV={0}, `$SVIP={1}, `$SVPORT={2}" -f $global:SV, $global:SVIP, $global:SVPORT) -ForegroundColor Green
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
    Write-Host "↑/↓ 이동  Ctrl+↑/↓ 3칸 이동  Enter 선택  Esc 취소" -ForegroundColor DarkGray
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

function Read-SshPickerKey {
    # fnc-ignore
    # sss-picker-v3: Esc 취소 및 Ctrl+Up/Down 3칸 이동 지원
    # 일반 ConsoleKey와 VT 입력(ESC [ A/B, ESC [ 1;5 A/B)을 모두 정규화한다.
    $first = [Console]::ReadKey($true)
    $firstKey = $first.Key.ToString()
    $isCtrl = ($first.Modifiers -band [ConsoleModifiers]::Control) -ne 0

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

        Set-SshSelectionVars -Entry $matchedEntry
        return $true
    }

    $index = 0

    while ($true) {
        Render-SshPicker -Entries $entries.ToArray() -Index $index

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
                Set-SshSelectionVars -Entry $selected
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

function ping-test {
    $svipVar = Get-Variable SVIP -Scope Global -ErrorAction SilentlyContinue

    if (-not $svipVar -or [string]::IsNullOrWhiteSpace($global:SVIP)) {
        Write-Error "SVIP가 설정되어 있지 않습니다. 먼저 svpick으로 서버를 선택해 주세요."
        return
    }

    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($global:SVIP, [ref]$parsedIp)) {
        Write-Error ("SVIP 값이 올바른 IP 형식이 아닙니다: {0}" -f $global:SVIP)
        return
    }

    & ping.exe -t $parsedIp.IPAddressToString
}

function sss {
    # sss-picker-v4: 실행할 때마다 이전 선택값을 제거한다.
    # 새 서버를 선택하지 않으면 기존 SV를 재사용해 연결하지 않는다.
    Remove-Variable SV -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable SVIP -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:OMP_SV -ErrorAction SilentlyContinue

    $selected = Set-SshHost

    if (
        -not $selected -or
        -not (Get-Variable SV -Scope Global -ErrorAction SilentlyContinue) -or
        [string]::IsNullOrWhiteSpace($global:SV)
    ) {
        return
    }

    ssh-con
}

function Test-ScpReady {
    # fnc-ignore
    # up/dn 실행 전 scp 존재 여부와 $SV, $SVIP, $SVPORT 설정 여부를 확인한다.
    if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
        Write-Error "scp 명령을 찾지 못했습니다. OpenSSH Client가 설치되어 있어야 합니다."
        return $false
    }

    foreach ($name in 'SV', 'SVIP', 'SVPORT') {
        $var = Get-Variable $name -Scope Global -ErrorAction SilentlyContinue

        if (-not $var -or [string]::IsNullOrWhiteSpace([string]$var.Value)) {
            Write-Host ("`${0}가 설정되지 않았습니다. 먼저 sss로 서버를 선택해 주세요." -f $name) -ForegroundColor Yellow
            return $false
        }
    }

    return $true
}

function up # scp local -> remote ($SV)
{
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$LocalPath,

        [Parameter(Position = 1)]
        [string]$RemotePath = '~/'
    )

    if (-not (Test-ScpReady)) { return }

    if (-not (Test-Path -LiteralPath $LocalPath)) {
        Write-Error ("로컬 경로를 찾지 못했습니다: {0}" -f $LocalPath)
        return
    }

    $resolved = (Resolve-Path -LiteralPath $LocalPath).Path

    # $SV는 ssh config 별칭이므로 User/IdentityFile은 config에서 가져오고 포트만 명시한다.
    $scpArgs = @('-P', $global:SVPORT)

    if (Test-Path -LiteralPath $resolved -PathType Container) {
        $scpArgs += '-r'
    }

    $target = "{0}:{1}" -f $global:SV, $RemotePath

    Write-Host ("upload: {0} -> {1} ({2}:{3})" -f $resolved, $target, $global:SVIP, $global:SVPORT) -ForegroundColor Green
    & scp @scpArgs $resolved $target

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

    # 원격 경로가 디렉터리일 때만 -r을 붙인다.
    # 자동완성으로 고른 디렉터리는 ls -p 덕분에 끝에 / 가 붙어 있어 ssh 확인 없이 판별되고,
    # / 없이 직접 입력한 경로만 원격에서 test -d 로 확인한다.
    $isDir = $RemotePath.EndsWith('/')

    if (-not $isDir) {
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
        Write-Host "원격 디렉터리로 감지되어 -r 옵션으로 다운로드합니다." -ForegroundColor DarkGray
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

# up/dn 원격 경로 자동완성: Tab을 누를 때마다 ssh로 원격 디렉터리 목록을 조회한다. (캐시 없음)
# up은 업로드 대상이므로 디렉터리만, dn은 파일/디렉터리 모두 후보로 보여준다.
Register-ArgumentCompleter -CommandName up, dn -ParameterName RemotePath -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $sv = Get-Variable SV -Scope Global -ErrorAction SilentlyContinue
    $svport = Get-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue

    if (-not $sv -or [string]::IsNullOrWhiteSpace([string]$sv.Value) -or
        -not $svport -or [string]::IsNullOrWhiteSpace([string]$svport.Value)) {
        return
    }

    $word = $wordToComplete.Trim("'`"")

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

    $items = & ssh -o BatchMode=yes -o ConnectTimeout=3 -p $svport.Value $sv.Value "$remoteCmd 2>/dev/null" 2>$null

    if ($LASTEXITCODE -ne 0 -or -not $items) {
        return
    }

    $dirOnly = ($commandName -eq 'up')

    foreach ($item in $items) {
        if ($item -in './', '../') { continue }
        if ($dirOnly -and -not $item.EndsWith('/')) { continue }
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

function auth
{
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
    Write-Host "서버 접속 비밀번호를 입력해 주세요." -ForegroundColor DarkGray
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
    foreach ($name in 'SV', 'SVIP') {
        $var = Get-Variable $name -Scope Global -ErrorAction SilentlyContinue
        if ($var -and $null -ne $var.Value) {
            $lines.Add(("`$global:{0} = '{1}'" -f $name, ([string]$var.Value -replace "'", "''")))
        }
    }
    $svport = Get-Variable SVPORT -Scope Global -ErrorAction SilentlyContinue
    if ($svport -and $null -ne $svport.Value) {
        $lines.Add(("`$global:SVPORT = {0}" -f [int]$svport.Value))
    }
    if ($env:OMP_SV) {
        $lines.Add(("`$env:OMP_SV = '{0}'" -f ($env:OMP_SV -replace "'", "''")))
    }
    if ($global:SV) {
        $lines.Add(("Write-Host 'dup: `$SV={0} 세션을 복제했습니다.' -ForegroundColor DarkGray" -f ([string]$global:SV -replace "'", "''")))
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
