-- Feature images.ascii (TESTS/sheets/features.lua): in a terminal that draws no pictures (the child editor has none)
-- `:Image` on the link under the cursor shows the image as block characters in a float, sampled by ImageMagick.
-- That sample is a blocking start of images.proc on the main loop: `testing perf` measures how long the editor
-- waits for it. On a runner without magick the stand-in takes the call and writes no pixels: the sheet then proves the
-- call names the image and that the failure is said instead of a broken float.
return {
  id = "images.ascii",
  feature = "images.ascii",
  title = "images.nvim: :Image in a terminal without pictures shows the image as block characters",
  engine = "rpc",
  sizes = { { rows = 30, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.tools({ magick = {} })
        _G.desk()]],
      note = "a note that links two images, images.nvim set up; magick real where installed",
    },
    { lua = [[_G.cursor_on("hello.png")]], note = "the cursor on the link to hello.png" },
    { keys = ":Image<CR>", note = ":Image" },
    {
      wait = [[require("images.ascii").is_open() or _G.loud() ~= ""]],
      timeout = 10000,
      note = "the blocks are drawn, or the failure is said",
    },
    {
      expect = [[(function()
        if not _G.real.magick then
          local argv = _G.stand_in_calls("magick")[1].argv
          return _G.starts(table.concat(argv, " "):match("%S*hello%.png%S*") or "", _G.desk_root .. "/assets/hello.png")
            and not require("images.ascii").is_open()
        end
        return _G.eq(_G.loud(), "") and require("images.ascii").is_open()
      end)()]],
      note = "a float of block characters (with a stand-in: the call named the image, no float)",
    },
    {
      expect = [[_G.real.magick == false or (function()
        local text = _G.float_text()
        return text:find("[\128-\255]") ~= nil
      end)()]],
      note = "the float holds block characters",
    },
    { keys = "<Esc>", note = "<Esc>" },
    { lua = [[require("images").clear()]], note = "the picture is cleared" },
    { expect = [[not require("images.ascii").is_open()]], note = "the float is gone" },
  },
  manual = {
    "In a terminal without image support (plain conhost, Terminal.app): :Image on a photo shows a recognisable picture",
  },
}
