# omp-mytheme

window oh-my-posh theme 파일입니다.
해당 파일의 경로는 $HOME/.mytheme.omp.json 파일에 저장하고 $profile 파일에서 아래처럼 지정하여 적용합니다.
```powershell
oh-my-posh init pwsh --config $HOME/.mytheme.omp.json | Invoke-Expression
```

string tag 적용 방법은 다음과 같습니다.
```powershell
$env:OMP_TAG = "표시할 문자열"

```


바로가기 링크는 총 5개까지 지정 가능합니다.
표시 이름과 실제 링크를 쌍으로 설정해줘야 합니다.
``` powershell
$env:OMP_LINK1_PATH = "C:\Users\kristoff"
$env:OMP_LINK1_NAME = "kristoff"
$env:OMP_LINK2_PATH = "C:\Users\kristoff\Downloads"
$env:OMP_LINK2_NAME = "Downloads"
$env:OMP_LINK3_PATH = "C:\Users\kristoff\Desktop"
$env:OMP_LINK3_NAME = "Desktop"
$env:OMP_LINK4_PATH = "C:\Users\kristoff\Downloads\output"
$env:OMP_LINK4_NAME = "output"
$env:OMP_LINK5_PATH = "C:\my-tools"
$env:OMP_LINK5_NAME = "my-tools"
```