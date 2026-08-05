#########################################################
# 외부 스크립트 자동 로드 (CurrentUserAllHosts)
#########################################################
# 이 파일은 $PROFILE(Microsoft.PowerShell_profile.ps1)과 별개로 항상 자동 로드된다.
# $PROFILE을 다른 PC 내용으로 통째로 덮어써도 이 로더는 유지된다.
#
# 아래 폴더의 *.ps1을 전부 dot-sourcing해 함수를 세션에 등록한다.
# 파일 추가/제거는 다음 세션부터 자동 반영되며, 폴더가 없거나 비어 있으면 건너뛴다.
# 검사/열거는 .NET API만 사용해 cmdlet 초기화 비용을 피한다.
#
# 경로는 여기서 전역 변수로 한 번만 정의한다 — fnc-extend.ps1(fnc-all)과
# $PROFILE(upload-pwsh)이 이 변수를 참조하므로 폴더를 옮기면 이 줄만 고치면 된다.
$global:my_scripts_dir = 'C:\CorePlatform\99. pwsh script'

if ([System.IO.Directory]::Exists($global:my_scripts_dir)) {
    foreach ($my_script in [System.IO.Directory]::GetFiles($global:my_scripts_dir, '*.ps1')) {
        # GetFiles의 '*.ps1' 패턴은 .ps1xml 같은 긴 확장자도 걸리므로 정확히 .ps1만 로드한다.
        if (-not $my_script.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        try {
            . $my_script
        }
        catch {
            Write-Warning ("스크립트 로드 실패: {0} - {1}" -f $my_script, $_.Exception.Message)
        }
    }
}
