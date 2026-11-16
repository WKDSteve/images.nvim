-- TESTS/zen_open_cost_spec.lua — what opening a picture costs, counted: process starts, pictures sent to the
-- terminal and full repaints.
--
-- filetree's `<CR>` on an image (`images.zen`) took 7 to 10 s on the Windows work machine, its `<Tab>`
-- (`images.show`) about 2 s. Measured (scripts/bench_open.lua, 2026-11-16): the two send the same bytes once
-- each, and the one step `zen` made on top was a blocking `magick identify` for the window's shape -- a process
-- start, the expensive thing under an endpoint scanner. The header of the file says the same (`images.pixels`).
-- The counts are pinned here, so a process start or a second draw creeping back into the open path shows up red
-- rather than as a slow open on one machine.
--
-- The window is real, so is the PNG (`images.testcard`), the anchor and the terminal module; only the bytes
-- for the terminal (`nvim_ui_send`) and the process starts (`vim.system`) are counted instead of done.

---@diagnostic disable: duplicate-set-field

---@param H table harness from TESTS/run.lua
return function(H)
  local terminal = require("images.terminal")
  if not terminal.available() then
    print("n/a  counting the draws needs nvim_ui_send (API level 14)")
    return
  end

  local prev_cfg = require("images.config").get()
  -- Headless Neovim looks like no image-capable terminal: without this `zen` would open the block-graphics
  -- fallback instead of the window under test.
  require("images.config").setup({ display = { assume_supported = true, terminal_probe = false } })

  ---@class ZenOpenCost
  ---@field spawned string[]
  ---@field sent integer
  ---@field mode integer

  --- Run `fn`, then let the loop run the deferred draw; count what reached the outside.
  ---@param fn fun()
  ---@param between fun()|nil runs right after `fn`, in the same tick (before the deferred draw)
  ---@return ZenOpenCost
  local function cost(fn, between)
    local c = { spawned = {}, sent = 0, mode = 0 }
    local real_system, real_send, real_cmd = vim.system, vim.api.nvim_ui_send, vim.cmd
    vim.system = function(argv, ...)
      c.spawned[#c.spawned + 1] = table.concat(argv, " ")
      return real_system(argv, ...)
    end
    vim.api.nvim_ui_send = function(s)
      if type(s) == "string" and s:find("1337", 1, true) then c.sent = c.sent + 1 end
    end
    vim.cmd = setmetatable({}, {
      __call = function(_, s)
        if s == "mode" then c.mode = c.mode + 1 end
        return real_cmd(s)
      end,
      __index = real_cmd,
    })
    local ok, err = pcall(function()
      fn()
      if between then between() end
      vim.wait(500, function()
        return c.sent > 0
      end, 5)
      -- Anything queued behind the first draw (a second draw would be) gets its tick too.
      vim.wait(50, function()
        return false
      end, 5)
    end)
    vim.system, vim.api.nvim_ui_send, vim.cmd = real_system, real_send, real_cmd
    if not ok then error(err, 0) end
    return c
  end

  H.tmpdir(function(dir)
    local zen = require("images.zen")

    -- A file no cache has seen: the open under test is a cold one.
    local file = dir .. "/tree-pick.png"
    H.write(file, require("images.testcard").build(640, 360))

    local c = cost(function()
      H.ok(zen.open(file, { width = 0.66, height = 0.66 }), "zen opens the picture the way filetree asks for it")
    end)
    H.eq(table.concat(c.spawned, "; "), "", "opening a zen window starts no process (no `magick identify`)")
    H.eq(c.sent, 1, "the picture goes to the terminal exactly once")
    H.eq(c.mode, 0, "no full repaint (`:mode`) on a first open")

    local w, h = vim.api.nvim_win_get_width(zen.win()), vim.api.nvim_win_get_height(zen.win())
    local max_w, max_h = zen.dimensions({ width = 0.66, height = 0.66 })
    H.ok(w <= max_w and h <= max_h and (w < max_w or h < max_h), "the window still takes the picture's shape")
    zen.close()

    -- The new window's own WinResized can arrive before its first draw has run: still one draw.
    local file2 = dir .. "/tree-pick-2.png"
    H.write(file2, require("images.testcard").build(300, 600))
    c = cost(function()
      zen.open(file2)
    end, function()
      vim.api.nvim_exec_autocmds("WinResized", { data = { windows = { zen.win() } } })
    end)
    H.eq(c.sent, 1, "a WinResized of the window just opened does not send the picture a second time")
    H.eq(#c.spawned, 0, "... and starts no process")
    zen.close()

    -- `images.show`, for comparison: the same budget.
    local file3 = dir .. "/tree-tab.png"
    H.write(file3, require("images.testcard").build(640, 360))
    c = cost(function()
      require("images").show(file3)
    end)
    H.eq(#c.spawned, 0, "images.show starts no process either")
    H.eq(c.sent, 1, "images.show sends the picture once")
    terminal.clear()
  end)

  require("images.config").setup(prev_cfg)
end
