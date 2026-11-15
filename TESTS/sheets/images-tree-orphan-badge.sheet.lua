-- Feature images.tree-orphan-badge (TESTS/sheets/features.lua): a project with a guide that links one image of
-- `docs/assets` and leaves the other alone, open in the real own tree of filetree.nvim. The image nobody links
-- carries the badge `orphan`, each folder above it counts it, and the badge goes when a document that is written
-- links the image. The badges are virtual text the tree places while it draws, so the sheet reads the screen.
-- filetree.nvim and ui.nvim come from .deps/ (CI) or beside this repository; without them the sheet is a reported
-- skip (n/a), never green.
return {
  id = "images.tree-orphan-badge",
  feature = "images.tree-orphan-badge",
  title = "images.nvim: an image no document links carries a badge in the tree, its folders count it",
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
    { lua = [[_G.on(_G.site, "docs/assets/unused.png")]], note = "open docs/assets in the tree" },
    {
      wait = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      timeout = 10000,
      note = "the image nobody links gets the badge, once the scan in the background ended",
    },
    {
      expect = [[_G.eq(_G.row(_G.site .. "/docs/assets/linked.png"), "        linked.png")]],
      note = "the linked image next to it has none",
    },
    { expect = [[_G.row_has(_G.site .. "/docs/assets", "1")]], note = "its folder counts it" },
    { expect = [[_G.row_has(_G.site .. "/docs", "1")]], note = "and so does the folder above" },
    {
      expect = [[_G.eq(_G.row(_G.site .. "/lua"), "  ▸ lua/")]],
      note = "a folder without one shows nothing",
    },
    { hl = { text = "orphan", group = "DiagnosticHint" }, note = "the badge is drawn as a hint" },
    { screen = "badge", note = "the tree with the badge and the counts" },

    -- the badge follows a written document
    { lua = [[_G.editor(); vim.cmd("edit " .. vim.fn.fnameescape(_G.site .. "/docs/guide.md"))]] },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, -1, -1, false, { "![unused](assets/unused.png)" }); vim.cmd("silent write")]],
      note = "the guide now links the image, and is written",
    },
    {
      wait = [[_G.row(_G.site .. "/docs/assets/unused.png") == "        unused.png"]],
      timeout = 10000,
      note = "the badge goes without anybody asking for a scan",
    },
    {
      wait = [[_G.row(_G.site .. "/docs/assets") == "    ▾ assets/" and _G.row(_G.site .. "/docs") == "  ▾ docs/"]],
      timeout = 5000,
      note = "and the counts on the folders",
    },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
  judge = {
    "The badge and the counts sit at the right edge of the tree and do not push the names around",
    "The badge reads as a hint (not as an error) in the colour scheme of the real editor",
  },
}
