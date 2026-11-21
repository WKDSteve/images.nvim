---@module 'images.ascii'
---@brief Draw an image as coloured block graphics when OSC 1337 is
--- unavailable.
---@description
--- The fallback for any terminal without a graphics protocol (SSH, tmux
--- without passthrough, an unrecognised terminal).
---
--- Originally considered as a color_my_ascii.nvim integration. Its highlighter
--- colours known ASCII character classes (arrows, box drawing, operators, …)
--- against a named scheme — pattern-based, one colour per class. An image, by
--- contrast, needs an arbitrary RGB colour per cell derived from real pixels;
--- that is a different kind of colouring, and not one color_my_ascii offers.
--- Hence a small dedicated path straight over `nvim_set_hl`/extmarks instead of
--- a dependency that does not fit.
---
--- Requires ImageMagick — one of the deliberate exceptions to the
--- "ImageMagick improves, never enables" guardrail (docs/architecture.md lists
--- them all): reading pixel colours out of an arbitrary raster file needs a
--- real image decoder, which plain Lua does not have.
---
--- Every terminal cell becomes a "█" character with its own foreground colour —
--- truecolour block graphics as used by graphics-protocol-less image viewers
--- (chafa, viu), rather than a brightness character ramp (" .:-=+*#%@"). More
--- faithful to the colours, and without the extra question of "which character
--- for which brightness".
---
--- The sampling and painting themselves live in `images.blocks`, which is also
--- what a frame sequence draws through. Moving them there fixed a fault this
--- module had latently: it created one highlight group per *exact* colour, in
--- a session-wide cache, and Neovim stops at 19 602 groups (measured
--- 2026-09-08). Enough images and `E849` ends the session's colouring for
--- good. `blocks` quantises to `levels` steps per channel, which caps the
--- count at `levels³` — 512 by default (8 levels).
---
--- Deliberately the single-image path only (`images.init.M.show`) — the same
--- scope boundary as remote images (see images.remote): gallery, compare,
--- pickers and zen do not get this (yet).
---
--- **Nothing here waits for ImageMagick.** The sample used to come from a
--- blocking `magick` on the main loop (`testing perf`: 138-230 ms per open, a
--- second blocking `magick identify` for the size on top), and the editor froze
--- for both. Now the float opens at once with a placeholder, its size from the
--- file's header (`images.pixels`, no process; `identify` runs in the
--- background only for a format whose header says nothing), the sample runs in
--- the background and is painted over the placeholder when it arrives. A
--- closed float, or one replaced by a newer open, drops the late answer: each
--- open gets a fresh token, `close()` forgets it. Samples are cached per file
--- (path, mtime, size), cell box and geometry, so showing the same picture
--- again starts no process at all.

local M = {}

local blocks = require("images.blocks")

local NS = vim.api.nvim_create_namespace("images.ascii")

--- Raw samples by `path:mtime:size:cols:rows:geometry`. A TTL like
--- `images.info`'s (PERF-42): a key never goes stale on its own, but a long
--- session looking at many pictures must not keep every one of them.
local samples = require("lib.nvim.cache.memory").namespace("images.ascii.samples", { ttl = 300 })

--- The currently open ASCII window, if there is one.
---@type integer|nil
local winid = nil

--- The open in flight: a fresh table per open, the late answer only acts while
--- it is still this one.
---@type table|nil
local pending = nil

---@return boolean
function M.is_open()
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

--- Whether the open float already shows the picture (and not the placeholder).
---@return boolean
function M.is_drawn()
  return M.is_open() and pending == nil
end

--- Close the window (a no-op when none is open), and drop an answer still on
--- its way.
---@return nil
function M.close()
  pending = nil
  if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
  winid = nil
end

---@param msg string
---@return nil
local function report(msg)
  require("lib.nvim.notify").create("[images]").error(msg)
end

--- The placeholder: blank rows over the canvas filler, a note in the middle.
--- It lives in the paint namespace, so the first paint replaces it.
---@param buf integer
---@param cols integer
---@param rows integer
---@return nil
local function placeholder(buf, cols, rows)
  local mid = math.floor((rows - 1) / 2)
  local note = "drawing…"
  for row = 0, rows - 1 do
    local text = (" "):rep(cols)
    if row == mid and cols >= vim.fn.strdisplaywidth(note) then
      local left = math.floor((cols - vim.fn.strdisplaywidth(note)) / 2)
      text = (" "):rep(left) .. note .. (" "):rep(cols - left - vim.fn.strdisplaywidth(note))
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, row, 0, {
      virt_text = { { text, "Comment" } },
      virt_text_pos = "overlay",
      virt_text_win_col = 0,
    })
  end
end

---@param path string
---@param cols integer
---@param rows integer
---@return string|nil key  nil when the file cannot be stat'ed
local function sample_key(path, cols, rows)
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil end
  return ("%s:%d:%d:%d:%d:%s"):format(path, stat.mtime and stat.mtime.sec or 0, stat.size, cols, rows, blocks.geometry().name)
end

--- Whether ImageMagick is available — this module's only prerequisite.
---@return boolean
function M.available()
  return blocks.available()
end

--- The cell box for a picture of `image_px` (nil: unknown, the whole box).
---@param display ImagesNvim.DisplayConfig
---@param image_px Images.Scale.MaybeDims|nil
---@return integer cols
---@return integer rows
local function box(display, image_px)
  -- `blocks.fit_cells`, not `images.scale.fit_cells`: a half block holds two
  -- pixels, which makes them square, and the other function corrects for a
  -- cell being twice as tall as it is wide. Using it here halves the picture.
  --
  -- 60/25 mirror `config.DEFAULTS.display.max_cols`/`max_rows` -- an invalid
  -- configured value degrades to the default instead of reaching the
  -- arithmetic in `fit_cells` as-is (ERR-22).
  local scale = require("images.scale")
  local max_cols = scale.valid_box(display.max_cols, 60)
  local max_rows = scale.valid_box(display.max_rows, 25)
  local px = (image_px and image_px.width and image_px.height) and { width = image_px.width, height = image_px.height } or nil
  return blocks.fit_cells(max_cols, max_rows, px)
end

--- Paint `raw` into the open float, or say why not. Ends the open either way.
---@param token table
---@param raw string|nil
---@param err string|nil
---@param key string|nil
---@param cols integer
---@param rows integer
---@param levels integer|nil
---@return nil
local function deliver(token, raw, err, key, cols, rows, levels)
  -- Remembered even when nobody waits for it any more: the sample is valid
  -- (`read_sampled` checked its size for the geometry in `key`), and the
  -- float closed before it arrived is the one most likely to be asked again.
  if raw and key then samples.set(key, raw) end
  if pending ~= token then return end -- closed, or replaced by a newer open
  if not M.is_open() then
    pending = nil
    return
  end
  if not raw then
    M.close()
    report(err or "the ASCII fallback failed")
    return
  end
  local buf = vim.api.nvim_win_get_buf(winid)
  local ok_call, ok_paint, paint_err = pcall(blocks.paint, buf, NS, raw, 1, cols, rows, levels)
  if not (ok_call and ok_paint) then
    M.close()
    report(tostring(ok_call and paint_err or ok_paint))
    return
  end
  pending = nil
end

--- Sample `path` into the open float: from the cache at once, else in the
--- background.
---@param token table
---@param path string
---@param cols integer
---@param rows integer
---@param levels integer|nil
---@return nil
local function fill(token, path, cols, rows, levels)
  local key = sample_key(path, cols, rows)
  local hit = key and samples.get(key)
  if hit then
    deliver(token, hit, nil, nil, cols, rows, levels)
    return
  end
  blocks.sample_async({ path }, cols, rows, function(raw, err)
    deliver(token, raw, err, key, cols, rows, levels)
  end)
end

--- Draw the image as coloured block graphics in a floating window under the
--- cursor.
---
--- Returns at once: the float opens with a placeholder, the picture follows
--- when ImageMagick has answered. A failure after this returns is said
--- through `vim.notify` and closes the float; the return value only covers
--- what is known up front (no ImageMagick, no file, no window).
---@param path string absolute path
---@param display ImagesNvim.DisplayConfig
---@return boolean ok
---@return string|nil err
function M.open(path, display)
  if not M.available() then return false, "the ASCII fallback requires ImageMagick (`magick` not found)" end
  if not vim.uv.fs_stat(path) then return false, "file not found: " .. path end

  -- The header, not `images.info.collect` (a blocking `magick identify`):
  -- the same number by a route without a process, as images.zen does.
  local header = require("images.pixels").read(path)
  local cols, rows = box(display, header)

  M.close()

  local win, buf = require("lib.nvim.window.make_scratch")({
    relative = "cursor",
    row = 1,
    col = 0,
    width = cols,
    height = rows,
    lines = blocks.canvas_lines(cols, rows),
    enter = false,
    focusable = false,
    border = "rounded",
    title = " ASCII (no OSC 1337) ",
  })
  if not win or not buf then return false, "could not open the ASCII window" end
  winid = win
  placeholder(buf, cols, rows)

  local token = {}
  pending = token

  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("WinClosed", function()
    if winid == win then
      winid = nil
      if pending == token then pending = nil end
    end
  end, {
    group = autocmd.group("images.ascii", true),
    pattern = tostring(win),
    once = true,
    desc = "images.ascii: clean up on close",
  })

  local levels = (display.ascii_fallback or {}).levels
  if header then
    fill(token, path, cols, rows, levels)
    return true
  end

  -- No size in the header (an SVG, a TIFF): ask ImageMagick, in the
  -- background too, and fit the float once it has answered.
  require("images.info").collect_async(path, function(info)
    if pending ~= token or not M.is_open() then return end
    local c, r = box(display, info)
    if c ~= cols or r ~= rows then
      local ok = pcall(function()
        vim.api.nvim_win_set_config(win, { width = c, height = r })
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, blocks.canvas_lines(c, r))
        vim.bo[buf].modifiable = false
        vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
        placeholder(buf, c, r)
      end)
      if not ok then
        M.close()
        report("could not resize the ASCII window")
        return
      end
    end
    fill(token, path, c, r, levels)
  end)
  return true
end

return M
