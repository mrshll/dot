-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- serveserve has no system clipboard; yank to the viewing terminal via OSC 52
-- (passes through herdr and ssh to kitty on the Mac).
if vim.uv.os_gethostname() == "serveserve" then
  vim.g.clipboard = "osc52"
  vim.opt.clipboard = "unnamedplus"
end
