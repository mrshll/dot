-- Treesitter's markdown_inline query conceals the brackets and destination of
-- inline links and images, so `[text](url)` reads as `text` until the cursor
-- lands on the line and the raw form pops back open. Drop just those two
-- conceal patterns so destinations stay put; emphasis and code-span concealing
-- are left alone.
local function show_link_destinations()
  local lang, name = "markdown_inline", "highlights"
  local chunks = {}
  for _, file in ipairs(vim.treesitter.query.get_files(lang, name)) do
    chunks[#chunks + 1] = table.concat(vim.fn.readfile(file), "\n")
  end
  if #chunks == 0 then
    return
  end

  local text = table.concat(chunks, "\n")
  local inline_conceal = '%(inline_link%s*%[.-%]%s*@markup%.link%s*%(#set! conceal ""%)%)'
  local image_conceal = '%(image%s*%[.-%]%s*@markup%.link%s*%(#set! conceal ""%)%)'

  local patched, inline_hits = text:gsub(inline_conceal, "")
  local image_hits
  patched, image_hits = patched:gsub(image_conceal, "")
  if inline_hits + image_hits == 0 then
    -- Upstream query changed shape; leave it be rather than guess.
    return
  end

  pcall(vim.treesitter.query.set, lang, name, patched)
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("markdown_show_links", { clear = true }),
  pattern = { "markdown", "markdown.mdx" },
  once = true,
  callback = show_link_destinations,
})

return {
  -- Calmer markdown rendering: keep the structure cues, drop the noise.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      heading = {
        -- No full-width tinted bars; colored heading text only.
        backgrounds = {},
        width = "block",
      },
      code = {
        -- Background hugs the block instead of bleeding to the window edge.
        width = "block",
        language_name = false,
        border = "thin",
      },
      -- Plainer bullets than the default ● ○ ◆ ◇.
      bullet = { icons = { "•", "◦", "‣", "⁃" } },
      -- No 󰌹 /󰥶 glyphs injected before every link.
      link = { enabled = false },
      pipe_table = { preset = "round" },
    },
  },

  -- Distraction-free read mode for prose: narrow centered column, wrapped
  -- lines, no gutter, no diagnostics.
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>ur",
        function()
          Snacks.zen({
            toggles = { dim = false, diagnostics = false },
            win = {
              width = 88,
              wo = {
                wrap = true,
                linebreak = true,
                breakindent = true,
                number = false,
                relativenumber = false,
                signcolumn = "no",
                cursorline = false,
                colorcolumn = "",
                list = false,
              },
            },
          })
        end,
        desc = "Read Mode (zen prose)",
      },
    },
  },
}
