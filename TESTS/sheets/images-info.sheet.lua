-- Feature images.info (TESTS/sheets/features.lua): `:Image info` on the link under the cursor says the format and the
-- pixel size of the image. ImageMagick's `magick identify` answers (a blocking start of images.proc, the one
-- `testing perf` watches for a freeze); on a runner without it a stand-in prints what identify prints for the fixture,
-- so the sheet reads the same line either way.
return {
  id = "images.info",
  feature = "images.info",
  title = "images.nvim: :Image info names the format and the size of the image under the cursor",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.tools({ magick = { stdout = "PNG 160 48" } })
        _G.desk()]],
      note = "a note that links two images, images.nvim set up; magick real where installed",
    },
    { lua = [[_G.cursor_on("hello.png")]], note = "the cursor on the link to hello.png" },
    { keys = ":Image info<CR>", note = ":Image info" },
    { wait = [[_G.noted("Format:")]], timeout = 10000, note = "the info is said" },
    { expect = [[_G.noted("Format:   PNG 160x48")]], note = "PNG, 160 by 48 pixels" },
    { expect = [[_G.noted("hello.png")]], note = "it names the file" },
    {
      expect = [[_G.real.magick or _G.eq(_G.stand_in_calls("magick")[1].argv[1], "identify")]],
      note = "the answer came from magick identify",
    },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
  },
}
