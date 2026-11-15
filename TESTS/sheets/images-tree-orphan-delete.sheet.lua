-- Feature images.tree-orphan-delete (TESTS/sheets/features.lua): the menu of an unreferenced image in the real
-- own tree of filetree.nvim offers "Delete this unreferenced image". The tree asks in its own dialog (the safe
-- answer focused): No keeps the file and its badge, Yes sends it to the trash of the tree, the line goes and the
-- folders stop counting it. A linked image has no such entry.
-- The trash of the operating system is a folder here (TESTS/sheets/_helpers.lua `trash_is_a_folder`): everything
-- the tree does around the one external call is the real code. Which program a platform starts is the sheet
-- images.tree-orphan-delete-program; the real recycle bin stays a manual line.
return {
  id = "images.tree-orphan-delete",
  feature = "images.tree-orphan-delete",
  title = "images.nvim: delete an unreferenced image from the menu of the tree, No and Yes of the trash question",
  task = "images.nvim/own-tree-feature-sheets-images-media-pickers",
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
      note = "the project site, images.nvim, the own tree on the left, its trash a folder",
    },
    { lua = [[_G.on(_G.site, "docs/assets/unused.png")]] },
    {
      wait = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      timeout = 10000,
      note = "the image nobody links has its badge",
    },

    -- a linked image has no such entry
    { lua = [[_G.right_click(_G.site .. "/docs/assets/linked.png")]], note = "a right click on the linked image" },
    { wait = [[_G.float_text():find("Preview image", 1, true) ~= nil]], timeout = 5000, note = "its menu is open" },
    {
      expect = [[_G.float_text():find("Delete this unreferenced image", 1, true) == nil]],
      note = "without the delete of unreferenced images",
    },
    { keys = "<Esc>", note = "close the menu" },
    { wait = [[#_G.floats() == 0]], timeout = 5000 },

    -- No
    { lua = [[_G.right_click(_G.site .. "/docs/assets/unused.png")]], note = "a right click on the image" },
    { wait = [[#_G.floats() > 0]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[_G.menu_on("Delete this unreferenced image")]],
      note = "it offers to delete the unreferenced image",
    },
    { keys = "<CR>", note = "pick the entry" },
    {
      wait = [[_G.float_text():find("Send to trash?", 1, true) ~= nil]],
      timeout = 5000,
      note = "the tree asks in its own dialog",
    },
    {
      expect = [[_G.float_text():find("unused.png", 1, true) ~= nil and _G.float_text():find("[ Yes ]  [ No ]", 1, true) ~= nil]],
      note = "which names the file and has the two buttons",
    },
    { keys = "<CR>", note = "<CR> on the focused button: No is the safe default" },
    { wait = [[#_G.floats() == 0]], timeout = 5000, note = "the dialog is gone" },
    { expect = [[_G.exists(_G.site .. "/docs/assets/unused.png")]], note = "No keeps the file" },
    {
      expect = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      note = "and its badge",
    },

    -- Yes
    { lua = [[_G.right_click(_G.site .. "/docs/assets/unused.png")]], note = "a right click on the image again" },
    { wait = [[#_G.floats() > 0]], timeout = 5000 },
    { expect = [[_G.menu_on("Delete this unreferenced image")]] },
    { keys = "<CR>", note = "pick the entry again" },
    { wait = [[_G.float_text():find("Send to trash?", 1, true) ~= nil]], timeout = 5000 },
    { keys = "h", note = "move to Yes" },
    { keys = "<CR>", note = "and confirm" },
    {
      wait = [[not _G.exists(_G.site .. "/docs/assets/unused.png")]],
      timeout = 5000,
      note = "Yes takes the image out of the project",
    },
    { expect = [[_G.exists(_G.bin .. "/unused.png")]], note = "into the trash of the tree" },
    {
      wait = [[_G.line_of(_G.site .. "/docs/assets/unused.png") == nil]],
      timeout = 5000,
      note = "the tree drops its line",
    },
    {
      wait = [[_G.row(_G.site .. "/docs/assets") == "    ▾ assets/" and _G.row(_G.site .. "/docs") == "  ▾ docs/"]],
      timeout = 5000,
      note = "and the folders stop counting it",
    },
    {
      expect = [[not require("images.integrations.tree").is_orphan(_G.site .. "/docs/assets/unused.png")]],
      note = "the badge is gone",
    },
    { expect = [[_G.exists(_G.site .. "/docs/assets/linked.png")]], note = "the linked image is untouched" },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
  judge = {
    "The trash dialog names the file and reads as the tree's own question (the same one its delete key asks)",
  },
  manual = {
    "In the real editor: Yes sends the image to the real trash of the system (Recycle Bin, Finder trash, gio), it can be restored from there, and the undo of the tree brings it back",
  },
}
