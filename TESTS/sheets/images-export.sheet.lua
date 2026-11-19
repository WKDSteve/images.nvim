-- Feature images.export (TESTS/sheets/features.lua): `:Image export` writes the image under the cursor as a PDF
-- beside it, through ImageMagick (pdfport.nvim, the other route, is not installed here). magick runs for real where
-- installed; on a runner without it the stand-in takes the call and the sheet proves the PDF it was asked for.
return {
  id = "images.export",
  feature = "images.export",
  title = "images.nvim: :Image export writes the image under the cursor as a PDF beside it",
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
    { keys = ":Image export<CR>", note = ":Image export" },
    {
      wait = [[_G.real.magick and (_G.noted("exported: ") or _G.loud() ~= "") or #_G.stand_in_calls("magick") >= 1]],
      timeout = 20000,
      note = "the export has answered",
    },
    {
      expect = [[(function()
        if _G.real.magick then
          return _G.eq(_G.loud(), "") and _G.exists(_G.desk_root .. "/assets/hello.pdf")
        end
        local argv = _G.stand_in_calls("magick")[1].argv
        return _G.eq(vim.fn.fnamemodify(argv[#argv], ":e"), "pdf")
      end)()]],
      note = "hello.pdf beside the image, and the note says so",
    },
  },
  manual = {
    "Once: the exported PDF opens in a PDF viewer and shows the picture on one page",
  },
}
