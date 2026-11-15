-- Feature images.tree-orphan-delete (TESTS/sheets/features.lua), the external half: which program the trash of
-- the tree starts for the image, with the real backend of filetree.nvim. The programs are recording stand-ins
-- (`fakes`): Windows (and WSL) starts `powershell`, macOS the `trash` CLI, Linux `gio trash`. The stand-in moves
-- nothing, so the file is still there afterwards; that the badge goes with the file is the sheet
-- images.tree-orphan-delete.
return {
  id = "images.tree-orphan-delete-program",
  feature = "images.tree-orphan-delete",
  title = "images.nvim: deleting an unreferenced image hands exactly that file to the trash program of the platform",
  task = "images.nvim/abnahme-orphan-images-in-the-own-tree",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  fakes = { "powershell", "trash", "gio" },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps()]],
      reason = "filetree.nvim or ui.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot({ trash = "program" })]],
      note = "the project site, images.nvim, the own tree with its real trash backend",
    },
    { lua = [[_G.on(_G.site, "docs/assets/unused.png")]] },
    {
      wait = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      timeout = 10000,
      note = "the image nobody links has its badge",
    },
    { lua = [[_G.right_click(_G.site .. "/docs/assets/unused.png")]], note = "a right click on the image" },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[_G.menu_on("Delete this unreferenced image")]],
      note = "it offers to delete the unreferenced image",
    },
    { keys = "<CR>", note = "pick the entry" },
    { wait = [[_G.float_text():find("Send to trash?", 1, true) ~= nil]], timeout = 5000, note = "the tree asks" },
    { expect = [[_G.eq(#_G.trash_calls(), 0)]], note = "nothing was started before the answer" },
    { keys = "h", note = "move to Yes" },
    { keys = "<CR>", note = "and confirm" },
    { wait = [[#_G.trash_calls() >= 1]], timeout = 10000, note = "the trash program is started" },
    { wait = [[#_G.floats() == 0]], timeout = 5000 },
    { expect = [[_G.eq(#_G.trash_calls(), 1)]], note = "once" },
    {
      expect = [[_G.eq(_G.trash_calls()[1].program, _G.trash_program())]],
      note = "the one of this platform (powershell, trash or gio)",
    },
    {
      expect = [[table.concat(_G.trash_calls()[1].argv, " "):find("unused.png", 1, true) ~= nil]],
      note = "with the unreferenced image",
    },
    {
      expect = [[table.concat(_G.trash_calls()[1].argv, " "):find("linked.png", 1, true) == nil]],
      note = "and nothing else of the folder",
    },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
  manual = {
    "On each system once with the real program: the image lands in the Recycle Bin (Windows), the Finder trash (macOS), the trash of the desktop (Linux, gio) and can be restored",
  },
}
