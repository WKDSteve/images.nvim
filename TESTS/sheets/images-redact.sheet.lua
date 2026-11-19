-- Feature images.redact (TESTS/sheets/features.lua): `:Image redact` opens the image under the cursor in a zen
-- window in censor mode; `v`, a move and `<CR>` mark a box, `w` burns it in with ImageMagick and writes
-- `hello.redacted.png` beside the source, which stays untouched. The pixel size comes from the PNG header (no
-- `magick identify` on the way in); magick runs for real where installed and draws the copy; on a runner without it
-- a stand-in takes the draw, and the sheet proves the draw was asked for the copy. The child has no terminal that draws
-- pictures: the bytes for the terminal are counted, not sent.
return {
  id = "images.redact",
  feature = "images.redact",
  title = "images.nvim: :Image redact marks a box and w writes a redacted copy beside the image",
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
    { keys = ":Image redact<CR>", note = ":Image redact" },
    {
      wait = [[require("images.redact").is_open() and _G.sent > 0 or _G.loud() ~= ""]],
      timeout = 10000,
      note = "the censor window is open and its picture was sent",
    },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
    {
      expect = [[_G.real.magick or _G.eq(#_G.stand_in_calls("magick"), 0)]],
      note = "opening it started no magick: the size came from the header",
    },
    { keys = "v", note = "v: a keyboard selection" },
    { keys = "lllljj", note = "four cells right, two down" },
    { keys = "<CR>", note = "<CR>: the box is taken" },
    { keys = "w", note = "w" },
    {
      wait = [[_G.real.magick and (_G.noted("redacted copy saved") or _G.loud() ~= "")
        or #_G.stand_in_calls("magick") >= 1]],
      timeout = 15000,
      note = "the copy is written",
    },
    {
      expect = [[(function()
        local copy = _G.desk_root .. "/assets/hello.redacted.png"
        if _G.real.magick then return _G.eq(_G.loud(), "") and _G.exists(copy) end
        -- any argument: a .cmd stand-in on Windows ends the list at an empty argument (testing.fake_programs)
        for _, call in ipairs(_G.stand_in_calls("magick")) do
          for _, arg in ipairs(call.argv) do
            if arg:gsub("\\", "/"):find(_G.desk_root .. "/assets/hello.redacted.", 1, true) then return true end
          end
        end
        error("no magick call names hello.redacted.*: " .. vim.inspect(_G.stand_in_calls("magick")), 0)
      end)()]],
      note = "hello.redacted.png beside the source",
    },
    {
      expect = [[_G.eq(vim.fn.getfsize(_G.desk_root .. "/assets/hello.png"), 650)]],
      note = "the source is untouched",
    },
  },
  manual = {
    "Once in WezTerm: the black box covers the marked part in the redacted copy, with its padding",
  },
}
