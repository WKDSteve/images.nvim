-- Feature images.tree-orphan-rescan (TESTS/sheets/features.lua): an image lands in `docs/assets` past the editor
-- (a download, a copy in the file manager). The menu of the folder in the real own tree of filetree.nvim offers
-- "Look for unreferenced images again"; picked with the mouse and <CR> it scans every root again, says in one
-- line how many unreferenced images there are, and the new image carries its badge.
return {
  id = "images.tree-orphan-rescan",
  feature = "images.tree-orphan-rescan",
  title = "images.nvim: the menu of a folder looks for unreferenced images again and says how many there are",
  task = "images.nvim/abnahme-orphan-images-in-the-own-tree",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps()]],
      reason = "filetree.nvim or ui.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]],
      note = "the project site, images.nvim, the own tree on the left",
    },
    { lua = [[_G.on(_G.site, "docs/assets/unused.png")]] },
    {
      wait = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      timeout = 10000,
      note = "one unreferenced image so far",
    },
    {
      lua = [[_G.write(_G.site, "docs/assets/pasted.png")]],
      note = "a new image nobody links, written past the editor",
    },
    { keys = "R", note = "the tree reads its folders again (its own key)" },
    {
      wait = [[_G.line_of(_G.site .. "/docs/assets/pasted.png") ~= nil]],
      timeout = 5000,
      note = "and shows the file",
    },
    { lua = [[_G.right_click(_G.site .. "/docs/assets")]], note = "a right click on the folder" },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[_G.menu_on("Look for unreferenced images again")]],
      note = "it offers to look again",
    },
    { keys = "<CR>", note = "pick the entry" },
    {
      wait = [[_G.noted("images.nvim: 2 unreferenced images")]],
      timeout = 10000,
      note = "one line says how many there are",
    },
    {
      wait = [[_G.row_has(_G.site .. "/docs/assets/pasted.png", "orphan")]],
      timeout = 5000,
      note = "the new image has its badge",
    },
    { expect = [[_G.row_has(_G.site .. "/docs/assets", "2")]], note = "and the folder counts two" },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
  judge = {
    "The entry reads well among the other entries of the folder menu",
  },
}
