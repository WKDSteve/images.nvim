---@module 'images.integrations.tree'
---@brief In a tree view: a badge on every image no document refers to, and two actions about them.
---@description
--- Entries at `lib.nvim.tree.registry`, read by a tree that knows the registry (the own tree of
--- filetree.nvim).
---
--- **The decorator `orphan`.** A badge next to an image that lies in a paste folder and is linked from
--- no document of the project, and on a folder the number of such images below it
--- (`roll_up = "count"`). What counts as unreferenced is `images.orphan_index`'s rule.
---
--- The decorator's `get` is a table lookup. The table is filled by scans that run in the background,
--- one per root a listening tree shows, and only while a tree listens:
---  - a root is scanned when a tree first shows it: the tree says which roots there are
---    (`ctx.roots()`, the second argument of `subscribe`) and when they change (`User FiletreeRoots`).
---    The other roots are left alone then, and what was found below a root no tree shows any more is
---    forgotten
---  - every root again after a document or an image was written (`BufWritePost`) and after a file
---    operation of a tree (`User FiletreeChanged`, `User FileopsChanged`), a moment later and once for
---    however many of them came together
---  - on demand: `require("images.integrations.tree").rescan()`, and the action below
---
--- A tree that hands no context (a filetree.nvim before `FiletreeRoots`) stands for the working
--- directory, scanned again after `:cd` (`DirChanged`).
---
--- Two roots, one below the other: an image is unreferenced only when every finished scan that covers
--- it says so. The wider one may know a document the narrower one never saw.
---
--- The home folder and the top of a drive are not scanned (`too_wide`): they are no project.
---
--- **Two actions**, in the menu of the tree and on a key where one is configured (`tree.keys`):
---
---   images.orphan.delete  on an image that carries the badge: delete it. Through the tree's own trash
---                         where the tree has one (what its delete key does: its question, its undo),
---                         else for good after a question of its own. The image is judged once more
---                         right before, and the badge goes without a scan of the project: an image
---                         that is gone after a file operation loses it at once (`prune`)
---   images.orphan.rescan  on a folder: look for unreferenced images again, and say how many there are
---
--- Nothing is scanned before a tree subscribes, and the autocommands go when the last one leaves.
---
--- Soft in both directions. The registry is lib.nvim's: without a tree that reads it the entries are
--- never looked at, without a lib.nvim that has the registry nothing is registered, and a registry
--- without actions gets the decorator alone.

local M = {}

M.NAME = "orphan"
M.DELETE = "images.orphan.delete"
M.RESCAN = "images.orphan.rescan"

---How long after the last change a scan starts, in milliseconds.
M.DEBOUNCE_MS = 400

---@class Images.Tree.Opts
---@field badge? string  The text of the badge (default "orphan").
---@field actions? boolean  false: the two actions are not registered.
---@field keys? { delete?: string|string[], rescan?: string|string[] }  A key per action; without one the action is in the menu only.

local AUGROUP = "images.tree.orphans"

---One tree that listens: what it wants to be told, and where it says which roots the trees show.
---@class Images.Tree.Listener
---@field emit fun(keys?: string[])
---@field ctx? { roots?: fun(): string[] }  What `subscribe` was handed next to `emit`; nil with a tree that hands none.

---The scan of one root.
---@class Images.Tree.Scan
---@field cancel? fun()  Set while the scan runs.
---@field token? table  Names the run whose answer is waited for.
---@field result? Images.OrphanIndex.Result  What the last finished scan of this root found.

---@type fun()|nil
local unregister_decorator = nil
---@type (fun())[]
local unregister_actions = {}
---@type table<string, table>  path -> badge
local badges = {}
---@type table<integer, Images.Tree.Listener>
local listeners = {}
local next_listener = 0
---@type table<string, Images.Tree.Scan>  by root (normalized)
local scans = {}
---@type uv.uv_timer_t|nil
local timer = nil
local badge_text = "orphan"
---@type Images.OrphanIndex.Result|nil
local last = nil
---Set by the action "look again": the next time no scan is on its way, say what was found.
local announce = false

---@param message string
---@param level? integer
local function say(message, level)
  vim.notify("images.nvim: " .. message, level or vim.log.levels.INFO)
end

---@param keys? string[]
local function tell(keys)
  for _, listener in pairs(listeners) do
    pcall(listener.emit, keys)
  end
end

---Whether `path` lies below `root` (both normalized).
---@param path string
---@param root string
---@return boolean
local function below(path, root)
  local prefix = root:sub(-1) == "/" and root or root .. "/"
  return path:sub(1, #prefix) == prefix
end

---Put the table together again from what the scans found, and name the keys that changed.
local function rebuild()
  ---@type table<string, true>
  local found = {}
  for _, scan in pairs(scans) do
    local result = scan.result
    if result and not result.partial then
      for path in pairs(result.orphans) do
        found[path] = true
      end
    end
  end
  -- Every doubt goes one way: a finished scan that covers the image and does not name it has read a
  -- document that links it (a root above the one that named it sees more documents).
  for path in pairs(found) do
    for root, scan in pairs(scans) do
      local result = scan.result
      if result and not result.partial and below(path, root) and not result.orphans[path] then
        found[path] = nil
        break
      end
    end
  end
  local changed = {}
  for path in pairs(badges) do
    if not found[path] then changed[#changed + 1] = path end
  end
  local fresh = {}
  for path in pairs(found) do
    if not badges[path] then changed[#changed + 1] = path end
    fresh[path] = { text = badge_text, hl = "DiagnosticHint", status = "orphan", count = 1 }
  end
  badges = fresh
  if #changed > 0 then
    table.sort(changed)
    tell(changed)
  end
end

---Whether a scan is on its way.
---@return boolean
local function scanning()
  for _, scan in pairs(scans) do
    if scan.cancel or scan.token then return true end
  end
  return false
end

---Say how many images carry the badge.
local function report()
  local n = vim.tbl_count(badges)
  say(n == 0 and "no unreferenced image" or ("%d unreferenced image%s"):format(n, n == 1 and "" or "s"))
end

---Take the result of the scan of `root`.
---@param root string
---@param result Images.OrphanIndex.Result
local function adopt(root, result)
  local scan = scans[root]
  if not scan then return end
  scan.cancel = nil
  scan.result = result
  last = result
  rebuild()
  if announce and not scanning() then
    announce = false
    report()
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

---The folders to scan: the roots the listening trees show (`ctx.roots()`), each once and sorted. A
---tree that hands no context (an older filetree.nvim) stands for the working directory, and so does
---nobody listening at all (a caller that forces a scan).
---@return string[] roots
---@return boolean cwd  Whether the working directory is among them because somebody could not say.
function M.roots()
  local norm = require("images.orphan_index").norm
  local seen, out = {}, {}
  ---@param root any
  local function add(root)
    if type(root) ~= "string" or root == "" then return end
    root = norm(root)
    if seen[root] then return end
    seen[root] = true
    out[#out + 1] = root
  end
  local cwd = next(listeners) == nil
  for _, listener in pairs(listeners) do
    local ask = type(listener.ctx) == "table" and listener.ctx.roots or nil
    local ok, roots = false, nil
    if type(ask) == "function" then
      ok, roots = pcall(ask)
    end
    if ok and type(roots) == "table" then
      for _, root in ipairs(roots) do
        add(root)
      end
    else
      cwd = true
    end
  end
  if cwd then add(vim.fn.getcwd()) end
  table.sort(out)
  return out, cwd
end

---Start the scan of `root`, in place of one that is still on its way there.
---@param root string
local function start(root)
  local scan = scans[root] or {}
  scans[root] = scan
  if scan.cancel then scan.cancel() end
  scan.cancel = nil
  scan.token = nil
  if M.too_wide(root) then
    adopt(root, { root = root, orphans = {}, partial = true, images = 0, docs = 0 })
    return
  end
  -- a scan that was replaced may answer all the same: only the run that is waited for is taken
  local token = {}
  scan.token = token
  local cancel = require("images.orphan_index").scan(root, function(result)
    if scans[root] ~= scan or scan.token ~= token then return end
    scan.token = nil
    adopt(root, result)
  end)
  if scan.token == token then scan.cancel = cancel end
end

---Give up the scans of roots no tree shows any more. Returns whether one went.
---@param wanted string[]
---@return boolean
local function drop_unwanted(wanted)
  local keep, dropped = {}, false
  for _, root in ipairs(wanted) do
    keep[root] = true
  end
  for root, scan in pairs(scans) do
    if not keep[root] then
      if scan.cancel then scan.cancel() end
      scans[root] = nil
      -- what the documents of that project linked is not kept for a tree that is gone
      require("images.orphan_index").clear_cache(root)
      dropped = true
    end
  end
  return dropped
end

---Scan every root again, in the background (see `roots`). Without a listening tree nothing happens
---unless `force` is set (a caller that wants the table for itself).
---@param force? boolean
function M.rescan(force)
  if not force and next(listeners) == nil then return end
  local wanted = M.roots()
  local dropped = drop_unwanted(wanted)
  for _, root in ipairs(wanted) do
    start(root)
  end
  if dropped then rebuild() end
end

---Follow the roots of the trees: scan a root that is new, forget one that is gone, and leave the
---others alone (`User FiletreeRoots`, and a tree that comes or goes).
function M.sync()
  if next(listeners) == nil then return end
  local wanted = M.roots()
  local dropped = drop_unwanted(wanted)
  for _, root in ipairs(wanted) do
    if not scans[root] then start(root) end
  end
  if dropped then rebuild() end
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
    callback = function()
      -- an image that went (trashed in the tree, by the action below or by hand) loses its badge now;
      -- what else the operation changed is the scan's to find, a moment later
      M.prune()
      rescan_soon()
    end,
  })
  -- a tree was made, rooted elsewhere or given up
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FiletreeRoots",
    callback = function()
      M.sync()
    end,
  })
  -- the working directory is a root only for a tree that cannot say which one it shows
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      local _, cwd = M.roots()
      if cwd then rescan_soon() end
    end,
  })
end

local function stop_listening()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
  for _, scan in pairs(scans) do
    if scan.cancel then scan.cancel() end
  end
  scans = {}
  announce = false
end

---What the last scan that ended found, or with `root` what the scan of that root found; nil before
---it ended (for `:checkhealth` and the specs).
---@param root? string
---@return Images.OrphanIndex.Result|nil
function M.last_scan(root)
  if root == nil then return last end
  local scan = scans[require("images.orphan_index").norm(root)]
  return scan and scan.result or nil
end

-- ── the actions ──────────────────────────────────────────────────────────────

---Whether `path` carries the badge right now (a table lookup).
---@param path any
---@return boolean
function M.is_orphan(path)
  return type(path) == "string" and badges[path] ~= nil
end

---Take the images that are no longer on disk out of what the scans found: their badges go, and
---nothing is scanned. One `stat` per image that carries the badge.
function M.prune()
  local gone = false
  for path in pairs(badges) do
    if not vim.uv.fs_stat(path) then
      gone = true
      for _, scan in pairs(scans) do
        if scan.result then scan.result.orphans[path] = nil end
      end
    end
  end
  if gone then rebuild() end
end

---Judge `path` once more, now: the table is as old as the last scan, and a document written since may
---link the image. The widest root that covers it is walked in one go (the links of unchanged documents
---come from the cache, so this asks every document for its time and reads the changed ones).
---@param path string normalized
---@return boolean orphan  false also when the walk was cut short: no proof, no delete
function M.still_orphan(path)
  local widest
  for root in pairs(scans) do
    if below(path, root) and (not widest or #root < #widest) then widest = root end
  end
  if not widest or M.too_wide(widest) then return false end
  local result = require("images.orphan_index").scan_sync(widest)
  return not result.partial and result.orphans[path] == true
end

---The trash of the tree, when filetree.nvim is loaded and has one that works here: it asks in the
---tree's own dialog (one question for several images) and can undo. Never loads the plugin.
---@return { delete_current: fun(opts: { paths: string[] }) }|nil
local function tree_trash()
  local filetree = package.loaded["filetree"]
  if type(filetree) ~= "table" or type(filetree.feature) ~= "function" then return nil end
  local ok, trash = pcall(filetree.feature, "trash")
  if not ok or type(trash) ~= "table" or type(trash.delete_current) ~= "function" then return nil end
  if type(trash.available) == "function" then
    local asked, available = pcall(trash.available)
    if not asked or not available then return nil end
  end
  return trash
end

---Delete unreferenced images: the ones among `paths` that carry the badge and are still unreferenced
---when asked once more.
---
---Where the tree has a trash they are handed to it (`delete_current({ paths })`, what its own delete
---key does: its question, its undo). It answers later; the badges go when it says that files changed
---(`User FiletreeChanged`, see `prune`). Without one they are deleted for good after one question for
---all of them, and the badges go at once.
---@param paths string[]
---@return string[] targets  the images that were up for deletion (handed to the tree, or asked about)
function M.delete(paths)
  local norm = require("images.orphan_index").norm
  local targets, stale = {}, 0
  for _, path in ipairs(paths) do
    path = norm(path)
    if M.is_orphan(path) then
      if M.still_orphan(path) then
        targets[#targets + 1] = path
      else
        stale = stale + 1
      end
    end
  end
  if stale > 0 then
    say(
      ("%d image%s linked by now, or the project could not be read to the end: not deleted"):format(
        stale,
        stale == 1 and " is" or "s are"
      ),
      vim.log.levels.WARN
    )
    -- the table said otherwise: bring it up to date
    M.rescan()
  end
  if #targets == 0 then return targets end

  local trash = tree_trash()
  if trash then
    local ok, err = pcall(trash.delete_current, { paths = targets })
    if not ok then say("the trash of the tree failed: " .. tostring(err), vim.log.levels.WARN) end
    return targets
  end

  local names = {}
  for _, path in ipairs(targets) do
    names[#names + 1] = "  " .. (path:match("([^/]+)$") or path)
  end
  local question = ("Delete %s for good (no document links %s)?\n%s"):format(
    #targets == 1 and "this image" or (#targets .. " images"),
    #targets == 1 and "it" or "them",
    table.concat(names, "\n")
  )
  if vim.fn.confirm(question, "&Delete\n&Cancel", 2) ~= 1 then return targets end
  local orphans = require("images.orphans")
  local deleted = 0
  for _, path in ipairs(targets) do
    local ok, err = orphans.delete(path)
    if ok then
      deleted = deleted + 1
    else
      say(("could not delete %s: %s"):format(path, tostring(err)), vim.log.levels.WARN)
    end
  end
  if deleted > 0 then
    M.prune()
    -- a tree shows a file that is gone until it is told
    pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "FileopsChanged", modeline = false })
  end
  return targets
end

---Look for unreferenced images again and say how many there are when the scans are through.
function M.look_again()
  if next(listeners) == nil then
    say("no tree shows the badges: nothing to look for")
    return
  end
  -- not before the scans are started: a root that is not walked at all (too wide) answers while the
  -- others have not begun, and the line would count what the old scans found
  announce = false
  M.rescan()
  if scanning() then
    announce = true
  else
    report()
  end
end

---What the tree is told about the two actions.
---@return table[]
local function action_specs()
  return {
    {
      id = "delete",
      name = M.DELETE,
      desc = "Delete this unreferenced image (images.nvim)",
      needs = { "file" },
      when = function(node)
        return M.is_orphan(node.path)
      end,
      mutates = true,
      run = function(nodes)
        local paths = {}
        for _, node in ipairs(nodes) do
          if type(node.path) == "string" then paths[#paths + 1] = node.path end
        end
        M.delete(paths)
      end,
    },
    {
      id = "rescan",
      name = M.RESCAN,
      desc = "Look for unreferenced images again (images.nvim)",
      needs = { "dir" },
      mutates = false,
      run = function()
        M.look_again()
      end,
    },
  }
end

-- ── registering ──────────────────────────────────────────────────────────────

---Register the decorator and, where the registry takes them, the two actions. Without
---`lib.nvim.tree.registry` (an older lib.nvim) nothing happens.
---@param opts? Images.Tree.Opts
---@return boolean registered
function M.register(opts)
  local ok, registry = pcall(require, "lib.nvim.tree.registry")
  if not ok or type(registry.decorator) ~= "function" then return false end
  M.unregister()
  opts = type(opts) == "table" and opts or {}
  badge_text = type(opts.badge) == "string" and opts.badge ~= "" and opts.badge or "orphan"
  unregister_decorator = registry.decorator({
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
    -- `ctx` (filetree.nvim hands it since `User FiletreeRoots` exists): where to ask for the roots
    subscribe = function(emit, ctx)
      next_listener = next_listener + 1
      local id = next_listener
      local first = next(listeners) == nil
      listeners[id] = { emit = emit, ctx = type(ctx) == "table" and ctx or nil }
      if first then start_listening() end
      M.sync()
      return function()
        listeners[id] = nil
        if next(listeners) == nil then
          stop_listening()
        else
          M.sync()
        end
      end
    end,
  })
  if opts.actions ~= false and type(registry.action) == "function" then
    local keys = type(opts.keys) == "table" and opts.keys or {}
    for _, spec in ipairs(action_specs()) do
      local key = keys[spec.id]
      unregister_actions[#unregister_actions + 1] = registry.action({
        name = spec.name,
        desc = spec.desc,
        -- a key only where one is configured: the actions are in the menu of the tree
        key = (type(key) == "string" or type(key) == "table") and key or nil,
        needs = spec.needs,
        when = spec.when,
        mutates = spec.mutates,
        run = spec.run,
      })
    end
  end
  return true
end

---Take the entries out again and stop everything behind them.
function M.unregister()
  for _, remove in ipairs(unregister_actions) do
    remove()
  end
  unregister_actions = {}
  if unregister_decorator then
    unregister_decorator()
    unregister_decorator = nil
  end
  listeners = {}
  stop_listening()
  badges = {}
  last = nil
end

return M
