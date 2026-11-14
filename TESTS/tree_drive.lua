-- TESTS/tree_drive.lua -- images.nvim in the real own tree of filetree.nvim: the orphan badge next to an
-- unreferenced image and on its folders, and what the tree does with an image node when images.nvim is
-- installed (the preview key, <CR>, the entries "Image info" and "OCR" of its context menu).
--
-- Not a spec of the suite (no `_spec` in the name): filetree.nvim is no dependency of images.nvim, and the
-- state of a sibling checkout must not decide about this suite. A hand run, on filetree.nvim's bench
-- `TESTS/native_drive.lua`, which sets up the editor and quits it:
--
--   FILETREE_NVIM_DIR=<checkout> nvim --clean --headless -u NONE -l TESTS/tree_drive.lua
--
-- A headless editor has no terminal that draws pictures, so the four entry points of images.nvim the tree
-- calls (`show`, `zen`, `info`, `ocr`) are replaced by recorders: the question here is whether the tree
-- reaches them with the path of the node, not what they draw (that is the suite's and the hand probe's).

---@diagnostic disable: need-check-nil, duplicate-set-field

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h"):gsub("\\", "/")
local plugin = vim.fs.dirname(here)
vim.opt.rtp:prepend(plugin)

local filetree = (vim.env.FILETREE_NVIM_DIR or ""):gsub("\\", "/")
if filetree == "" or not vim.uv.fs_stat(filetree .. "/TESTS/native_drive.lua") then
  io.stdout:write("  n/a  $FILETREE_NVIM_DIR names no filetree.nvim: nothing was run\n")
  vim.cmd("cq")
  return
end
-- the bench looks for lib.nvim and ui.nvim next to filetree.nvim, or where these name them
for _, dep in ipairs({ "lib.nvim", "ui.nvim" }) do
  local var = dep:upper():gsub("%.", "_") .. "_DIR"
  local sibling = vim.fs.dirname(plugin) .. "/" .. dep
  if (vim.env[var] or "") == "" and vim.uv.fs_stat(sibling .. "/lua") then vim.env[var] = sibling end
end
-- nothing of the person's own setup: the stored calibration and the caches go to a temp folder
local scratch = vim.fn.tempname():gsub("\\", "/")
vim.fn.mkdir(scratch, "p")
for _, var in ipairs({ "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME" }) do
  vim.env[var] = scratch
end

-- a 1x1 PNG
local PNG = "\137PNG\r\n\26\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\8\6\0\0\0\31\21\196\137"
  .. "\0\0\0\rIDATx\156c\248\207\192\240\31\0\5\0\1\255\137\153=\29\0\0\0\0IEND\174B`\130"

local images
local calls = {}
local T = dofile(filetree .. "/TESTS/native_drive.lua")({
  name = "tree_drive (images.nvim)",
  files = { "README.md", "docs/guide.md", "docs/assets/a.png", "docs/assets/b.png", "lua/init.lua" },
  features = { preview = { enabled = true } },
  before_setup = function(T)
    for _, rel in ipairs({ "docs/assets/a.png", "docs/assets/b.png" }) do
      local fd = assert(io.open(T.dir .. "/" .. rel, "wb"))
      fd:write(PNG)
      fd:close()
    end
    T.mkfile("docs/guide.md", { "# Guide", "", "![a](assets/a.png)" })
    images = require("images")
    images.setup({ deps_popup = false, display = { terminal_probe = false } })
    for _, fn in ipairs({ "show", "zen", "info", "ocr" }) do
      assert(type(images[fn]) == "function", "images." .. fn .. " is what the tree calls")
      images[fn] = function(path, opts)
        calls[#calls + 1] = { fn = fn, path = path and T.norm(path), opts = opts }
        return true
      end
    end
  end,
})

local dir = T.dir
local function has(name, text, needle)
  T.ok(name .. "  -- " .. vim.inspect(text), type(text) == "string" and text:find(needle, 1, true) ~= nil)
end
---The calls since `from` as "fn path" lines, the path relative to the project.
local function called(from)
  local out = {}
  for i = from, #calls do
    out[#out + 1] = calls[i].fn .. " " .. tostring(calls[i].path):sub(#dir + 2)
  end
  return out
end

-- ── the orphan badge ─────────────────────────────────────────────────────────
T.on("docs/assets/b.png")
T.ok(
  "an image no document links gets the badge, once the background scan ended",
  T.wait(function()
    return T.drawn("docs/assets/b.png").text:find("orphan", 1, true) ~= nil
  end, 5000)
)
T.eq("the linked image next to it has none", T.drawn("docs/assets/a.png").text, "")
has("its folder counts it", T.drawn("docs/assets").text, "1")
has("... and so does the folder above", T.drawn("docs").text, "1")
T.eq("a folder without one shows nothing", T.drawn("lua").text, "")

-- ── the preview key and <CR> on an image node ────────────────────────────────
local mark = T.mark()
local from = #calls + 1
T.on("docs/assets/a.png")
T.feed("<Tab>")
T.wait(function()
  return #calls >= from
end)
T.eq("<Tab> on an image hands it to images.nvim", called(from), { "show docs/assets/a.png" })

from = #calls + 1
T.on("docs/assets/a.png")
T.feed("<CR>")
T.wait(function()
  return #calls >= from
end)
T.eq("<CR> on an image opens the zen float of images.nvim", called(from), { "zen docs/assets/a.png" })
T.ok("... with a size", type(calls[#calls].opts) == "table" and calls[#calls].opts.width ~= nil)
T.eq("neither says anything at warning level", T.loud(mark), {})
T.close_floats()

-- ── the context menu of an image node ────────────────────────────────────────
require("ui.contextmenu").setup({ renderer = "kit" })
local tree_win = T.adapter.get_winid()
local function pointer(win, line)
  vim.fn.getmousepos = function()
    return { winid = win, line = line, column = 4, screenrow = vim.fn.screenpos(win, line, 1).row, screencol = 4 }
  end
end
local function menu_entry(label)
  for _, float in ipairs(T.floats()) do
    for i, text in ipairs(float.lines) do
      if text:find(label, 1, true) then return float.win, i end
    end
  end
  return nil, nil
end
---Right click on `rel` and pick the entry whose text contains `label`.
local function pick(rel, label)
  T.tree()
  local line = T.adapter.get_node_line(T.on(rel))
  pointer(tree_win, line)
  T.feed("<RightMouse>")
  local win, entry_line = menu_entry(label)
  if not win then return false end
  vim.api.nvim_win_set_cursor(win, { entry_line, 0 })
  T.feed("<CR>")
  return true
end

T.tree()
pointer(tree_win, T.adapter.get_node_line(T.on("docs/assets/b.png")))
T.feed("<RightMouse>")
T.ok("the menu of an image offers its preview", (menu_entry("Preview image")) ~= nil)
T.ok("... the image info of images.nvim", (menu_entry("Image info")) ~= nil)
T.ok("... and OCR", (menu_entry("OCR")) ~= nil)
T.close_floats()

from = #calls + 1
T.ok("the entry Image info can be picked", pick("docs/assets/b.png", "Image info"))
T.wait(function()
  return #calls >= from
end)
T.eq("... and runs on the clicked node", called(from), { "info docs/assets/b.png" })
T.close_floats()

from = #calls + 1
T.ok("the entry OCR can be picked", pick("docs/assets/b.png", "OCR"))
T.wait(function()
  return #calls >= from
end)
T.eq("... and runs on the clicked node", called(from), { "ocr docs/assets/b.png" })
T.close_floats()

from = #calls + 1
T.ok("the entry Preview image can be picked", pick("docs/assets/b.png", "Preview image"))
T.wait(function()
  return #calls >= from
end)
T.eq("... and hands the node to images.nvim", called(from), { "show docs/assets/b.png" })
T.close_floats()

-- a file that is no image has none of them
T.tree()
pointer(tree_win, T.adapter.get_node_line(T.on("README.md")))
T.feed("<RightMouse>")
T.ok("the menu of another file is open", (menu_entry("Markdown link")) ~= nil)
T.eq("... without the image entries", (menu_entry("Image info")), nil)
T.close_floats()

-- ── the badge follows a written document ─────────────────────────────────────
T.tree()
T.mkfile("docs/guide.md", { "# Guide", "", "![a](assets/a.png) ![b](assets/b.png)" })
vim.api.nvim_exec_autocmds("BufWritePost", { pattern = dir .. "/docs/guide.md" })
T.on("docs/assets/b.png")
T.ok(
  "a document that now links the image takes the badge away",
  T.wait(function()
    return T.drawn("docs/assets/b.png").text == ""
  end, 5000)
)
T.eq("... and the count on the folder", T.drawn("docs").text, "")

T.eq("no dialog nobody expected", T.unanswered, 0)
require("images.integrations.tree").unregister()
vim.fn.delete(scratch, "rf")
T.finish()
