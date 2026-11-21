-- TESTS/ascii_spec.lua — `images.ascii`: the window bookkeeping, and that
-- `open()` never waits for ImageMagick.
--
-- `open()` runs against a `vim.system` stand-in (no real ImageMagick, no
-- real picture): whether the blocks look like the picture is the sheet's and
-- the manual check's part. The sampling/painting it draws through is covered
-- in blocks_spec.lua.

---@param H table harness from TESTS/run.lua
return function(H)
  local ascii = require("images.ascii")

  -- ── no window open: is_open/close are safe no-ops ────────────────────────
  H.falsy(ascii.is_open(), "no ASCII window is open")
  ascii.close() -- must not fail
  H.falsy(ascii.is_open(), "close() stays a no-op without an open window")

  -- ── available(): a real, side-effect-free check (magick on PATH) ─────────
  local available = ascii.available()
  H.eq(type(available), "boolean", "available() reports a boolean either way")

  -- ── open(): ImageMagick runs in the background, never through wait() ─────
  --
  -- `testing perf` measured the open at 138-230 ms of frozen editor: the
  -- sample (and a `magick identify` for the size) ran via `vim.system():wait()`.
  -- The stand-in below throws from `wait()` and hands its `on_exit` to the
  -- spec, which answers by hand -- so a blocking path fails loudly here, and
  -- the order "float first, picture later" is under the spec's control.
  local blocks = require("images.blocks")
  local executable = require("lib.nvim.cross.executable")
  local real = {
    system = vim.system,
    notify = vim.notify,
    available = blocks.available,
    exists = executable.exists,
  }
  local calls, said = {}, {}
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(argv, _, on_exit)
    calls[#calls + 1] = { argv = argv, on_exit = on_exit }
    return {
      pid = -1,
      wait = function()
        error("images.ascii must not wait for " .. tostring(argv[1]))
      end,
      kill = function() end,
    }
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    said[#said + 1] = tostring(msg)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  blocks.available = function()
    return true
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  executable.exists = function(name)
    return name == "magick" or real.exists(name)
  end

  local display = { max_cols = 20, max_rows = 10 }
  -- More bytes than any box of this display needs: `read_sampled` checks for
  -- too few, never too many.
  local payload = string.rep("\100", blocks.frame_bytes(20, 10) * 2)

  ---@param needle string
  ---@return boolean
  local function argv_has(call, needle)
    return call ~= nil and table.concat(call.argv, " "):find(needle, 1, true) ~= nil
  end

  local ok_run, run_err = pcall(H.tmpdir, function(dir)
    local fixture = vim.fs.normalize(vim.fn.getcwd() .. "/TESTS/sheets/fixtures/hello.png")
    local function copy(name)
      local target = dir .. "/" .. name
      vim.uv.fs_copyfile(fixture, target)
      return target
    end

    -- 1. The float opens at once with a placeholder; the picture follows.
    local first = copy("first.png")
    local ok_open, open_err = ascii.open(first, display)
    H.ok(ok_open, "open: returns true before ImageMagick has answered (" .. tostring(open_err) .. ")")
    H.ok(ascii.is_open(), "open: the float is there at once")
    H.falsy(ascii.is_drawn(), "open: ...showing the placeholder, not yet the picture")
    H.eq(#calls, 1, "open: one magick start -- the sample; the size came from the PNG header, no identify")
    H.ok(argv_has(calls[1], "first.png") and not argv_has(calls[1], "identify"), "open: that start samples the file")

    calls[1].on_exit({ code = 0, stdout = payload, stderr = "" })
    vim.wait(1000, ascii.is_drawn, 5)
    H.ok(ascii.is_drawn(), "answer: the picture replaces the placeholder")
    H.eq(#said, 0, "answer: nothing is reported")

    -- 2. The same file again: the cached sample, no process at all.
    ascii.close()
    calls = {}
    H.ok(ascii.open(first, display), "again: open succeeds")
    H.eq(#calls, 0, "again: the cached sample is drawn, no magick start")
    H.ok(ascii.is_drawn(), "again: drawn at once")
    ascii.close()

    -- 3. Closed before the answer: the late answer opens and reports nothing.
    calls = {}
    local late = copy("late.png")
    H.ok(ascii.open(late, display), "late: open succeeds")
    ascii.close()
    calls[1].on_exit({ code = 0, stdout = payload, stderr = "" })
    vim.wait(50)
    H.falsy(ascii.is_open(), "late: an answer for a closed float opens nothing")
    H.eq(#said, 0, "late: ...and says nothing")
    calls = {}
    H.ok(ascii.open(late, display), "late: opened again")
    H.eq(#calls, 0, "late: the dropped answer was still remembered, no second magick start")
    H.ok(ascii.is_drawn(), "late: drawn at once")
    ascii.close()

    -- 4. Replaced by a newer open: the older answer must not paint the newer float.
    calls = {}
    H.ok(ascii.open(copy("old.png"), display), "replaced: first open")
    H.ok(ascii.open(copy("new.png"), display), "replaced: second open")
    calls[1].on_exit({ code = 0, stdout = payload, stderr = "" })
    vim.wait(50)
    H.falsy(ascii.is_drawn(), "replaced: the old answer is dropped, the new float still waits")
    calls[2].on_exit({ code = 0, stdout = payload, stderr = "" })
    vim.wait(1000, ascii.is_drawn, 5)
    H.ok(ascii.is_drawn(), "replaced: the new answer draws")
    ascii.close()

    -- 5. ImageMagick fails: the float closes and the failure is said.
    calls = {}
    H.ok(ascii.open(copy("broken.png"), display), "failure: open still returns at once")
    calls[1].on_exit({ code = 1, stdout = "", stderr = "no decode delegate" })
    vim.wait(1000, function()
      return #said > 0
    end, 5)
    H.falsy(ascii.is_open(), "failure: the placeholder float is closed")
    H.contains(said[1] or "", "no decode delegate", "failure: ImageMagick's reason is reported")
    said = {}

    -- 6. A format without a size in its header: identify, also in the background.
    calls = {}
    local svg = dir .. "/wide.svg"
    H.write(svg, '<svg xmlns="http://www.w3.org/2000/svg"/>')
    H.ok(ascii.open(svg, display), "svg: open returns at once")
    H.ok(argv_has(calls[1], "identify"), "svg: the size is asked of ImageMagick")
    calls[1].on_exit({ code = 0, stdout = "SVG 400 100", stderr = "" })
    vim.wait(1000, function()
      return #calls >= 2
    end, 5)
    H.ok(argv_has(calls[2], "wide.svg") and not argv_has(calls[2], "identify"), "svg: then the sample starts")
    calls[2].on_exit({ code = 0, stdout = payload, stderr = "" })
    vim.wait(1000, ascii.is_drawn, 5)
    H.ok(ascii.is_drawn(), "svg: drawn")
    ascii.close()
  end)

  ascii.close()
  vim.system = real.system
  vim.notify = real.notify
  blocks.available = real.available
  executable.exists = real.exists
  H.ok(ok_run, "the open cases ran through: " .. tostring(run_err))
end
