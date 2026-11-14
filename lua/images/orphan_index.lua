---@module 'images.orphan_index'
---@brief Images of a project that no document refers to, found in the background.
---@description
--- `images.orphans` answers for one buffer and its paste folder. This module answers for a whole
--- folder tree, for a reader that wants to mark the files (a tree view): which images lie in a paste
--- folder and are linked from no document below the root.
---
--- What counts, the same rule as `:Image orphans`, widened from one document to all of them:
---  - a document is a Markdown or HTML file (`DOC_EXTENSIONS`)
---  - a paste folder is `<folder of a document>/<paste.dir>` (the folder itself when `paste.dir` is
---    empty). Only images directly in a paste folder are judged: an image anywhere else may well be
---    unlinked for a good reason (an icon the code loads)
---  - an image is referred to when any document below the root links it: `![alt](target)`,
---    `[text](target)`, a reference definition `[label]: target`, `<img src="target">`, relative to
---    the document, absolute, or from the root (`/docs/a.png`); or embeds it the Obsidian way,
---    `![[name.png]]`, which names a file wherever it lies. Remote targets are no files
---
--- Every doubt goes one way: a link that might mean an image counts as one. A badge on an image that
--- is in use would invite deleting it.
---
--- The walk reads folders and documents with the synchronous calls, in slices: after `SLICE_MS` it
--- hands the editor back and goes on a moment later, so a large project costs many short steps and no
--- long one. A walk that hits `MAX_ENTRIES` did not see every document and therefore names no orphan
--- at all (`partial`), because a link it did not read would make an image look unlinked.
---
--- Not its job: drawing, deleting, deciding when to scan (`images.integrations.tree`).

local M = {}

local uv = vim.uv

---@type table<string, true>
M.DOC_EXTENSIONS = { md = true, markdown = true, mdx = true, qmd = true, rmd = true, html = true, htm = true }

---Folders that are never entered, besides every folder whose name starts with a dot.
---@type table<string, true>
M.SKIP_DIRS = { node_modules = true, target = true, dist = true, build = true }

---A walk stops (and reports `partial`) after this many directory entries.
M.MAX_ENTRIES = 50000

---A document larger than this is not read; the scan is `partial` then.
M.MAX_DOC_BYTES = 2 * 1024 * 1024

---How long one slice of a background scan may run, in milliseconds.
M.SLICE_MS = 8

---@class Images.OrphanIndex.Result
---@field root string                 The folder that was scanned (normalized).
---@field orphans table<string, true> The unreferenced images, by path (`/`, drive letter upper case).
---@field partial boolean             The walk was cut short: `orphans` is empty on purpose.
---@field images integer              Images in paste folders that were judged.
---@field docs integer                Documents that were read.

---One spelling for a path, the one a tree view uses for its keys: `/`-separated, the drive letter in
---upper case, no trailing slash.
---@param path string
---@return string
function M.norm(path)
  path = path:gsub("\\", "/")
  path = path:gsub("^(%a):", function(drive)
    return drive:upper() .. ":"
  end)
  if #path > 1 and path:sub(-1) == "/" and not path:match("^%a:/$") then path = path:sub(1, -2) end
  return path
end

local IS_WINDOWS = vim.fn.has("win32") == 1

---The key two spellings of one file share: on Windows the case does not tell files apart.
---@param path string normalized
---@return string
local function same_file_key(path)
  return IS_WINDOWS and path:lower() or path
end

---Take `.` and `..` out of a normalized path. A `..` above the top is dropped.
---@param path string
---@return string
function M.collapse(path)
  local head, rest = path:match("^(%a:/)(.*)$")
  if not head then
    head, rest = path:match("^(/)(.*)$")
  end
  if not head then
    head, rest = "", path
  end
  local parts = {}
  for part in rest:gmatch("[^/]+") do
    if part == ".." then
      parts[#parts] = nil
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return head .. table.concat(parts, "/")
end

---The file a link target names, or nil for what is no local file (a URL, a `data:` image, an anchor).
---The second result is the same target read from the root, for a target that starts with `/`.
---@param target string  as written in the document
---@param doc_dir string normalized
---@param root string    normalized
---@return string|nil path
---@return string|nil from_root
function M.target_path(target, doc_dir, root)
  target = vim.trim(target)
  -- `<path with spaces>` and `path "title"`
  target = target:match("^<(.*)>$") or target
  target = target:gsub("%s+[\"'].*$", "")
  if target == "" or target:match("^%a[%w+.-]*:[^/\\]") or target:match("^%a[%w+.-]+://") or target:sub(1, 1) == "#" then
    -- `scheme:rest` (data:, mailto:) and `scheme://`; a drive letter is one letter followed by a slash
    return nil
  end
  target = target:gsub("[?#].*$", "")
  target = target:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  target = target:gsub("\\", "/")
  if target == "" then return nil end
  if target:match("^%a:/") then return M.collapse(M.norm(target)) end
  if target:sub(1, 1) == "/" then return M.collapse(target), M.collapse(root .. target) end
  if target:sub(1, 1) == "~" then return nil end
  return M.collapse(doc_dir .. "/" .. target)
end

---The file names a line embeds the Obsidian way (`![[name.png]]`, `[[folder/name.png|alias]]`): the
---last path component, since such a link names a file wherever it lies in the vault.
---@param line string
---@return string[]
function M.wiki_names_in_line(line)
  local out = {}
  if not line:find("[[", 1, true) then return out end
  for inner in line:gmatch("%[%[([^%]]+)%]%]") do
    local target = vim.trim((inner:gsub("[|#].*$", "")))
    local name = target:gsub("\\", "/"):match("([^/]+)$")
    if name then out[#out + 1] = name end
  end
  return out
end

---Every link target of one line: Markdown links (markdown.nvim's scanner when it is there, see
---`images.resolve.links_in_line`), a reference definition (`[label]: target`) and the `src` of raw HTML.
---@param line string
---@return string[]
function M.targets_in_line(line)
  local out = {}
  local definition = line:match("^%s*%[[^%]]+%]:%s*(.+)$")
  if definition then out[#out + 1] = definition end
  if line:find("](", 1, true) then
    for _, link in ipairs(require("images.resolve").links_in_line(line)) do
      out[#out + 1] = link.target
    end
  end
  if line:find("src", 1, true) then
    for target in line:gmatch('src%s*=%s*"([^"]+)"') do
      out[#out + 1] = target
    end
    for target in line:gmatch("src%s*=%s*'([^']+)'") do
      out[#out + 1] = target
    end
  end
  return out
end

---@param path string
---@return string|nil text
local function read_file(path)
  local st = uv.fs_stat(path)
  if not st or st.size > M.MAX_DOC_BYTES then return nil end
  local fd = uv.fs_open(path, "r", 292)
  if not fd then return nil end
  local text = uv.fs_read(fd, st.size, 0)
  uv.fs_close(fd)
  return type(text) == "string" and text or nil
end

---The scan as a coroutine body: `pause()` is called between steps and may yield.
---@param root string
---@param pause fun()
---@return Images.OrphanIndex.Result
local function run(root, pause)
  root = M.norm(root)
  local resolve = require("images.resolve")
  local sub = require("images.config").get().paste.dir
  sub = type(sub) == "string" and sub:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "") or ""

  ---@type table<string, string[]>  folder -> the images directly in it
  local images_in = {}
  local docs, entries, partial = {}, 0, false
  local queue, head = { root }, 1
  while queue[head] do
    local dir = queue[head]
    head = head + 1
    local handle = uv.fs_scandir(dir)
    while handle do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then break end
      entries = entries + 1
      if entries > M.MAX_ENTRIES then
        partial = true
        break
      end
      local path = dir .. "/" .. name
      if kind == "directory" then
        -- a link to a folder is not followed: it may point back up
        if name:sub(1, 1) ~= "." and not M.SKIP_DIRS[name] then queue[#queue + 1] = path end
      elseif kind == "file" then
        local ext = (name:match("%.([%w]+)$") or ""):lower()
        if M.DOC_EXTENSIONS[ext] then
          docs[#docs + 1] = path
        elseif resolve.is_image(name) then
          local list = images_in[dir] or {}
          images_in[dir] = list
          list[#list + 1] = path
        end
      end
    end
    if partial then break end
    pause()
  end

  local referenced, referenced_names, paste_dirs, read = {}, {}, {}, 0
  if not partial then
    for _, doc in ipairs(docs) do
      local doc_dir = doc:match("^(.*)/[^/]+$") or root
      paste_dirs[sub ~= "" and M.collapse(doc_dir .. "/" .. sub) or doc_dir] = true
      local text = read_file(doc)
      if not text then
        -- too large or unreadable: its links are unknown
        partial = true
        break
      end
      read = read + 1
      for line in text:gmatch("[^\r\n]+") do
        for _, target in ipairs(M.targets_in_line(line)) do
          local path, from_root = M.target_path(target, doc_dir, root)
          if path then referenced[same_file_key(path)] = true end
          if from_root then referenced[same_file_key(from_root)] = true end
        end
        for _, name in ipairs(M.wiki_names_in_line(line)) do
          referenced_names[name:lower()] = true
        end
      end
      pause()
    end
  end

  local orphans, judged = {}, 0
  if not partial then
    for dir in pairs(paste_dirs) do
      for _, image in ipairs(images_in[dir] or {}) do
        judged = judged + 1
        local name = image:match("([^/]+)$") or image
        if not referenced[same_file_key(image)] and not referenced_names[name:lower()] then orphans[image] = true end
      end
    end
  end
  return { root = root, orphans = orphans, partial = partial, images = judged, docs = read }
end

---Scan `root` in one go (specs, and a caller that waits anyway).
---@param root string
---@return Images.OrphanIndex.Result
function M.scan_sync(root)
  return run(root, function() end)
end

---Scan `root` in the background: slices of `SLICE_MS` on the main loop, `on_done(result)` at the end.
---The returned function cancels the scan (`on_done` is then never called).
---@param root string
---@param on_done fun(result: Images.OrphanIndex.Result)
---@return fun() cancel
function M.scan(root, on_done)
  local cancelled = false
  local started = uv.hrtime()
  local co = coroutine.create(function()
    return run(root, function()
      if (uv.hrtime() - started) / 1e6 >= M.SLICE_MS then coroutine.yield() end
    end)
  end)
  local function step()
    if cancelled then return end
    started = uv.hrtime()
    local ok, result = coroutine.resume(co)
    if not ok then
      -- a scan that failed names no orphan; the reader keeps what it had
      return
    end
    if coroutine.status(co) == "dead" then
      on_done(result)
    else
      vim.defer_fn(step, 1)
    end
  end
  vim.schedule(step)
  return function()
    cancelled = true
  end
end

return M
