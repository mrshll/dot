return {
  "saghen/blink.cmp",
  opts = {
    keymap = {
      preset = "enter", -- Keeps enter working normally
      ["<Tab>"] = { "select_and_accept", "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
    },
  },
}
