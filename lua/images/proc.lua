---@module 'images.proc'
---@brief One place for how images.nvim starts external programs: a timeout, and ImageMagick's resource limits.
---@description
--- Two problems share one fix:
---
--- * A `vim.system(...):wait()` without a timeout freezes Neovim for as long as the process hangs (antivirus
---   holding the file, a network share, a broken image). Every call that has to answer synchronously goes through
---   `M.sync`, which passes `timeout = process.timeout_ms` (one value, one config key).
--- * No `magick` call used to set `-limit memory`/`-limit time`, so ImageMagick was loosed on arbitrary user
---   files with only the system's `policy.xml` as protection. `M.magick` puts the limits right after the binary
---   name in every argv; the values are `process.magick_memory` and `process.magick_time_s`.
---
--- Neither is a prerequisite: `process = { magick_memory = false }` leaves that limit off.

local M = {}

---@return ImagesNvim.ProcessConfig
local function cfg()
  local ok, conf = pcall(function()
    return require("images.config").get().process
  end)
  if ok and type(conf) == "table" then return conf end
  return { timeout_ms = 20000, magick_memory = "512MiB", magick_time_s = 60 }
end

--- The timeout for one external call, in ms.
---@return integer
function M.timeout_ms()
  local v = cfg().timeout_ms
  if type(v) ~= "number" or v <= 0 then return 20000 end
  return v
end

--- `argv` (`{ "magick", ... }`) with the resource limits inserted after the binary. Anything else is returned
--- unchanged, so a caller can wrap an argv without checking what it starts.
---@param argv string[]
---@return string[]
function M.magick(argv)
  if argv[1] ~= "magick" then return argv end
  local conf = cfg()
  local out = { "magick" }
  if type(conf.magick_memory) == "string" and conf.magick_memory ~= "" then
    vim.list_extend(out, { "-limit", "memory", conf.magick_memory, "-limit", "map", conf.magick_memory })
  end
  if type(conf.magick_time_s) == "number" and conf.magick_time_s > 0 then
    vim.list_extend(out, { "-limit", "time", tostring(conf.magick_time_s) })
  end
  for i = 2, #argv do
    out[#out + 1] = argv[i]
  end
  return out
end

--- `vim.system` options with the shared timeout added.
---@param opts table|nil
---@return table
function M.opts(opts)
  return vim.tbl_extend("keep", opts or {}, { timeout = M.timeout_ms() })
end

--- Run `argv` to completion on the calling thread, but never longer than the timeout. A process that has to be
--- killed answers `timed_out = true` (and the exit code 124 `vim.system` reports).
---@param argv string[]
---@param opts table|nil  `vim.system` options
---@return vim.SystemCompleted result
---@return boolean timed_out
function M.sync(argv, opts)
  local ok, obj = pcall(vim.system, M.magick(argv), M.opts(opts))
  if not ok then return { code = -1, signal = 0, stdout = "", stderr = tostring(obj) }, false end
  local res = obj:wait()
  return res, res.code == 124
end

--- Async `vim.system` for an argv, with the limits and the timeout.
---@param argv string[]
---@param opts table|nil
---@param on_exit fun(result: vim.SystemCompleted)
---@return vim.SystemObj|nil
function M.async(argv, opts, on_exit)
  local ok, obj = pcall(vim.system, M.magick(argv), M.opts(opts), on_exit)
  return ok and obj or nil
end

return M
