
# oh-my-posh module
oh-my-posh init pwsh --config $HOME/.mytheme.omp.json | Invoke-Expression

# setting env path

# Alias 
Set-Alias ls lsd
Set-Alias vi vim

# config path setting
$omp_config_file = "$env:HOMEPATH/.mytheme.omp.json"
$history_backup_file_path = "$env:APPDATA/Microsoft/Windows/PowerShell/PSReadLine"

# PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView

Invoke-Expression (& { (zoxide init powershell | Out-String) })

Set-Alias zz zi

Set-PSReadLineOption -Colors @{ Parameter = 'Cyan' }
Set-PSReadLineOption -Colors @{ Operator = 'Cyan' }

$env:OMP_TAG = "IP : 10.10.70.52"

$env:OMP_LINK1_PATH = "C:\Users\Hanssak"
$env:OMP_LINK1_NAME = "Home"
$env:OMP_LINK2_PATH = "C:\Users\Hanssak\Downloads"
$env:OMP_LINK2_NAME = "Downloads"
$env:OMP_LINK3_PATH = "C:\Users\Hanssak\Desktop"
$env:OMP_LINK3_NAME = "Desktop"
$env:OMP_LINK4_PATH = "C:\hanssak"
$env:OMP_LINK4_NAME = "hanssak"

##########################################################################################
# function list
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

function code-hist # open powershell history 
{
    code "$history_backup_file_path/ConsoleHost_history.txt"
}

function del-hist # delete powershell history
{
    rm "$history_backup_file_path/ConsoleHost_history.txt"
}

function open-hist
{
    code "$history_backup_file_path/ConsoleHost_history.txt"
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

function fnc # get function list in $profile
{
    cat $PROFILE | Select-string -Pattern "^function*" -NoEmphasis
}

function down  # change directory downloads
{ 
    cd $Home/Downloads
}

function ssh-config
{
    code $Home/.ssh/config
}

function layout-config
{
    code C:/hanssak/powershell_script\ssh-layout
}

function reload {
    oh-my-posh init pwsh --config "$HOME\.mytheme.omp.json" | Invoke-Expression
}


############################################################################################

function Show-MyPalette {
    $esc = [char]27

    function Convert-HexToRgb {
        param([string]$Hex)
        $h = $Hex.Trim()
        if ($h.StartsWith('#')) { $h = $h.Substring(1) }
        [int]$r = [Convert]::ToInt32($h.Substring(0,2),16)
        [int]$g = [Convert]::ToInt32($h.Substring(2,2),16)
        [int]$b = [Convert]::ToInt32($h.Substring(4,2),16)
        return [pscustomobject]@{ R = $r; G = $g; B = $b }
    }

    function Convert-RgbToHex {
        param([int]$R, [int]$G, [int]$B)
        return ('#{0:X2}{1:X2}{2:X2}' -f $R,$G,$B)
    }

    function New-Tone {
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
