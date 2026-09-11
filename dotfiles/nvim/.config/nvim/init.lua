-- Neutrino - nvim
-- ~/.config/nvim/init.lua

vim.g.mapleader = " "

local o = vim.opt
o.number = true
o.relativenumber = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.ignorecase = true
o.smartcase = true
o.termguicolors = true
o.signcolumn = "yes"
o.undofile = true
o.clipboard = "unnamedplus"
o.scrolloff = 6
o.cursorline = true
o.laststatus = 3
o.fillchars = { eob = " ", vert = "\u{2502}" }
o.list = true
o.listchars = { tab = "\u{2502} ", trail = "\u{00b7}" }

-- --- grayscale -----------------------------------------------------------
-- Same ramp as the rest of the repo. Syntax is carried by weight and
-- lightness instead of hue: comments recede, strings and constants sit mid
-- ramp, keywords and identifiers come forward.
local c = {
  bg      = "#0b0b0b",
  bg_alt  = "#121212",
  surface = "#1a1a1a",
  overlay = "#242424",
  border  = "#303030",
  muted   = "#4d4d4d",
  subtext = "#7a7a7a",
  text    = "#c2c2c2",
  bright  = "#ebebeb",
}

vim.cmd.highlight("clear")
vim.o.background = "dark"
vim.g.colors_name = "neutrino"

local hl = vim.api.nvim_set_hl
local groups = {
  Normal       = { fg = c.text,    bg = c.bg },
  NormalFloat  = { fg = c.text,    bg = c.bg_alt },
  FloatBorder  = { fg = c.border,  bg = c.bg_alt },
  CursorLine   = { bg = c.bg_alt },
  CursorLineNr = { fg = c.bright,  bold = true },
  LineNr       = { fg = c.muted },
  SignColumn   = { bg = c.bg },
  VertSplit    = { fg = c.border },
  WinSeparator = { fg = c.border },
  Visual       = { bg = c.overlay },
  Search       = { fg = c.bg,      bg = c.subtext },
  IncSearch    = { fg = c.bg,      bg = c.bright },
  MatchParen   = { fg = c.bright,  bold = true },
  Pmenu        = { fg = c.text,    bg = c.surface },
  PmenuSel     = { fg = c.bg,      bg = c.text },
  StatusLine   = { fg = c.subtext, bg = c.bg_alt },
  Whitespace   = { fg = c.overlay },
  NonText      = { fg = c.overlay },

  Comment      = { fg = c.muted,   italic = true },
  Constant     = { fg = c.text },
  String       = { fg = c.subtext },
  Character    = { fg = c.subtext },
  Number       = { fg = c.text },
  Boolean      = { fg = c.text,    bold = true },
  Identifier   = { fg = c.text },
  Function     = { fg = c.bright,  bold = true },
  Statement    = { fg = c.bright },
  Keyword      = { fg = c.bright,  bold = true },
  Operator     = { fg = c.subtext },
  PreProc      = { fg = c.subtext },
  Type         = { fg = c.text,    bold = true },
  Special      = { fg = c.subtext },
  Todo         = { fg = c.bg,      bg = c.subtext, bold = true },
  Error        = { fg = c.bright,  bg = c.overlay },

  DiffAdd      = { bg = "#1c1c1c" },
  DiffDelete   = { fg = c.muted },
  DiffChange   = { bg = "#171717" },
  DiffText     = { bg = c.overlay, bold = true },

  DiagnosticError = { fg = c.bright },
  DiagnosticWarn  = { fg = c.text },
  DiagnosticInfo  = { fg = c.subtext },
  DiagnosticHint  = { fg = c.muted },
}
for group, spec in pairs(groups) do
  hl(0, group, spec)
end

-- treesitter, if it ever gets installed, follows the same scheme
hl(0, "@comment",  { link = "Comment" })
hl(0, "@string",   { link = "String" })
hl(0, "@function", { link = "Function" })
hl(0, "@keyword",  { link = "Keyword" })
hl(0, "@variable", { fg = c.text })

vim.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "write" })
vim.keymap.set("n", "<esc>", "<cmd>nohlsearch<cr>")
