#########################################################
# vi 도움말 영역 Start
#########################################################

function vi-help {
    # vi(vim) 편집 명령어 가이드를 새 화면에 표시한다. (↑↓/PgUp/PgDn 스크롤, ESC/q/Ctrl+C 닫기)
    $esc = [char]27
    $keyWidth = 12

    # 대체 스크린 버퍼에서 다시 그릴 수 있도록 ANSI 색상을 입힌 문자열 목록으로 내용을 만든다.
    $lines = [System.Collections.Generic.List[string]]::new()

    function Add-ViTitle {
        # fnc-ignore
        param([string]$Text)
        $lines.Add("$esc[93m$Text$esc[0m")
    }

    function Add-ViSection {
        # fnc-ignore
        param([string]$Title)
        $lines.Add('')
        $lines.Add("$esc[36m  --- $Title ---$esc[0m")
    }

    function Add-ViKey {
        # fnc-ignore
        param([string]$Key, [string]$Desc)
        $lines.Add(("  $esc[92m{0}$esc[0m{1}" -f $Key.PadRight($keyWidth), $Desc))
    }

    Add-ViTitle "[ 보기 모드 (Normal 모드) ]  - ESC를 누르면 언제든 이 모드로 돌아온다"

    Add-ViSection "커서 이동"
    Add-ViKey "h j k l"   "좌 / 하 / 상 / 우 이동 (방향키도 가능)"
    Add-ViKey "w / b"     "다음 단어 시작 / 이전 단어 시작으로 이동"
    Add-ViKey "0 / $"     "줄 맨 앞 / 줄 맨 끝으로 이동"
    Add-ViKey "gg / G"    "문서 맨 위 / 문서 맨 아래로 이동"
    Add-ViKey ":<숫자>"   "해당 줄 번호로 이동 (예: :10)"
    Add-ViKey "Ctrl+f/b"  "한 화면 아래 / 위로 스크롤"

    Add-ViSection "검색"
    Add-ViKey "/문자열"   "아래 방향으로 검색"
    Add-ViKey "?문자열"   "위 방향으로 검색"
    Add-ViKey "n / N"     "다음 / 이전 검색 결과로 이동"

    Add-ViSection "삭제"
    Add-ViKey "x"         "커서 위치 글자 삭제"
    Add-ViKey "dd"        "현재 줄 삭제 (잘라내기)"
    Add-ViKey "dw"        "커서부터 단어 끝까지 삭제"
    Add-ViKey "d$"        "커서부터 줄 끝까지 삭제"
    Add-ViKey "<숫자>dd"  "여러 줄 삭제 (예: 3dd = 3줄)"

    Add-ViSection "복사 / 붙여넣기"
    Add-ViKey "yy"        "현재 줄 복사"
    Add-ViKey "<숫자>yy"  "여러 줄 복사 (예: 3yy = 3줄)"
    Add-ViKey "p / P"     "커서 다음 줄 / 이전 줄에 붙여넣기"

    Add-ViSection "실행 취소"
    Add-ViKey "u"         "실행 취소 (undo)"
    Add-ViKey "Ctrl+r"    "다시 실행 (redo)"

    Add-ViSection "저장 / 종료 (: 명령)"
    Add-ViKey ":w"        "저장"
    Add-ViKey ":q"        "종료 (변경 사항 있으면 거부됨)"
    Add-ViKey ":wq"       "저장 후 종료"
    Add-ViKey ":q!"       "저장하지 않고 강제 종료"

    $lines.Add('')
    Add-ViTitle "[ 편집 모드 (Insert 모드) ]  - 아래 키로 진입, ESC로 빠져나온다"

    Add-ViSection "진입 키"
    Add-ViKey "i / a"     "커서 앞 / 커서 뒤에서 입력 시작"
    Add-ViKey "I / A"     "줄 맨 앞 / 줄 맨 끝에서 입력 시작"
    Add-ViKey "o / O"     "아래 / 위에 새 줄을 만들고 입력 시작"
    Add-ViKey "cw"        "커서부터 단어 끝까지 지우고 입력 시작"
    Add-ViKey "cc"        "현재 줄을 지우고 입력 시작"
    Add-ViKey "ESC"       "입력을 끝내고 보기 모드로 복귀"

    $lines.Add('')
    Add-ViTitle "[ 멀티 라인 편집 (Visual 모드) ]  - 보기 모드에서 아래 키로 선택 시작"

    Add-ViSection "선택 시작"
    Add-ViKey "v"         "글자 단위 선택 시작"
    Add-ViKey "V"         "줄 단위 선택 시작 (여러 줄은 j/k로 확장)"
    Add-ViKey "Ctrl+v"    "블록(세로) 단위 선택 시작"

    Add-ViSection "선택 후 동작"
    Add-ViKey "d / y"     "선택 영역 삭제 / 복사 (붙여넣기는 p)"
    Add-ViKey "> / <"     "선택한 줄 들여쓰기 / 내어쓰기"
    Add-ViKey "J"         "선택한 줄들을 한 줄로 합치기"
    Add-ViKey "ESC"       "선택을 취소하고 보기 모드로 복귀"

    Add-ViSection "멀티 라인 입력 (블록 선택 활용)"
    Add-ViKey "Ctrl+v→I"  "블록 선택 후 I: 각 줄 앞에 동시 입력 (입력 후 ESC 시 전체 줄 적용)"
    Add-ViKey "Ctrl+v→A"  "블록 선택 후 A: 각 줄 뒤에 동시 입력"
    Add-ViKey "Ctrl+v→x"  "블록 선택 후 x: 각 줄의 선택 열을 동시 삭제"
    $lines.Add("$esc[94m  * 예: 여러 줄 주석 처리 = Ctrl+v로 줄 선택 -> I -> # 입력 -> ESC$esc[0m")

    # 파이프/리다이렉션 등 비대화형 환경에서는 그냥 전체를 출력하고 끝낸다.
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        $lines | ForEach-Object { $_ }
        return
    }

    # 대체 스크린 버퍼(ESC[?1049h)로 전환해 새 화면처럼 표시하고,
    # 닫을 때(ESC[?1049l) 이전 화면과 스크롤 히스토리를 그대로 복원한다.
    $prevCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true
    [Console]::Write("$esc[?1049h$esc[?25l")

    try {
        $top = 0
        while ($true) {
            $height = [Console]::WindowHeight - 1   # 마지막 줄은 상태 표시줄
            $maxTop = [Math]::Max(0, $lines.Count - $height)
            if ($top -gt $maxTop) { $top = $maxTop }

            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append("$esc[H")
            for ($i = 0; $i -lt $height; $i++) {
                $idx = $top + $i
                if ($idx -lt $lines.Count) {
                    [void]$sb.Append($lines[$idx])
                }
                [void]$sb.Append("$esc[K`n")
            }

            $shownTo = [Math]::Min($top + $height, $lines.Count)
            [void]$sb.Append(("$esc[7m ↑/↓ PgUp/PgDn 스크롤 | ESC/q/Ctrl+C 닫기  ({0}-{1}/{2}줄) $esc[0m$esc[K" -f ($top + 1), $shownTo, $lines.Count))
            [Console]::Write($sb.ToString())

            $key = [Console]::ReadKey($true)

            if ($key.Key -eq [ConsoleKey]::C -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                return
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

#########################################################
# vi 도움말 영역 End
#########################################################
