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

vim.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "write" })
vim.keymap.set("n", "<esc>", "<cmd>nohlsearch<cr>")
