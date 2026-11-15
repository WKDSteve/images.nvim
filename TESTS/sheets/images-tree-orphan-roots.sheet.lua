-- Feature images.tree-orphan-roots (TESTS/sheets/features.lua): two projects in two tabs, each with its own tree.
-- images.nvim scans what the trees show, not the working directory: the unreferenced image of the second project
-- gets its badge in the second tab, the one of the first project keeps its own, and a project whose tab is closed
-- is forgotten. The real own tree of filetree.nvim (.deps/ on CI, else beside this repository).
return {
  id = "images.tree-orphan-roots",
  feature = "images.tree-orphan-roots",
  title = "images.nvim: two tabs on two projects, each tree shows the unreferenced images of its own root",
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
      note = "the first project has its badge",
    },
    {
      expect = [[_G.eq(require("images.integrations.tree").roots(), { _G.site })]],
      note = "one tree, one root to scan",
    },
    { lua = [[_G.editor()]], note = "back in the text, as before opening another project" },

    -- a second tab on the second project
    {
      lua = [[vim.cmd("tabedit " .. vim.fn.fnameescape(_G.blog .. "/post.md"))
      vim.cmd("tcd " .. vim.fn.fnameescape(_G.blog))
      _G.blog_win = vim.api.nvim_get_current_win()
      _G.adapter.open_cwd()]],
      note = "a new tab with the post of the blog, its own working directory and its own tree",
    },
    { wait = [[_G.line_of(_G.blog .. "/assets") ~= nil]], timeout = 5000, note = "the tree shows the blog" },
    {
      wait = [[vim.deep_equal(require("images.integrations.tree").roots(), { _G.blog, _G.site })]],
      timeout = 5000,
      note = "both roots are scanned now",
    },
    { lua = [[_G.on(_G.blog, "assets/draft.png")]] },
    {
      wait = [[_G.row_has(_G.blog .. "/assets/draft.png", "orphan")]],
      timeout = 10000,
      note = "the image of the blog nobody links gets its badge",
    },
    { expect = [[_G.row_has(_G.blog .. "/assets", "1")]], note = "and its folder the count" },
    { lua = [[vim.api.nvim_set_current_win(_G.blog_win)]], note = "back in the post" },

    -- the first tab still has its own
    { keys = "1gt", note = "back to the first tab" },
    { expect = [[_G.eq(_G.adapter.get_root_path(), _G.site)]], note = "whose tree still shows the site" },
    {
      wait = [[_G.row_has(_G.site .. "/docs/assets/unused.png", "orphan")]],
      timeout = 5000,
      note = "with its badge",
    },
    {
      expect = [[_G.eq(_G.line_of(_G.blog .. "/assets/draft.png"), nil)]],
      note = "and nothing of the blog",
    },

    -- closing the second tab forgets its project
    { keys = ":tabclose 2<CR>", note = "close the tab of the blog" },
    {
      wait = [[vim.deep_equal(require("images.integrations.tree").roots(), { _G.site })]],
      timeout = 5000,
      note = "its root is no longer scanned",
    },
    {
      wait = [[require("images.integrations.tree").last_scan(_G.blog) == nil]],
      timeout = 5000,
      note = "and what was found there is forgotten",
    },
    {
      expect = [[require("images.integrations.tree").is_orphan(_G.site .. "/docs/assets/unused.png")]],
      note = "the first project keeps its badge",
    },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
  manual = {
    "In the real editor with two real projects in two tabs: each tree shows the badges of its own project, and switching tabs does not move them",
  },
}
