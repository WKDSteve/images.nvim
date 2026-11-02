---@module 'images.cache'
---@brief Housekeeping for the three disk caches under `stdpath("cache")/images.nvim`.
---
--- `svg`, `pdf` and `remote` key their files on path + mtime (or the URL), so a changed source
--- leaves the old entry behind and nothing else ever removes it. `sweep` deletes what is older
--- than `cache.max_age_days` and then the oldest files of a cache until it fits `cache.max_size_mb`.
--- It runs once per session, a few seconds after the first cache directory is used, and never
--- touches a `.part` download younger than an hour.

local M = {}

M.NAMES = { "svg", "pdf", "remote" }

local PART_GRACE_S = 60 * 60
local SWEEP_DELAY_MS = 3000
local DAY_S = 24 * 60 * 60

local scheduled = false

---@return string
function M.root()
  return vim.fn.stdpath("cache") .. "/images.nvim"
end

---@return { max_age_days: number, max_size_mb: number }
local function limits()
  local ok, config = pcall(function()
    return require("images.config").get().cache
  end)
  local c = ok and type(config) == "table" and config or {}
  local function positive(v, default)
    return type(v) == "number" and v > 0 and v or default
  end
  return { max_age_days = positive(c.max_age_days, 30), max_size_mb = positive(c.max_size_mb, 200) }
end

---@class ImagesNvim.CacheFile
---@field path string
---@field size integer
---@field mtime integer

---The regular files of one cache directory (no recursion: the caches are flat).
---@param name string
---@return ImagesNvim.CacheFile[]
function M.files(name)
  local dir = M.root() .. "/" .. name
  local out = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return out end
  while true do
    local entry, kind = vim.uv.fs_scandir_next(handle)
    if not entry then break end
    local path = dir .. "/" .. entry
    local stat = (kind == "file" or kind == nil) and vim.uv.fs_stat(path) or nil
    if stat and stat.type == "file" then
      out[#out + 1] = { path = path, size = stat.size or 0, mtime = stat.mtime and stat.mtime.sec or 0 }
    end
  end
  return out
end

---Count and bytes of every cache (what `:checkhealth images` reports).
---@return table<string, { count: integer, bytes: integer }>
function M.stats()
  local out = {}
  for _, name in ipairs(M.NAMES) do
    local count, bytes = 0, 0
    for _, f in ipairs(M.files(name)) do
      count, bytes = count + 1, bytes + f.size
    end
    out[name] = { count = count, bytes = bytes }
  end
  return out
end

---Delete the files of every cache that are too old, then the oldest ones until each cache fits.
---@param opts? { now?: integer, max_age_days?: number, max_size_mb?: number }
---@return { removed: integer, freed: integer }
function M.sweep(opts)
  opts = opts or {}
  local lim = limits()
  local now = opts.now or os.time()
  local max_age = (opts.max_age_days or lim.max_age_days) * DAY_S
  local max_bytes = (opts.max_size_mb or lim.max_size_mb) * 1024 * 1024
  local removed, freed = 0, 0

  local function drop(f)
    if vim.uv.fs_unlink(f.path) then
      removed, freed = removed + 1, freed + f.size
      return true
    end
    return false
  end

  for _, name in ipairs(M.NAMES) do
    local keep, total = {}, 0
    for _, f in ipairs(M.files(name)) do
      local young_part = f.path:match("%.part$") and (now - f.mtime) < PART_GRACE_S
      if not young_part and (now - f.mtime) > max_age then
        if not drop(f) then
          keep[#keep + 1], total = f, total + f.size
        end
      else
        keep[#keep + 1], total = f, total + f.size
      end
    end
    if total > max_bytes then
      table.sort(keep, function(a, b)
        return a.mtime < b.mtime
      end)
      for _, f in ipairs(keep) do
        if total <= max_bytes then break end
        if not f.path:match("%.part$") and drop(f) then total = total - f.size end
      end
    end
  end
  return { removed = removed, freed = freed }
end

---Sweep once per session, a few seconds after the first cache directory is used.
function M.schedule_sweep()
  if scheduled then return end
  scheduled = true
  vim.defer_fn(function()
    pcall(M.sweep)
  end, SWEEP_DELAY_MS)
end

---@param bytes integer
---@return string
function M.format_bytes(bytes)
  if bytes >= 1024 * 1024 then return ("%.1f MB"):format(bytes / 1024 / 1024) end
  return ("%.1f KB"):format(bytes / 1024)
end

---Test hook: forget that the session sweep was scheduled.
function M._reset()
  scheduled = false
end

return M
