-- Feature images.paste (TESTS/sheets/features.lua): `:Image paste` asks the clipboard program of the platform for an
-- image (Windows: the persistent PowerShell worker, or one `powershell` per paste with
-- `paste.windows_persistent_helper = false`; macOS `pngpaste`; Linux `wl-paste` or `xclip`). The clipboard of the
-- machine is not the sheet's to read or fill: the programs are recording stand-ins (`fakes`) that hand back no
-- image, and the sheet proves the right program was asked, the failure is said, and nothing was written or linked.
return {
  id = "images.paste",
  feature = "images.paste",
  title = "images.nvim: :Image paste asks the clipboard program and, with no image there, says so and links nothing",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  fakes = { "powershell", "pngpaste", "wl-paste", "xclip" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.bare_exe_names()
        _G.desk()
        _G.before = _G.lines()]],
      note = "a note, images.nvim set up; the clipboard programs are stand-ins",
    },
    { lua = [[vim.api.nvim_win_set_cursor(0, { 1, 0 })]], note = "the cursor on the heading" },
    { keys = ":Image paste rel shot<CR>", note = ":Image paste rel shot" },
    { wait = [[_G.loud() ~= ""]], timeout = 15000, note = "the paste has answered" },
    {
      expect = [[(function()
        local asked = vim.fn.has("win32") == 1 and "powershell" or vim.fn.has("mac") == 1 and "pngpaste" or "wl-paste"
        return _G.eq(#_G.faked(asked), 1)
      end)()]],
      note = "the clipboard program of this platform was asked once",
    },
    { expect = [[_G.eq(_G.lines(), _G.before)]], note = "no link was written" },
    {
      expect = [[_G.eq(#vim.fn.globpath(_G.desk_root, "**/*.png", false, true), 2)]],
      note = "no image file was written",
    },
    {
      lua = [[if vim.fn.has("win32") == 1 then
          _G.notes = {}
          require("images.config").get().paste.windows_persistent_helper = false
          vim.cmd("Image paste rel shot")
        end]],
      note = "Windows: once more with one powershell per paste instead of the worker",
    },
    {
      wait = [[vim.fn.has("win32") == 0 or _G.loud() ~= ""]],
      timeout = 15000,
      note = "it has answered too",
    },
    {
      expect = [[vim.fn.has("win32") == 0 or _G.eq(#_G.faked("powershell"), 2)]],
      note = "a second powershell was started for it",
    },
    { expect = [[_G.eq(_G.lines(), _G.before)]], note = "still no link" },
  },
  manual = {
    "With a screenshot in the clipboard (Windows, macOS, Wayland, X11): :Image paste writes the PNG beside the note "
      .. "and links it",
  },
}
