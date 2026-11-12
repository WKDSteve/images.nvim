---@module 'images.export_set'
---@brief Which images `:Image export <dir|glob>` puts into one PDF: the matching files, in natural order.

local M = {}

---Does `spec` name a set of files (a glob or a directory) rather than one file?
---@param spec string|nil
---@return boolean
function M.is_set(spec)
  if type(spec) ~= "string" or spec == "" then return false end
  if vim.fn.filereadable(vim.fs.normalize(spec)) == 1 then return false end
  if spec:find("[*?%[]") then return true end
  return vim.fn.isdirectory(vim.fs.normalize(spec)) == 1
end

---Natural order: `page2.png` before `page10.png`, case ignored, equal keys fall back to plain order so the sort
---is deterministic.
---@param a string
---@param b string
---@return boolean
local function natural_less(a, b)
  local function key(s)
    return (s:lower():gsub("%d+", function(n)
      return ("%012d"):format(tonumber(n) or 0)
    end))
  end
  local ka, kb = key(a), key(b)
  if ka ~= kb then return ka < kb end
  return a < b
end

---The image files `spec` names: every file of a directory, or every match of a glob (`**` recurses), kept when its
---extension is one of `extensions`, sorted naturally by full path.
---@param spec string a directory or a glob
---@param extensions string[]|nil defaults to the configured `extensions`
---@return string[] files absolute, `/`-separated
function M.collect(spec, extensions)
  extensions = extensions or require("images.config").get().extensions
  if type(extensions) ~= "table" then extensions = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg" } end
  local allowed = {}
  for _, ext in ipairs(extensions) do
    allowed[tostring(ext):lower()] = true
  end

  -- `normalize` expands `~` and `$VAR` but, unlike `expand()`, leaves `*` and `[` alone
  local expanded = vim.fs.normalize(spec)
  ---@type string[]
  local candidates
  if vim.fn.isdirectory(expanded) == 1 then
    -- a directory is listed, not globbed: a name with `[` or `*` in it is a name here, not a pattern
    local dir = (expanded:gsub("/+$", ""))
    candidates = vim.tbl_map(function(name)
      return dir .. "/" .. name
    end, vim.fn.readdir(dir))
  else
    candidates = vim.fn.glob(expanded, false, true)
  end

  local out = {}
  for _, f in ipairs(candidates) do
    local ext = f:match("%.([^./\\]+)$")
    if ext and allowed[ext:lower()] and vim.fn.filereadable(f) == 1 then
      out[#out + 1] = vim.fs.normalize(vim.fn.fnamemodify(f, ":p"))
    end
  end
  table.sort(out, natural_less)
  return out
end

---Ask whether a large set should really become one PDF. Replaceable (`require("images.export_set").confirm = ...`).
---@param n integer
---@return boolean
function M.confirm(n)
  return vim.fn.confirm(("Export %d images as one PDF?"):format(n), "&Yes\n&No", 2) == 1
end

return M
