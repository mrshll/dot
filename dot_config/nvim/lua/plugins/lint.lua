return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = {
            "--config",
            function()
              return vim.fn.stdpath("config") .. "/.markdownlint-cli2.jsonc"
            end,
            "-",
          },
        },
      },
    },
  },
}
