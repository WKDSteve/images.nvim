-- Feature images.screenshot (TESTS/sheets/features.lua): `:Image screenshot` starts the interactive screen selection
-- of the platform (Windows: one `powershell` that takes the clipboard baseline, opens the Snipping Tool through
-- `ms-screenclip:` and waits for the snip itself; macOS `screencapture -i`; Wayland `slurp` + `grim`; X11 `maim -s`).
-- A selection needs a person: here the programs are recording stand-ins (`fakes`) and nobody selects, so the capture
-- ends without a picture (Windows: the stand-in watcher ends without an answer) and nothing is written or linked.
-- What `testing perf` counts on Windows: exactly one `powershell` for the whole wait (it used to be one per poll tick).
return {
  id = "images.screenshot",
  feature = "images.screenshot",
  title = "images.nvim: :Image screenshot starts the screen selection and, when nothing is selected, links nothing",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  fakes = { "explorer", "powershell", "screencapture", "slurp", "grim", "maim" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.bare_exe_names()
        _G.desk({ display = { screenshot = { windows_timeout_ms = 1500, windows_poll_interval_ms = 300 } } })
        _G.before = _G.lines()]],
      note = "a note, images.nvim set up (Windows: a 1.5 s wait for the snip); the capture programs are stand-ins",
    },
    { keys = ":Image screenshot<CR>", note = ":Image screenshot" },
    { wait = [[_G.loud() ~= ""]], timeout = 15000, note = "the capture has ended" },
    {
      expect = [[(function()
        if vim.fn.has("win32") == 1 then
          local ps = _G.faked("powershell")
          return _G.eq(#ps, 1) and table.concat(ps[1].argv, " "):find("ms-screenclip:", 1, true) ~= nil
            and _G.eq(#_G.faked("explorer"), 0) and _G.loud():find("without an answer", 1, true) ~= nil
        elseif vim.fn.has("mac") == 1 then
          return _G.eq(_G.faked("screencapture")[1].argv[1], "-i") and _G.loud():find("cancelled", 1, true) ~= nil
        end
        return _G.eq(#_G.faked("slurp"), 1) and _G.eq(#_G.faked("grim"), 0)
          and _G.loud():find("cancelled", 1, true) ~= nil
      end)()]],
      note = "the selection of this platform was started, and the capture ended without a picture",
    },
    { expect = [[_G.eq(_G.lines(), _G.before)]], note = "no link was written" },
    {
      expect = [[_G.eq(#vim.fn.globpath(_G.desk_root, "**/*.png", false, true), 2)]],
      note = "no image file was written",
    },
  },
  manual = {
    "On Windows, macOS, Wayland and X11: :Image screenshot, select a region; the PNG lands beside the note, linked",
  },
}
