---@module 'images.integrations.tree'
---@brief A badge in a tree view on every image no document refers to.
---@description
--- Registers one decorator, `orphan`, at `lib.nvim.tree.registry`. A tree that reads the registry (the
--- own tree of filetree.nvim) draws its badge next to an image that lies in a paste folder and is
--- linked from no document of the project, and on a folder the number of such images below it
--- (`roll_up = "count"`). What counts as unreferenced is `images.orphan_index`'s rule.
---
--- The decorator's `get` is a table lookup. The table is filled by a scan of the working directory
--- that runs in the background, and only while a tree listens:
---  - when the first tree subscribes
---  - after a document or an image was written (`BufWritePost`), after a file operation of a tree
---    (`User FiletreeChanged`, `User FileopsChanged`) and after `:cd` (`DirChanged`), a moment later
---    and once for however many of them came together
---  - on demand: `require("images.integrations.tree").rescan()`
---
--- The home folder and the top of a drive are not scanned (`too_wide`): they are no project.
---
--- Nothing is scanned before a tree subscribes, and the autocommands go when the last one leaves.
---
--- Soft in both directions. The registry is lib.nvim's: without a tree that reads it the entry is never
--- looked at, and without a lib.nvim that has the registry nothing is registered.

local M = {}

M.NAME = "orphan"

---How long after the last change a scan starts, in milliseconds.
M.DEBOUNCE_MS = 400

---@class Images.Tree.Opts
---@field badge? string  The text of the badge (default "orphan").

local AUGROUP = "images.tree.orphans"

---@type fun()|nil
local unregister = nil
---@type table<string, table>  path -> badge
local badges = {}
---@type table<integer, fun(keys?: string[])>
local listeners = {}
local next_listener = 0
---@type fun()|nil  cancels the running scan
local cancel_scan = nil
---@type uv.uv_timer_t|nil
local timer = nil
local badge_text = "orphan"
---@type Images.OrphanIndex.Result|nil
local last = nil

---@param keys? string[]
local function tell(keys)
  for _, emit in pairs(listeners) do
    pcall(emit, keys)
  end
end

---Take the result of a scan: replace the table and name the keys that changed.
---@param result Images.OrphanIndex.Result
local function adopt(result)
  last = result
  local changed = {}
  for path in pairs(badges) do
    if not result.orphans[path] then changed[#changed + 1] = path end
  end
  local fresh = {}
  for path in pairs(result.orphans) do
    if not badges[path] then changed[#changed + 1] = path end
    fresh[path] = { text = badge_text, hl = "DiagnosticHint", status = "orphan", count = 1 }
  end
  badges = fresh
  if #changed > 0 then
    table.sort(changed)
    tell(changed)
  end
end

---Whether `root` is no project but a place everything lies below: the home folder, or the top of a
---drive. Walking it would read tens of thousands of entries after every written document, to end as a
---partial walk that names nothing anyway.
---@param root string
---@return boolean
function M.too_wide(root)
  local index = require("images.orphan_index")
  root = index.norm(root)
  if root == "/" or root:match("^%a:/?$") then return true end
  local home = vim.uv.os_homedir()
  return home ~= nil and index.norm(home):lower() == root:lower()
end

---Scan the working directory again, in the background. Without a listening tree nothing happens
---unless `force` is set (a caller that wants the table for itself).
---@param force? boolean
function M.rescan(force)
  if not force and next(listeners) == nil then return end
  if cancel_scan then cancel_scan() end
  cancel_scan = nil
  local root = vim.fn.getcwd()
  if M.too_wide(root) then
    adopt({ root = root, orphans = {}, partial = true, images = 0, docs = 0 })
    return
  end
  cancel_scan = require("images.orphan_index").scan(root, function(result)
    cancel_scan = nil
    adopt(result)
  end)
end

---`rescan` after `DEBOUNCE_MS` without another call.
local function rescan_soon()
  if not timer then timer = vim.uv.new_timer() end
  if not timer then
    M.rescan()
    return
  end
  timer:stop()
  timer:start(
    M.DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      M.rescan()
    end)
  )
end

local function start_listening()
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      local name = args.file or ""
      local ext = (name:match("%.([%w]+)$") or ""):lower()
      if require("images.orphan_index").DOC_EXTENSIONS[ext] or require("images.resolve").is_image(name) then rescan_soon() end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "FiletreeChanged", "FileopsChanged" },
    callback = rescan_soon,
  })
  vim.api.nvim_create_autocmd("DirChanged", { group = group, callback = rescan_soon })
end

local function stop_listening()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
  if cancel_scan then
    cancel_scan()
    cancel_scan = nil
  end
end

---What the last scan found, or nil before the first one ended (for `:checkhealth` and the specs).
---@return Images.OrphanIndex.Result|nil
function M.last_scan()
  return last
end

---Register the decorator. Without `lib.nvim.tree.registry` (an older lib.nvim) nothing happens.
---@param opts? Images.Tree.Opts
---@return boolean registered
function M.register(opts)
  local ok, registry = pcall(require, "lib.nvim.tree.registry")
  if not ok or type(registry.decorator) ~= "function" then return false end
  M.unregister()
  badge_text = type(opts) == "table" and type(opts.badge) == "string" and opts.badge ~= "" and opts.badge or "orphan"
  unregister = registry.decorator({
    name = M.NAME,
    key = "path",
    slot = "badge",
    priority = 20,
    roll_up = "count",
    get = function(path)
      return badges[path]
    end,
    all = function()
      return badges
    end,
    subscribe = function(emit)
      next_listener = next_listener + 1
      local id = next_listener
      local first = next(listeners) == nil
      listeners[id] = emit
      if first then
        start_listening()
        M.rescan()
      end
      return function()
        listeners[id] = nil
        if next(listeners) == nil then stop_listening() end
      end
    end,
  })
  return true
end

---Take the decorator out again and stop everything behind it.
function M.unregister()
  if unregister then
    unregister()
    unregister = nil
  end
  listeners = {}
  stop_listening()
  badges = {}
  last = nil
end

return M
