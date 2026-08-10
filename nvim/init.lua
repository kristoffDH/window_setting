-- 기본 옵션
vim.g.mapleader = " "            -- 리더키 = 스페이스
vim.opt.number = true
vim.opt.termguicolors = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.clipboard = "unnamedplus" -- 시스템 클립보드 연동

-- lazy.nvim 부트스트랩
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- 테마
  {
    "folke/tokyonight.nvim",
    lazy = false, priority = 1000,
    config = function() vim.cmd.colorscheme("tokyonight-night") end,
  },

  -- 구문 하이라이팅: Neovim 0.12 내장 treesitter 사용 (markdown/lua/vim/c, 코드펜스 injection 포함).
  -- nvim-treesitter(master 브랜치)는 동결되어 0.12와 비호환(구형 match 형식 → range nil 에러)이라 제거함.
  -- python/js/json은 regex 문법으로 폴백 — 정밀 하이라이트가 필요해지면 main 브랜치로 재도입할 것.

  -- 퍼지 검색
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "파일 찾기" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "텍스트 검색" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",    desc = "버퍼 목록" },
    },
  },

  -- 파일 탐색기
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons", "MunifTanjim/nui.nvim" },
    keys = { { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "파일 트리" } },
  },

  -- 상태줄 / git 표시 / 키 안내 / 자동 괄호
  { "nvim-lualine/lualine.nvim", opts = {} },
  { "lewis6991/gitsigns.nvim", opts = {} },
  { "folke/which-key.nvim", opts = {} },
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

  -- LSP
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

  -- 자동완성
  {
    "saghen/blink.cmp",
    version = "1.*",
    opts = { keymap = { preset = "enter" } },
  },
})
