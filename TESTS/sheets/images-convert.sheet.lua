-- Feature images.convert (TESTS/sheets/features.lua): `:Image scale`, `:Image convert` and `:Image optimise` on the
-- image under the cursor of a Markdown note write a copy beside the source through ImageMagick, and say so.
-- Where `magick` is installed it runs for real (what `testing perf` measures: the async `vim.system` of
-- images.proc); on a runner without it a recording stand-in takes the call (`_G.tools`), and the sheet proves the
-- argv names the source and the copy beside it.
return {
  id = "images.convert",
  feature = "images.convert",
  title = "images.nvim: :Image scale, convert and optimise write a copy beside the image under the cursor",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.tools({ magick = {} })
        _G.desk()]],
      note = "a note that links two images, images.nvim set up; magick real where installed",
    },
    { lua = [[_G.cursor_on("hello.png")]], note = "the cursor on the link to hello.png" },
    { keys = ":Image scale 50%<CR>", note = ":Image scale 50%" },
    {
      wait = [[_G.real.magick and (_G.noted("scaled: ") or _G.loud() ~= "") or #_G.stand_in_calls("magick") >= 1]],
      timeout = 15000,
      note = "magick has answered (or the stand-in was called)",
    },
    {
      expect = [[(function()
        local copy = _G.desk_root .. "/assets/hello.scaled.png"
        if _G.real.magick then return _G.eq(_G.loud(), "") and _G.noted("scaled: ") and _G.exists(copy) end
        -- magick writes a temporary name beside the copy, images.convert renames it
        local argv = _G.stand_in_calls("magick")[1].argv
        return _G.starts(argv[#argv], _G.desk_root .. "/assets/hello.scaled.")
      end)()]],
      note = "hello.scaled.png beside the source, and the note says so",
    },
    { keys = ":Image convert webp<CR>", note = ":Image convert webp" },
    {
      wait = [[_G.real.magick and (_G.noted("converted: ") or _G.loud() ~= "") or #_G.stand_in_calls("magick") >= 2]],
      timeout = 15000,
      note = "the conversion is done",
    },
    {
      expect = [[(function()
        local copy = _G.desk_root .. "/assets/hello.webp"
        if _G.real.magick then return _G.eq(_G.loud(), "") and _G.noted("converted: ") and _G.exists(copy) end
        local argv = _G.stand_in_calls("magick")[2].argv
        return _G.starts(argv[#argv], _G.desk_root .. "/assets/hello.")
          and _G.eq(vim.fn.fnamemodify(argv[#argv], ":e"), "webp")
      end)()]],
      note = "hello.webp beside the source",
    },
    { keys = ":Image optimise<CR>", note = ":Image optimise" },
    {
      wait = [[_G.real.magick and #vim.tbl_filter(function(n) return n.msg:find("optim") ~= nil end, _G.notes) > 0
        or #_G.stand_in_calls("magick") >= 3]],
      timeout = 15000,
      note = "the optimisation has answered",
    },
    {
      expect = [[_G.real.magick or #_G.stand_in_calls("magick") == 3]],
      note = "one more magick run for it",
    },
    {
      expect = [[_G.eq(vim.fn.filereadable(_G.desk_root .. "/assets/hello.png"), 1)]],
      note = "the original is still there",
    },
  },
  manual = {
    "Once with a real photo: the scaled, converted and optimised copies open in an image viewer as expected",
  },
}
