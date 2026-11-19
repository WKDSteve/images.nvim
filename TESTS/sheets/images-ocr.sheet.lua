-- Feature images.ocr (TESTS/sheets/features.lua): `:Image ocr` on the link under the cursor reads the text out of the
-- image into a scratch buffer, and `--upscale` enlarges it with ImageMagick first. tesseract and magick run for real
-- where installed (the fixture says HELLO); on a runner without them the stand-ins answer the way they would, so the
-- buffer holds the same word either way.
return {
  id = "images.ocr",
  feature = "images.ocr",
  title = "images.nvim: :Image ocr reads the text of the image under the cursor into a scratch buffer",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.tools({ tesseract = { stdout = "HELLO" }, magick = {} })
        _G.desk()
        _G.note_win = vim.api.nvim_get_current_win()]],
      note = "a note that links two images, images.nvim set up; tesseract and magick real where installed",
    },
    { lua = [[_G.cursor_on("hello.png")]], note = "the cursor on the link to hello.png" },
    { keys = ":Image ocr<CR>", note = ":Image ocr" },
    {
      wait = [[vim.api.nvim_get_current_win() ~= _G.note_win or _G.loud() ~= ""]],
      timeout = 30000,
      note = "the text arrives in its own window",
    },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
    { expect = [[_G.eq(vim.trim(table.concat(_G.lines(), "\n")), "HELLO")]], note = "the buffer holds HELLO" },
    {
      lua = [[vim.api.nvim_set_current_win(_G.note_win)
        _G.cursor_on("hello.png")
        vim.cmd("only")]],
      note = "back in the note, the result window closed",
    },
    { keys = ":Image ocr --upscale<CR>", note = ":Image ocr --upscale" },
    {
      wait = [[vim.api.nvim_get_current_win() ~= _G.note_win or _G.loud() ~= ""]],
      timeout = 30000,
      note = "the text arrives again",
    },
    {
      expect = [[_G.real.magick and _G.eq(_G.loud(), "") or _G.loud():find("upscaling for OCR failed", 1, true) ~= nil]],
      note = "nothing was said at warning level (a magick stand-in writes no enlarged copy: that is said)",
    },
    {
      expect = [[_G.real.magick or #_G.stand_in_calls("magick") == 1]],
      note = "the image was enlarged by magick first",
    },
    {
      expect = [[_G.real.magick or _G.real.tesseract
        or _G.eq(vim.trim(table.concat(_G.lines(), "\n")), "HELLO")]],
      note = "with stand-ins the buffer holds HELLO again (the real pair reads the enlarged copy)",
    },
  },
}
