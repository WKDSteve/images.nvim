-- Feature images.tree-orphan-delete (TESTS/sheets/features.lua), in a tree without a trash
-- (`features.trash.enabled = false` of filetree.nvim): images.nvim asks itself, with the editor's own confirm
-- prompt, and deletes for good. Cancel keeps the file and its badge; Delete removes it, the tree is told and the
-- badge and the count go.
return {
  id = "images.tree-orphan-delete-for-good",
  feature = "images.tree-orphan-delete",
  title = "images.nvim: without a trash in the tree the delete asks in a confirm prompt and deletes for good",
  task = "images.nvim/abnahme-orphan-images-in-the-own-tree",
  engine = "rpc",
  -- the subject is images.nvim's own vim.fn.confirm: let it show its prompt instead of "cancelled"
  prompts = "real",
  sizes = { { rows = 24, cols = 100 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps()]],
      reason = "filetree.nvim or ui.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot({ trash = "none" })]],
      note = "the project site, images.nvim, the own tree without its trash feature",
    },
    { lua = [[_G.on(_G.site, "docs/assets/unused.png")]] },
    {
      wait = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      timeout = 10000,
      note = "the image nobody links has its badge",
    },

    -- Cancel
    { lua = [[_G.right_click(_G.site .. "/docs/assets/unused.png")]], note = "a right click on the image" },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[_G.menu_on("Delete this unreferenced image")]],
      note = "it offers to delete the unreferenced image",
    },
    { input = "<CR>", note = "pick the entry" },
    { prompt = "confirm", timeout = 5000, note = "images.nvim asks whether to delete the image for good" },
    { screen = "confirm", note = "the question as the editor shows it" },
    { input = "c", note = "Cancel" },
    { wait = [[_G.exists(_G.site .. "/docs/assets/unused.png")]], timeout = 5000, note = "Cancel keeps the file" },
    {
      expect = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      note = "and its badge",
    },
    { wait = [[#_G.floats() == 0]], timeout = 5000, note = "the menu is gone" },

    -- Delete
    { lua = [[_G.right_click(_G.site .. "/docs/assets/unused.png")]], note = "a right click on the image again" },
    { wait = [[#_G.floats() > 0]], timeout = 5000 },
    { expect = [[_G.menu_on("Delete this unreferenced image")]] },
    { input = "<CR>", note = "pick the entry again" },
    { prompt = "confirm", timeout = 5000 },
    { input = "d", note = "Delete" },
    {
      wait = [[not _G.exists(_G.site .. "/docs/assets/unused.png")]],
      timeout = 5000,
      note = "the image is deleted",
    },
    {
      wait = [[_G.line_of(_G.site .. "/docs/assets/unused.png") == nil]],
      timeout = 5000,
      note = "the tree drops its line",
    },
    {
      wait = [[_G.row(_G.site .. "/docs/assets") == "    ▾ assets/"]],
      timeout = 5000,
      note = "and the folder stops counting it",
    },
    { expect = [[_G.exists(_G.site .. "/docs/assets/linked.png")]], note = "the linked image is untouched" },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
  judge = {
    "The confirm prompt names the image and says that no document links it",
  },
}
