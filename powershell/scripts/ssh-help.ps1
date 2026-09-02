#########################################################
# ssh 원격 관리 도움말 영역 Start
#########################################################
# $PROFILE의 원격 관련 명령(ss/sd/xs/xd/c/auth/sw/xw/up/dn/rr)을 사용 흐름 순서로 정리한 가이드.
# 명령 자체는 $PROFILE에 있으므로, 프로필 쪽을 고치면 이 설명도 함께 갱신할 것.

function Show-HelpPager {
    # fnc-ignore
    # 대체 스크린 버퍼에 내용을 띄우고 스크롤한다 (vi-help와 동일한 방식).
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$StatusHint = '↑/↓ PgUp/PgDn 스크롤 | ESC/q/Ctrl+C 닫기'
    )

    $esc = [char]27
    $prevCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true
    [Console]::Write("$esc[?1049h$esc[?25l")

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
                    [void]$sb.Append($Lines[$idx])
                }
                [void]$sb.Append("$esc[K`n")
            }

            $shownTo = [Math]::Min($top + $height, $Lines.Count)
            [void]$sb.Append(("$esc[7m {0}  ({1}-{2}/{3}줄) $esc[0m$esc[K" -f $StatusHint, ($top + 1), $shownTo, $Lines.Count))
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

function ssh-help {
    # 원격 서버 선택/접속/파일 전송 명령 가이드를 새 화면에 표시한다. (↑↓/PgUp/PgDn 스크롤, ESC/q/Ctrl+C 닫기)
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
    Add-Plain "  $esc[92mss$esc[0m 서버 선택  ->  $esc[92mc$esc[0m 접속 / $esc[92msw$esc[0m 원격 경로 고정  ->  $esc[92mup dn$esc[0m 파일 전송"
    Add-Plain "  서버간 전송은 $esc[92msd$esc[0m 로 대상까지 고른 뒤 $esc[92mrr$esc[0m."
    Add-Plain ""
    Add-Plain "  선택 상태는 프롬프트 윗줄에 표시된다 - SV | ID | IP | PORT | DIR (DST는 아래 줄)."

    # ── 1. 서버 선택 ─────────────────────────────────────────────
    Add-Title "[ 1. 서버 선택 ]"
    Add-Section "명령"
    Add-Cmd "ss [별칭]"        "작업 서버(SV) 선택. 인자 없으면 목록에서 방향키로 고른다"
    Add-Note "Tab: ssh config의 Host 별칭 자동완성"
    Add-Cmd "sd [별칭]"        "전송 대상(DST) 선택 - rr 전용이며 up/dn과는 무관"
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
    Add-Cmd "p"                "선택된 SVIP로 ping (= ping-test)"
    Add-Cmd "d [-r|-l|-u|-d]"  "현재 세션을 화면 분할로 복제 (= dup, 기본 -r 우측)"
    Add-Note "새 pane이 SV/DST/SVDIR 선택 상태를 그대로 이어받는다"
    Add-Cmd "rsa-pubkey"       "로컬 공개키(id_rsa.pub) 내용을 출력한다"

    # ── 3. 원격 작업 디렉터리 ────────────────────────────────────
    Add-Title "[ 3. 원격 작업 디렉터리 (SVDIR) ]"
    Add-Plain "  매번 긴 원격 경로를 치지 않도록 기준 디렉터리를 세션에 고정한다."
    Add-Section "명령"
    Add-Cmd "sw <원격경로>"    "기준 디렉터리 지정 (원격에 실제로 있는지 확인한 뒤 설정)"
    Add-Note "Tab: 원격 디렉터리 자동완성 (원격 홈 또는 절대경로 기준)"
    Add-Cmd "sw"               "현재 설정값 확인"
    Add-Cmd "xw"               "해제 (기준이 다시 원격 홈으로 돌아간다)"

    Add-Section "경로 해석 규칙"
    Add-Cmd "test.txt"         "상대 경로 -> SVDIR 기준 (SVDIR이 없으면 원격 홈)"
    Add-Cmd "sub/a.log"        "하위 경로도 동일"
    Add-Cmd "/var/log/a.log"   "/ 로 시작하면 SVDIR을 벗어난다"
    Add-Cmd "~/a.log"          "~ 로 시작하면 원격 홈 기준 - 역시 SVDIR 무시"
    Add-Note "up / dn / rr(1번째 인자)과 자동완성 모두 같은 규칙을 따른다"

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
    Add-Plain "    dn mes<Tab>         # /var/log 안에서 자동완성 -> dn messages"
    Add-Section "패치 파일 올리고 확인하기"
    Add-Plain "    up patch.tar        # sw로 잡아둔 경로로 업로드"
    Add-Plain "    c                   # 같은 서버에 접속해 확인"
    Add-Section "서버에서 서버로 옮기기"
    Add-Plain "    ss srchost          # 원본 서버"
    Add-Plain "    sd dsthost          # 대상 서버"
    Add-Plain "    rr backup.tar ~/    # 원본:backup.tar -> 대상:~/"

    # ── 6. 문제 해결 ─────────────────────────────────────────────
    Add-Title "[ 6. 자주 겪는 문제 ]"
    Add-Cmd "자동완성이 로컬 경로" "SV 미선택이거나 키 인증이 안 된 상태 - ss 후 auth 실행"
    Add-Cmd "변수 미설정 안내"    "up/dn은 ss가, rr은 ss + sd가 모두 필요하다"
    Add-Cmd "전체 명령 목록"     "fnc (함수 목록) / fnc-alias (alias 목록)"

    Add-Plain ""
    Show-HelpPager -Lines $lines
}

#########################################################
# ssh 원격 관리 도움말 영역 End
#########################################################
