# Windows Neovim 설치 및 설정 가이드

winget으로 Neovim을 설치하고, lazy.nvim 기반 플러그인 구성(`init.lua`)까지 완료하는 가이드입니다.

- 대상 OS: Windows 10 / 11
- 터미널: Windows Terminal 권장 (트루컬러 지원)
- 소요 시간: 약 10~15분

---

## 1. 필수 프로그램 설치 (winget)

PowerShell을 열고 아래 명령을 실행합니다.

```powershell
winget install Neovim.Neovim Git.Git BurntSushi.ripgrep.MSVC sharkdp.fd
```

| 도구 | 필요한 이유 |
|---|---|
| Neovim | 에디터 본체 (0.12+ — 내장 treesitter로 구문 하이라이팅 처리) |
| Git | lazy.nvim(플러그인 매니저)이 플러그인을 `git clone`으로 설치 |
| ripgrep, fd | telescope의 파일/텍스트 검색 백엔드 |

> 설치 후 **PowerShell을 재시작**해야 PATH가 반영됩니다.
> 확인: `nvim --version`, `git --version`, `rg --version`
> (예전 가이드의 zig는 nvim-treesitter 파서 컴파일용이었는데, 해당 플러그인을 제거해 더 이상 필요 없습니다.)

### 1-1. Nerd Font 설치 (아이콘 폰트)

파일 트리·상태줄의 아이콘 표시에 필요합니다.

```powershell
winget install DEVCOM.JetBrainsMonoNerdFont
```

설치 후 **Windows Terminal 설정 → 프로필(PowerShell) → 모양 → 글꼴**을
`JetBrainsMono Nerd Font`로 변경합니다.

---

## 2. 설정 폴더 생성

Windows에서 Neovim 설정 파일 위치는 `%LOCALAPPDATA%\nvim\init.lua` 입니다.

```powershell
mkdir $env:LOCALAPPDATA\nvim
notepad $env:LOCALAPPDATA\nvim\init.lua
```

메모장이 열리면 아래 3번의 `init.lua` 내용을 붙여넣고 저장합니다.
(같은 폴더의 `init.lua`가 실제 사용 중인 원본 백업이므로 그 파일을 그대로 복사해도 됩니다.)

---

## 3. init.lua 전체 내용

```lua
-- ============================================================
-- 기본 옵션
-- ============================================================
vim.g.mapleader = " "             -- 리더키 = 스페이스
vim.opt.number = true             -- 줄 번호 표시
vim.opt.termguicolors = true      -- 트루컬러 활성화
vim.opt.expandtab = true          -- 탭 대신 스페이스
vim.opt.shiftwidth = 4            -- 들여쓰기 폭
vim.opt.clipboard = "unnamedplus" -- 시스템 클립보드 연동

-- ============================================================
-- lazy.nvim 부트스트랩 (최초 실행 시 자동 설치)
-- ============================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- ============================================================
-- 플러그인
-- ============================================================
require("lazy").setup({
  -- 테마 (Tokyo Night)
  {
    "folke/tokyonight.nvim",
    lazy = false, priority = 1000,
    config = function() vim.cmd.colorscheme("tokyonight-night") end,
  },

  -- 구문 하이라이팅: Neovim 0.12+ 내장 treesitter 사용 (markdown/lua/vim/c, 코드펜스 injection 포함).
  -- nvim-treesitter(master 브랜치)는 동결되어 0.12와 비호환(구형 match 형식 → range nil 에러)이라 사용하지 않음.
  -- python/js/json은 regex 문법으로 폴백 — 정밀 하이라이트가 필요해지면 main 브랜치로 재도입할 것.

  -- 퍼지 검색 (telescope)
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "파일 찾기" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "텍스트 검색" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",    desc = "버퍼 목록" },
    },
  },

  -- 파일 탐색기 (neo-tree)
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = { { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "파일 트리" } },
  },

  -- 상태줄 / git 변경 표시 / 단축키 안내 / 자동 괄호
  { "nvim-lualine/lualine.nvim", opts = {} },
  { "lewis6991/gitsigns.nvim", opts = {} },
  { "folke/which-key.nvim", opts = {} },
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

  -- LSP (언어 서버: 자동완성·정의 이동·오류 진단)
  { "mason-org/mason.nvim", opts = {} },
  {
    "neovim/nvim-lspconfig",
    dependencies = { "mason-org/mason-lspconfig.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "pyright" }, -- 필요한 언어 서버 추가
      })
    end,
  },

  -- 자동완성 UI
  {
    "saghen/blink.cmp",
    version = "1.*",
    opts = { keymap = { preset = "enter" } },
  },
})
```

---

## 4. 첫 실행 및 확인

1. PowerShell에서 `nvim` 실행
   - 최초 실행 시 lazy.nvim이 플러그인을 자동으로 클론/설치합니다 (진행 창 표시).
   - 설치가 끝나면 `q`로 진행 창을 닫습니다.
2. `:checkhealth` — 누락된 의존성(컴파일러, ripgrep 등)을 점검합니다.
3. `:Lazy` — 플러그인 설치 상태 확인 및 업데이트(`U`).
4. `:Mason` — LSP 서버 설치 상태 확인. 다른 언어 서버도 이 UI에서 설치 가능합니다.

### 주요 단축키

| 키 | 동작 |
|---|---|
| `Space` + `ff` | 파일 찾기 |
| `Space` + `fg` | 프로젝트 전체 텍스트 검색 |
| `Space` + `fb` | 열린 버퍼 목록 |
| `Space` + `e` | 파일 트리 토글 |
| `gcc` | 현재 줄 주석 토글 (Neovim 0.10+ 내장) |
| `gd` | 정의로 이동 (LSP) |
| `K` | 문서 팝업 (LSP) |

---

## 5. 자주 발생하는 문제 (Windows)

| 증상 | 원인 / 해결 |
|---|---|
| md 파일 열 때 `range (a nil value)` 에러 | 구버전 nvim-treesitter(master) 플러그인 잔재 → init.lua에서 플러그인 제거(내장 treesitter 사용) 후 nvim에서 `:Lazy clean` 실행 |
| 아이콘이 네모(□)로 깨짐 | 터미널 글꼴이 Nerd Font가 아님 → Windows Terminal 글꼴 설정 확인 |
| 색상이 이상함 | `vim.opt.termguicolors = true` 누락이거나 구형 cmd 콘솔 사용 → Windows Terminal 사용 |
| telescope 검색이 안 됨 | ripgrep/fd 미설치 → `rg --version`, `fd --version` 확인 |
| lazy.nvim이 플러그인을 못 받음 | git 미설치 또는 사내 프록시 → `git --version` 확인, 프록시 환경이면 git 프록시 설정 필요 |

---

## 6. 테마 변경 방법

`init.lua`의 테마 블록에서 플러그인과 `colorscheme` 이름만 교체하면 됩니다.

예: Catppuccin으로 변경

```lua
{
  "catppuccin/nvim",
  name = "catppuccin",
  lazy = false, priority = 1000,
  config = function()
    vim.cmd.colorscheme("catppuccin-mocha") -- mocha(다크) / latte(라이트)
  end,
},
```

추천 테마: `folke/tokyonight.nvim`, `catppuccin/nvim`, `rebelot/kanagawa.nvim`,
`ellisonleao/gruvbox.nvim`, `rose-pine/neovim`
