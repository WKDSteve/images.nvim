-- Feature images.tree-zen-open (TESTS/sheets/features.lua): `<CR>` on an image in the real own tree of filetree.nvim
-- opens images.nvim's zen float, with a text preview of the tree open before, the way a person moves through a
-- project. The open used to start a `magick identify` for the window's shape (7 to 10 s against 2 s for `<Tab>` on a
-- Windows machine under an endpoint scanner): this sheet counts what the open costs in a child editor with a UI,
-- where Neovim really repaints and fires WinResized -- no `magick`, the picture sent once, `images.show` never, and
-- the tree's text preview gone before the zen float opens. The child has no terminal that draws pictures, so the
-- bytes for the terminal are counted, not sent; how fast the picture appears stays for a person (`manual`).
-- filetree.nvim and ui.nvim come from .deps/ (CI) or beside this repository; without them the sheet is a reported
-- skip (n/a), never green.
return {
  id = "images.tree-zen-open",
  feature = "images.tree-zen-open",
  title = "images.nvim: <CR> on an image in the tree opens the zen float without a process start, drawn once",
  task = "images.nvim/workstation-measure-zen-open-after-fix",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps()]],
      reason = "filetree.nvim or ui.nvim is not beside this repository",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot({
        images = { display = { assume_supported = true } },
        preview = { enabled = true, mode = "float" },
      })]],
      note = "the project site, images.nvim (the terminal taken as image-capable), the own tree with its preview",
    },
    { lua = [[_G.on(_G.site, "docs/guide.md")]], note = "the cursor on the guide in the tree" },
    { lua = [[_G.press("<Tab>")]], note = "<Tab>: its text preview" },
    { wait = [[#_G.floats() == 1]], timeout = 3000, note = "the preview float is open" },
    {
      lua = [[
        _G.cost = { magick = 0, sent = 0, shown = 0, floats_at_zen = nil }
        local system = vim.system
        vim.system = function(argv, ...)
          if argv[1] == "magick" then _G.cost.magick = _G.cost.magick + 1 end
          return system(argv, ...)
        end
        require("lib.nvim.terminal.osc").send = function(seq)
          if seq:find("1337", 1, true) then _G.cost.sent = _G.cost.sent + 1 end
          return true
        end
        local images = require("images")
        local zen, show = images.zen, images.show
        images.zen = function(...)
          _G.cost.floats_at_zen = #_G.floats()
          return zen(...)
        end
        images.show = function(...)
          _G.cost.shown = _G.cost.shown + 1
          return show(...)
        end
      ]],
      note = "from here on, process starts of magick and pictures sent to the terminal are counted",
    },
    { lua = [[_G.on(_G.site, "docs/assets/linked.png")]], note = "the cursor on the image; the preview follows it" },
    { lua = [[_G.press("<CR>")]], note = "<CR> on the image" },
    {
      wait = [[require("images.zen").is_open() and _G.cost.sent > 0]],
      timeout = 5000,
      note = "the zen float is open and its picture went to the terminal",
    },
    {
      wait = [[(function() vim.wait(300) return true end)()]],
      note = "the editor repaints and fires WinResized for the new window",
    },
    { expect = [[_G.eq(_G.cost.magick, 0)]], note = "opening it started no magick (no `magick identify`)" },
    { expect = [[_G.eq(_G.cost.sent, 1)]], note = "the picture was sent once, not again for the window's own resize" },
    { expect = [[_G.eq(_G.cost.shown, 0)]], note = "the inline view (`images.show`) was not used as well" },
    { expect = [[_G.eq(_G.cost.floats_at_zen, 0)]], note = "the tree's text preview was gone before zen opened" },
    {
      expect = [[_G.eq(#_G.floats(), 1) and _G.eq(vim.api.nvim_get_current_win(), require("images.zen").win())]],
      note = "the zen float is the one float, and the cursor is in it",
    },
    {
      expect = [[_G.eq(vim.api.nvim_win_get_config(require("images.zen").win()).title[1][1], " linked.png ")]],
      note = "its title names the image",
    },
    { lua = [[_G.press("q")]], note = "q closes it" },
    { wait = [[not require("images.zen").is_open()]], timeout = 3000, note = "the zen float is gone" },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
  manual = {
    "In WezTerm on the Windows work machine: <CR> on an image in the tree shows the frame at once and the picture "
      .. "about as fast as <Tab> shows it inline (images.nvim/workstation-measure-zen-open-after-fix)",
  },
}
