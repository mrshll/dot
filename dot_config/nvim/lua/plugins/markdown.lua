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
