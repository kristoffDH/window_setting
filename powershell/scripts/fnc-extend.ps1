#########################################################
# fnc 확장: 외부 스크립트 폴더 함수 목록 추가 출력
#########################################################
# $PROFILE의 fnc는 $PROFILE만 파싱하므로, 이 폴더의 함수까지 이어서 보여주는
# 확장 함수(fnc-all)를 정의하고 alias로 fnc를 가로챈다.
#
# 동작 원리: 이 폴더의 스크립트는 profile.ps1(CurrentUserAllHosts)에서 로드되어
# $PROFILE보다 먼저 실행된다. 함수 fnc를 재정의하면 $PROFILE이 다시 덮어쓰지만,
# PowerShell은 alias를 함수보다 우선 해석하므로 alias fnc -> fnc-all은 유지된다.
# 원본 fnc 함수는 Get-Command -CommandType Function으로 호출 시점에 찾아 실행한다.

function fnc-all {
    # fnc-ignore
    # $PROFILE의 fnc 출력 뒤에 외부 스크립트 폴더의 함수 목록을 이어서 출력한다. (fnc <함수명>: 해당 함수만 표시)
    param([string]$Name)

    $core = Get-Command -Name fnc -CommandType Function -ErrorAction SilentlyContinue

    $dir = 'C:\CorePlatform\99. pwsh script'
    if (-not [System.IO.Directory]::Exists($dir)) {
        if ($core) { & $core @PSBoundParameters }
        return
    }

    $items = foreach ($file in [System.IO.Directory]::GetFiles($dir, '*.ps1')) {
        if (-not $file.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)

        if ($errors.Count -gt 0) {
            continue
        }

        $comments = @($tokens | Where-Object {
            $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment
        })

        # 최상위 함수만 나열한다(중첩 스크립트블록 내부 헬퍼 제외).
        foreach ($func in $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $false)) {
            $start = $func.Extent.StartOffset
            $body = $func.Body

            # 본문에서 코드가 시작되는 지점(param 블록 또는 첫 문장)을 찾는다.
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
                $func.Extent.EndOffset
            }

            # 함수 선언 줄 끝의 주석 또는 본문 첫 코드 앞의 첫 주석을 설명으로 사용한다.
            $head = $comments | Where-Object {
                $_.Extent.StartOffset -ge $start -and
                $_.Extent.EndOffset -le $firstCode
            } | Select-Object -First 1

            $text = if ($head) { ($head.Text -replace '^#+\s*', '').Trim() } else { '' }

            if ($text -match '(?i)^fnc-ignore\b') {
                continue
            }

            [pscustomobject]@{
                File        = [System.IO.Path]::GetFileName($file)
                Name        = $func.Name
                Description = $text
            }
        }
    }

    $items = @($items)

    # 이름이 지정되면: 이 폴더의 함수는 여기서 단독 표시하고, $PROFILE 함수는 원본 fnc에 위임한다.
    # 어느 쪽에도 없으면 원본 fnc가 에러+전체 목록을 출력하므로 외부 목록도 이어 붙인다.
    $showCore = $true
    if ($Name) {
        $matched = @($items | Where-Object { $_.Name -eq $Name })
        if ($matched.Count -gt 0) {
            $items = $matched
            $showCore = $false
        }
        else {
            $errCountBefore = $Error.Count
            if ($core) {
                & $core -Name $Name
            }
            else {
                Write-Error "'$Name' 함수 이름이 없습니다. 전체 목록을 출력합니다."
            }
            # 에러가 없었다면 원본 fnc가 해당 함수를 단독 표시한 것이므로 여기서 끝낸다.
            if ($Error.Count -eq $errCountBefore) {
                return
            }
            $showCore = $false
        }
    }

    if ($showCore -and $core) {
        & $core
    }

    if ($items.Count -eq 0) {
        return
    }

    Write-Host ""
    Write-Host ("Functions in {0} ({1})" -f [System.IO.Path]::GetFileName($dir), $items.Count) -ForegroundColor Cyan

    $nameWidth = ($items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum

    $index = 1
    $currentFile = $null

    foreach ($item in $items) {
        # 파일별로 묶어 파일명을 배너로 표시한다.
        if ($item.File -ne $currentFile) {
            $currentFile = $item.File
            Write-Host ""
            Write-Host ("[ {0} ]" -f $currentFile) -ForegroundColor Yellow
        }

        Write-Host ("{0,2}. {1}" -f $index, $item.Name.PadRight($nameWidth)) -NoNewline
        if ($item.Description) {
            Write-Host ("  # {0}" -f $item.Description) -ForegroundColor Gray
        }
        else {
            Write-Host ""
        }
        $index++
    }
}

# alias는 함수보다 우선 해석되므로, $PROFILE이 함수 fnc를 정의해도 이 alias가 이긴다.
Set-Alias -Name fnc -Value fnc-all
