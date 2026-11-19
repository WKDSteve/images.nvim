-- Feature images.terminal-probe (TESTS/sheets/features.lua): at setup images.nvim asks the terminal its name
-- (XTVERSION) to tell a terminal that draws pictures from one that does not. Under tmux the terminal is not asked
-- directly: `tmux display-message -p '#{client_termtype}'` says what the outer terminal answered tmux (one process per
-- setup, the start `testing perf` sees). The child editor runs in no tmux: the sheet sets $TMUX and puts a stand-in
-- `tmux` first on the PATH that answers like a tmux inside WezTerm, and `:Image check` then names WezTerm.
return {
  id = "images.terminal-probe",
  feature = "images.terminal-probe",
  title = "images.nvim: under tmux the setup asks tmux for the outer terminal, and :Image check names it",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.tmux = require("testing.fake_programs").new({ tmux = { stdout = "WezTerm 20240203-110809-5046fc22" } })
        vim.env.PATH = _G.tmux:path(vim.env.PATH)
        vim.env.TMUX = "/tmp/tmux-1000/default,4242,0"
        vim.env.TMUX_PANE = "%3"
        _G.desk({ display = { terminal_probe = true } })]],
      note = "inside a (stand-in) tmux in WezTerm, images.nvim set up with its terminal probe",
    },
    {
      wait = [[require("images.xtversion").status().state ~= "pending"]],
      timeout = 10000,
      note = "the probe has its answer",
    },
    {
      expect = [[_G.eq(_G.tmux:calls("tmux")[1].argv, { "display-message", "-p", "-t", "%3", "#{client_termtype}" })]],
      note = "tmux was asked once, for the pane of this editor",
    },
    { expect = [[_G.eq(require("images.xtversion").status().state, "answered")]], note = "an answer came" },
    { keys = ":Image check<CR>", note = ":Image check" },
    { wait = [[_G.noted("WezTerm")]], timeout = 5000, note = "the check names WezTerm" },
    { expect = [[_G.eq(#_G.tmux:calls("tmux"), 1)]], note = "the answer was kept: tmux was not asked again" },
  },
  manual = {
    "In WezTerm inside tmux 3.3+: :Image check names WezTerm, and :Image shows the picture",
  },
}
