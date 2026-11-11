-- TESTS/terminal_limit_spec.lua -- `display.max_file_mb`: a file above the limit is refused with a message (or
-- shrunk) instead of being read and encoded whole on the main thread. Through `terminal.read_file`, which
-- `draw`/`draw_many` call first, so no terminal is needed.

---@param H table harness from TESTS/run.lua
return function(H)
  local terminal = require("images.terminal")
  local config = require("images.config")
  local prev = config.get()

  local ok, err = pcall(function()
    H.tmpdir(function(dir)
      local img = dir .. "/big.png"
      H.write(img, "\137PNG\r\n\26\n" .. string.rep("x", 4000))

      -- Under the limit: read as before.
      config.setup({ display = { max_file_mb = 1 } })
      local raw = terminal.read_file(img)
      H.ok(raw and #raw > 4000, "under the limit the file is read whole")

      -- Over the limit, shrinking off: refused, and the message names the knob and the file.
      config.setup({ display = { max_file_mb = 0.001, shrink_oversized = false } })
      local none, msg = terminal.read_file(img)
      H.eq(none, nil, "over the limit nothing is read")
      H.contains(msg or "", "max_file_mb", "the message names display.max_file_mb")
      H.contains(msg or "", "big.png", "...and the file")
      H.contains(msg or "", "shrink_oversized", "...and says why it was not shrunk")

      -- 0 = no limit.
      config.setup({ display = { max_file_mb = 0, shrink_oversized = false } })
      H.ok(terminal.read_file(img), "max_file_mb = 0 lifts the limit")

      -- Shrinking (ImageMagick present): a real PNG above the limit is read as a reduced copy.
      if require("lib.nvim.cross.executable").exists("magick") then
        local big = dir .. "/photo.png"
        local made = vim.system({ "magick", "-size", "1600x1200", "plasma:fractal", big }, { text = true }):wait()
        if made.code == 0 and vim.uv.fs_stat(big) then
          local size = vim.uv.fs_stat(big).size
          config.setup({ display = { max_file_mb = size / 2 / 1048576, shrink_oversized = true, shrink_px = 200 } })
          local small = terminal.read_file(big)
          H.ok(small and #small < size, "an oversized photo is read as a shrunk copy")
          local shrunk = require("images.convert").shrink(big, 200)
          H.ok(shrunk and vim.uv.fs_stat(shrunk).size < size, "the shrunk copy is smaller than the original")
          H.eq(require("images.convert").shrink(big, 200), shrunk, "a second shrink is served from the cache")
        end
      end
    end)
  end)

  config.setup(prev)
  if not ok then error(err, 0) end
end
