---@module 'images.info'
---@brief Determine an image file's metadata.
---@description
--- Format and dimensions come from ImageMagick, when it is present. Without
--- ImageMagick, the dimensions still come — `images.pixels` reads them out of
--- the file's own header — and so do size and modification time; only the
--- format name goes missing. The feature does not become useless, which is why
--- `magick` is deliberately optional.
---
--- ImageMagick goes first where both can answer: it opens the picture rather
--- than reading the first thirty bytes of it, so on a malformed file it is the
--- better judge. `images.pixels` is not a second opinion but the same number by
--- a cheaper route — see its own docs for why the draw path needs that route to
--- exist at all.

local M = {}

---@internal
--- Result cache, keyed by path plus modification time plus size.
---
--- `magick identify` runs through `vim.system(...):wait()` and therefore
--- blocks the UI thread. Going async is not straightforward here: all six
--- callers (`ascii`, `compare` — twice per comparison —, `init`, `redact`,
--- `zen`) need the dimensions immediately for their layout arithmetic, so the
--- return value is part of the contract. What is possible: not asking about
--- the same file over and over. Format and dimensions only change when the
--- file changes — and that is exactly what the key captures. `:Image compare`
--- saves half its calls that way, and any repeated display of the same image
--- saves all of them.
---
--- A TTL rather than an unbounded table (PERF-42, same reasoning as
--- `images.pixels`'s twin cache): a key never goes stale on its own, but
--- nothing ever removed an entry for a file no longer looked at either, so a
--- long session visiting many distinct images grew this table for its
--- lifetime with no way back short of a restart.
local cache = require("lib.nvim.cache.memory").namespace("images.info", { ttl = 300 })

---@class Images.Info : Images.Scale.MaybeDims
---@field path string absolute path
---@field bytes integer file size
---@field mtime integer modification time (Unix)
---@field format string|nil e.g. "PNG"
---@field width integer|nil pixels
---@field height integer|nil pixels

--- Format bytes for humans.
---@param bytes integer
---@return string
function M.human_size(bytes)
  local units = { "B", "KB", "MB", "GB" }
  local value, unit = bytes, 1
  while value >= 1024 and unit < #units do
    value = value / 1024
    unit = unit + 1
  end
  if unit == 1 then return ("%d %s"):format(value, units[unit]) end
  return ("%.1f %s"):format(value, units[unit])
end

---@internal
--- The half before ImageMagick: the stat, the cache key and the skeleton both
--- forms of `collect` fill.
---@param path string
---@return Images.Info|nil info
---@return string|nil key  nil together with `info` on a cache hit
---@return string|nil err
local function begin(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, nil, "file not found: " .. path end

  local mtime = stat.mtime and stat.mtime.sec or 0
  local key = ("%s:%d:%d"):format(path, mtime, stat.size)
  local hit = cache.get(key)
  if hit then return hit, nil, nil end
  return { path = path, bytes = stat.size, mtime = mtime }, key, nil
end

--- `identify` as a subcommand of `magick`, not as its own binary: on Windows
--- `convert.exe`/`identify.exe` collide with the system programs of the same
--- name in System32.
---@param path string
---@return string[]
local function identify_argv(path)
  return { "magick", "identify", "-format", "%m %w %h", path .. "[0]" }
end

---@internal
--- The half after ImageMagick (`res` nil when it was not asked): read its
--- answer, let the header fill what it could not say, remember the result.
---@param info Images.Info
---@param key string
---@param res vim.SystemCompleted|nil
---@return Images.Info
local function finish(info, key, res)
  if res and res.code == 0 and type(res.stdout) == "string" then
    local fmt, w, h = res.stdout:match("^(%S+)%s+(%d+)%s+(%d+)")
    info.format = fmt
    info.width = tonumber(w)
    info.height = tonumber(h)
  end

  -- Whatever ImageMagick could not say -- because it is not installed, or
  -- because `identify` failed on this file -- the header may still say.
  if not (info.width and info.height) then
    local px = require("images.pixels").read(info.path)
    if px then
      info.width, info.height = px.width, px.height
    end
  end

  cache.set(key, info)
  return info
end

--- Collect metadata.
---@param path string absolute path
---@return Images.Info|nil
---@return string|nil err
function M.collect(path)
  local info, key, err = begin(path)
  if not info then return nil, err end
  if not key then return info end

  local res = nil
  if require("lib.nvim.cross.executable").exists("magick") then
    res = require("images.proc").sync(identify_argv(path), { text = true })
  end
  return finish(info, key, res)
end

--- Same, without blocking: `magick identify` runs in the background and
--- `callback(info, err)` runs on the main loop exactly once -- also on a cache
--- hit, and also when the process could not even be started. The same cache as
--- `collect`, so either form answers the other's file for free.
---@param path string absolute path
---@param callback fun(info: Images.Info|nil, err: string|nil)
---@return nil
function M.collect_async(path, callback)
  local info, key, err = begin(path)
  if not info or not key then
    vim.schedule(function()
      callback(info, err)
    end)
    return
  end

  local function answer(res)
    vim.schedule(function()
      local ok, result = pcall(finish, info, key, res)
      if ok then
        callback(result, nil)
      else
        callback(nil, tostring(result))
      end
    end)
  end

  if not require("lib.nvim.cross.executable").exists("magick") then
    answer(nil)
    return
  end
  if not require("images.proc").async(identify_argv(path), { text = true }, answer) then answer(nil) end
end

--- Metadata as lines, ready to display.
---@param info Images.Info
---@return string[]
function M.lines(info)
  local out = {
    "Path:     " .. vim.fn.fnamemodify(info.path, ":~"),
    "Size:     " .. M.human_size(info.bytes),
  }
  if info.width and info.height then
    table.insert(out, 2, ("Format:   %s %dx%d"):format(info.format or "?", info.width, info.height))
  elseif not require("lib.nvim.cross.executable").exists("magick") then
    out[#out + 1] = "Format:   (ImageMagick not installed)"
  end
  if info.mtime > 0 then out[#out + 1] = "Modified: " .. os.date("%Y-%m-%d %H:%M", info.mtime) end
  return out
end

return M
