-- Feature images.zen-zoom (TESTS/sheets/features.lua): `+` in the zen window shows part of the picture larger: the
-- part is a file that ImageMagick cuts out (images.convert.crop, asynchronous), and the zen window sends it in place
-- of the whole picture. magick runs for real where installed; on a runner without it the stand-in takes the cut and
-- the sheet proves the cut was asked for. The child has no terminal that draws pictures: the bytes are counted.
return {
  id = "images.zen-zoom",
  feature = "images.zen-zoom",
  title = "images.nvim: + in the zen window cuts out the middle of the picture with magick and shows it larger",
  engine = "rpc",
  sizes = { { rows = 30, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.tools({ magick = {} })
        _G.desk({ display = { assume_supported = true } })
        _G.count_pictures()]],
      note = "a note that links two images, images.nvim set up (the terminal taken as image-capable)",
    },
    { lua = [[_G.cursor_on("hello.png")]], note = "the cursor on the link to hello.png" },
    { keys = ":Image zen<CR>", note = ":Image zen" },
    {
      wait = [[require("images.zen").is_open() and _G.sent > 0]],
      timeout = 10000,
      note = "the zen window is open and its picture was sent",
    },
    { lua = [[_G.sent = 0]], note = "from here on the pictures sent are counted anew" },
    { keys = "+", note = "+" },
    {
      wait = [[_G.real.magick and (_G.sent > 0 or _G.loud() ~= "") or #_G.stand_in_calls("magick") >= 1]],
      timeout = 15000,
      note = "the part is cut out and shown",
    },
    {
      expect = [[(function()
        if _G.real.magick then return _G.eq(_G.loud(), "") and _G.eq(_G.sent, 1) end
        local argv = _G.stand_in_calls("magick")[1].argv
        return vim.tbl_contains(argv, "-crop")
      end)()]],
      note = "the larger part went to the terminal once (with a stand-in: a crop was asked for)",
    },
    { keys = "q", note = "q closes the zen window" },
    { wait = [[not require("images.zen").is_open()]], timeout = 3000, note = "it is gone" },
  },
  manual = {
    "In WezTerm: + and - in the zen window zoom in and out around the middle without a visible delay",
  },
}
