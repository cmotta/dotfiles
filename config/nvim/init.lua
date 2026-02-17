----------------------------
-- BASIC NEOVIM SETTINGS  --
----------------------------
vim.g.mapleader = " " -- Space as leader key

vim.opt.number = true -- Show line numbers
vim.opt.relativenumber = true -- Relative numbers for motion
vim.opt.signcolumn = "yes" -- Always show sign column
vim.opt.updatetime = 200 -- Faster diagnostics and CursorHold

-- Always use spaces for indentation
vim.opt.expandtab = true   -- tabs are spaces
vim.opt.tabstop = 2        -- number of spaces a <Tab> counts for
vim.opt.shiftwidth = 2     -- number of spaces to use for autoindent
vim.opt.softtabstop = 2    -- number of spaces a <Tab> counts for while editing

-- Remove trailing spaces on save
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  command = [[%s/\s\+$//e]],
})

-- Terminal title
-- Enable terminal title
vim.o.title = true

local function set_title_to_cwd()
  local cwd = vim.loop.cwd() or vim.fn.getcwd()
  local proj = vim.fn.fnamemodify(cwd, ":t")
  vim.o.titlestring = "nvim " .. proj
end

-- Set on startup and whenever the cwd changes
vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
  callback = set_title_to_cwd,
})
---------------------------------
-- BOOTSTRAP PLUGIN MANAGER    --
---------------------------------
local lazypath = vim.fn.stdpath("data").."/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({"git","clone","--filter=blob:none","https://github.com/folke/lazy.nvim.git", lazypath})
end
vim.opt.rtp:prepend(lazypath)

-------------------------------
-- PLUGIN DEFINITIONS        --
-------------------------------
require("lazy").setup({
  -- Core dependencies
  { "nvim-lua/plenary.nvim" },
  -- Syntax and code structure
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  { "windwp/nvim-ts-autotag", opts = {} }, -- Auto-close/rename HTML & JSX tags
  -- Navigation & UX
  { "nvim-telescope/telescope.nvim" }, -- Fuzzy finder
  { "folke/which-key.nvim", opts = {} }, -- Expose leader shortcuts
  { "stevearc/oil.nvim", opts = {} }, -- Nerdtree for nvim
  { "nvim-lualine/lualine.nvim", opts = { options = { theme = "auto" } } }, -- Status line
  { "numToStr/Comment.nvim", opts = {} }, -- Facilitate commenting e.g. gcc
  { "kylechui/nvim-surround", opts = {} }, -- Changes surrondings e.g.  cs"' changes from " to '
  { "akinsho/toggleterm.nvim", version = "*", opts = {} }, -- Toggle terminal with leader + t
  { "lewis6991/gitsigns.nvim", opts = {} }, -- inline git actions
  { "folke/trouble.nvim", opts = {} }, -- Show list of issues with leader + xx

  -- LSP + completion
  { "williamboman/mason.nvim", build = ":MasonUpdate", opts = {} },
  { "williamboman/mason-lspconfig.nvim" },
  { "neovim/nvim-lspconfig" },
  { "hrsh7th/nvim-cmp" },
  { "hrsh7th/cmp-nvim-lsp" },
  { "hrsh7th/cmp-buffer" },
  { "hrsh7th/cmp-path" },

  -- Formatting (on save) + extra linters
  { "stevearc/conform.nvim", opts = { format_on_save = { timeout_ms = 500 } } },
  { "nvimtools/none-ls.nvim" },  -- for sqlfluff, cfn-lint, eslint_d, etc.


  -- Automatically add pairs for ", (, etc.
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = true
  },

  -- Neo-tree: multi-source project panel
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- icons (optional but nice)
      "MunifTanjim/nui.nvim",
    },
    opts = {
      close_if_last_window = true,
      sources = { "filesystem", "buffers", "git_status" },
      source_selector = { winbar = true, content_layout = "center" },
      enable_git_status = true,
      enable_diagnostics = true,
      default_component_configs = {
        indent = { with_expanders = true },
        diagnostics = { symbols = { hint = "H", info = "I", warn = "W", error = "E" } },
      },
      filesystem = {
        bind_to_cwd = true,
        follow_current_file = { enabled = true, leave_dirs_open = false },
        use_libuv_file_watcher = true,
        filtered_items = {
          hide_dotfiles = true,
          hide_gitignored = true,
          hide_by_name = { ".git", "node_modules" },
        },
      },
      window = {
      	position = "left",
	      width = 34,
      },
    },
  },

})

-- Treesitter: add TSX/JSX; keeps highlighting/indent robust
require("nvim-treesitter.configs").setup({
  ensure_installed = {
    "lua","vim","vimdoc",
    "python",
    "typescript","tsx","javascript","json","html","css","yaml","markdown",
    "sql"
  },
  auto_install = true,  -- installs missing parsers on buffer open
  highlight = { enable = true },
  indent = { enable = true },
})

-------------------------------
--       LSP SUPPORT         --
-------------------------------

-- Mason: install language servers & tools you use
require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = {
    -- Python
    "pyright", "ruff",
    -- TS/JS/React
    "ts_ls", "eslint", "tailwindcss", "cssls", "html", "jsonls", "emmet_ls",
    -- SQL
    "sqls",
    -- Infra / config
    "yamlls",
    -- Neovim / Lua
    "lua_ls",
  }
})

-- Completion
local cmp = require("cmp")
cmp.setup({
  mapping = cmp.mapping.preset.insert({
    ["<CR>"] = cmp.mapping.confirm({ select = true }),
    ["<C-Space>"] = cmp.mapping.complete(),
  }),
  sources = { { name = "nvim_lsp" }, { name = "path" }, { name = "buffer" } },
})

-- LSP setups
local lsp = require("lspconfig")
local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- Lua (Neovim config)
lsp.lua_ls.setup({ capabilities = capabilities,
  settings = { Lua = { diagnostics = { globals = { "vim" } } } }
})


-- Python
lsp.pyright.setup({
  capabilities = capabilities,
  settings = {
    python = {
      analysis = {
        autoImportCompletions = true,
        diagnosticMode = "workspace",
      },
    },
  },
})
lsp.ruff.setup({ capabilities = capabilities }) -- fast lint + fixes

-- TypeScript / JavaScript / React
lsp.ts_ls.setup({ capabilities = capabilities })
lsp.eslint.setup({ capabilities = capabilities }) -- code actions & diags

-- HTML css
lsp.cssls.setup({ capabilities = capabilities })
lsp.html.setup({ capabilities = capabilities })
lsp.emmet_ls.setup({
  capabilities = capabilities,
  filetypes = { "html","css","scss","javascriptreact","typescriptreact" },
})

-- Tailwind (optional; harmless if absent)
lsp.tailwindcss.setup({ capabilities = capabilities })

-- JSON
lsp.jsonls.setup({ capabilities = capabilities })

-- YAML (CloudFormation: schemaStore handles many cases; pair with cfn-lint below)
lsp.yamlls.setup({
  capabilities = capabilities,
  settings = { yaml = { schemaStore = { enable = true } } },
})

-- SQL
lsp.sqls.setup({ capabilities = capabilities })

-- Conform (format-on-save)
require("conform").setup({
  format_on_save = { timeout_ms = 5000, lsp_fallback = false },
  formatters_by_ft = {
    python = { "ruff_format" },
    javascript = { "prettierd", "prettier" },
    typescript = { "prettierd", "prettier" },
    javascriptreact = { "prettierd", "prettier" },
    typescriptreact = { "prettierd", "prettier" },
    json = { "prettierd", "prettier" },
    html = { "prettierd", "prettier" },
    css = { "prettierd", "prettier" },
    yaml = { "prettierd", "prettier" },
    markdown = { "prettierd", "prettier" },
    sql = { "sqlfluff" }, -- keep simple; see sqlfluff below
    lua = { "stylua" },
  },
  formatters = {
    sqlfluff = {
      command = "sqlfluff",
      args = { "fix", "--disable-progress-bar", "--dialect", "postgres", "-" },
      stdin = true,
    },
  }
})

-- none-ls: hook in extra linters/diagnostics (sqlfluff, cfn-lint, eslint_d)
local null_ls = require("null-ls")
null_ls.setup({
  sources = {
    -- SQLFluff (lint; can be slow to format large files, so lint-only by default)
    null_ls.builtins.diagnostics.sqlfluff.with({
      extra_args = { "--dialect", "postgres" }, -- good default; override per-project
    }),
    -- CloudFormation
    null_ls.builtins.diagnostics.cfn_lint,
  },
})


-------------------------------
--           KEYMAPS         --
-------------------------------
-- QoL keymaps
local map = vim.keymap.set
-- Terminal
map({"n"},"<leader>t","<cmd>ToggleTerm<cr>", { desc="Terminal" })
vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
-- Search
map("n","<leader>ff", require("telescope.builtin").find_files, { desc="Find files" })
map("n","<leader>fg", require("telescope.builtin").live_grep,  { desc="Grep" })
-- Open diagnostic
map("n","<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",   { desc = "Diagnostics list" })
vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- Quickfix nav/open/close
vim.keymap.set("n", "]q", ":cnext<CR>",  { desc = "Quickfix next" })
vim.keymap.set("n", "[q", ":cprev<CR>",  { desc = "Quickfix prev" })
vim.keymap.set("n", "<leader>qo", ":copen<CR>", { desc = "Quickfix open" })
vim.keymap.set("n", "<leader>qc", ":cclose<CR>",{ desc = "Quickfix close" })

-- Buffer nav
vim.keymap.set("n", "]b", ":bnext<CR>",  { desc = "Buffer next" })
vim.keymap.set("n", "[b", ":bprevious<CR>", { desc = "Buffer prev" })

-- Tab nav
vim.keymap.set("n", "]t", ":tabnext<CR>", { desc = "Tab next" })
vim.keymap.set("n", "[t", ":tabprevious<CR>", { desc = "Tab prev" })

-- Toggle some common options (Unimpaired-like 'yo' bindings)
vim.keymap.set("n", "<leader>on", function() vim.wo.number = not vim.wo.number end, { desc="Toggle line numbers" })
vim.keymap.set("n", "<leader>or", function() vim.wo.relativenumber = not vim.wo.relativenumber end, { desc="Toggle relnum" })
vim.keymap.set("n", "<leader>ow", function() vim.wo.wrap = not vim.wo.wrap end, { desc="Toggle wrap" })

-- Neo-tree: project “bird’s-eye” panel (files/buffers/git)
vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle reveal<CR>", { desc = "Project panel (neo-tree)" })

-- Keymap for quick Oil open in current file's folder
vim.keymap.set("n", "-", function() require("oil").open(vim.fn.expand("%:p:h")) end, { desc = "Open Oil in current file's directory" })

-- Navigate splits with Ctrl + h/j/k/l
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left split" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to below split" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to above split" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right split" })

---- Filename regex with fd (shows only files whose PATH matches the regex)
vim.keymap.set("n", "<leader>fr", function()
  local regex = vim.fn.input("Filename regex > ")
  if regex == "" then return end
  require("telescope.builtin").find_files({
    -- -H: follow hidden; -I: no .gitignore; -t f: files only
    find_command = { "fd", "-HI", "-t", "f", regex },
  })
end, { desc = "Find files (regex on path)" })

---- Content regex with ripgrep (search inside files)
vim.keymap.set("n", "<leader>fR", function()
  local pattern = vim.fn.input("Content regex > ")
  if pattern == "" then return end
  require("telescope.builtin").live_grep({
    default_text = pattern,   -- treat as regex by default
    additional_args = function() return { "--hidden", "--no-ignore" } end,
  })
end, { desc = "Live grep (regex content)" })

