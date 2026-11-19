-- TESTS/sheets/_helpers.lua -- what the images.nvim test sheets need in their child editor. Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); a sheet's `requires` and its first step run it with `dofile`, the
-- child's cwd is the project root. The directory is in the spec's @cache-inputs, so a change here re-runs the sheets.
--
-- The sheets run images.nvim in the real own tree of filetree.nvim (`adapter = "native"`), with the real context
-- menu and dialogs of ui.nvim. A headless child has no terminal that draws pictures, and nothing here needs one: the
-- sheets are about the badge on an image no document links and the two actions around it.

local M = {}

---filetree.nvim and ui.nvim on the runtimepath; false when one is not to be found. For `requires`.
---TESTS/minimal_init.lua looked them up ($<NAME>_DIR, .deps/<name>, ../<name>, the lazy.nvim directory) and left
---what it found in `vim.g.images_sheets_deps`.
---@return boolean
function M.add_deps()
  local found = vim.g.images_sheets_deps or {}
  for _, name in ipairs({ "ui.nvim", "filetree.nvim" }) do
    local dir = found[name]
    if type(dir) ~= "string" or vim.fn.isdirectory(dir .. "/lua") ~= 1 then return false end
  end
  for _, name in ipairs({ "ui.nvim", "filetree.nvim" }) do
    vim.opt.rtp:append(found[name])
  end
  return true
end

vim.o.swapfile = false
vim.o.hidden = true
vim.o.laststatus = 0
vim.o.ruler = false
vim.o.showcmd = false
vim.opt.shortmess:append("I")
vim.g.have_nerd_font = false
vim.g.mapleader = "\\"

-- a 1x1 PNG
local PNG = "\137PNG\r\n\26\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\8\6\0\0\0\31\21\196\137"
  .. "\0\0\0\rIDATx\156c\248\207\192\240\31\0\5\0\1\255\137\153=\29\0\0\0\0IEND\174B`\130"

-- Every notification is kept instead of shown: a long one would become a hit-enter prompt.
_G.notes = {}
vim.notify = function(msg, level)
  _G.notes[#_G.notes + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO }
end

---Whether a notification so far holds `text` (plain).
---@param text string
---@return boolean
function _G.noted(text)
  for _, note in ipairs(_G.notes) do
    if note.msg:find(text, 1, true) then return true end
  end
  return false
end

---The notifications at warning level or above, one per line ("" when there is none).
---@return string
function _G.loud()
  local out = {}
  for _, note in ipairs(_G.notes) do
    if note.level >= vim.log.levels.WARN then out[#out + 1] = note.msg end
  end
  return table.concat(out, "\n")
end

---`got == want`, or an error that says what came instead (the failure line of the sheet shows it).
---@param got any
---@param want any
---@return boolean
function _G.eq(got, want)
  if not vim.deep_equal(got, want) then error(("got %s, wanted %s"):format(vim.inspect(got), vim.inspect(want)), 0) end
  return true
end

---A directory that really exists, spelled the way the editor reports it (a runner's temp may be a link).
---@param path string
---@return string
local function fresh_dir(path)
  vim.fn.mkdir(path, "p")
  return (vim.fs.normalize(assert(vim.uv.fs_realpath(path))))
end

---Write a file below `root`: lines, or the 1x1 PNG for a name that ends in `.png`.
---@param root string
---@param rel string
---@param lines? string[]
---@return string path
function _G.write(root, rel, lines)
  local path = root .. "/" .. rel
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if rel:match("%.png$") then
    local fd = assert(io.open(path, "wb"))
    fd:write(PNG)
    fd:close()
  else
    vim.fn.writefile(lines or { "text" }, path)
  end
  return path
end

---@param path string
---@return boolean
function _G.exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

---Two projects below the temp directory. `_G.site`: a guide that links `docs/assets/linked.png` and leaves
---`docs/assets/unused.png` alone. `_G.blog`: a post that links nothing, next to `assets/draft.png`.
local function projects()
  local base = fresh_dir(vim.fn.tempname())
  _G.site = fresh_dir(base .. "/site")
  _G.write(_G.site, "README.md", { "# Site" })
  _G.write(_G.site, "docs/guide.md", { "# Guide", "", "![linked](assets/linked.png)" })
  _G.write(_G.site, "docs/assets/linked.png")
  _G.write(_G.site, "docs/assets/unused.png")
  _G.write(_G.site, "lua/init.lua", { "return {}" })
  _G.blog = fresh_dir(base .. "/blog")
  _G.write(_G.blog, "post.md", { "# Post", "", "no picture yet" })
  _G.write(_G.blog, "assets/draft.png")
  _G.bin = fresh_dir(base .. "/bin")
end

---The trash of the operating system, replaced by the folder `_G.bin`: what the tree does around the one external
---call (its question, its refresh, `User FiletreeChanged`) is the real code, and no file leaves the temp directory.
function _G.trash_is_a_folder()
  local platform = require("filetree.features.fileops.trash.platform")
  local function send(path)
    local moved = vim.uv.fs_rename(path, _G.bin .. "/" .. vim.fn.fnamemodify(path, ":t"))
    return { ok = moved == true, err = not moved and "could not move" or nil }
  end
  platform.available = function()
    return true
  end
  platform.send = function(path, cb)
    vim.schedule(function()
      cb(send(path))
    end)
  end
  platform.send_batch = function(paths, cb)
    vim.schedule(function()
      cb(vim.tbl_map(send, paths))
    end)
  end
end

---The two projects, images.nvim and the own tree of filetree.nvim, open on `_G.site` with the cursor in README.md.
---`trash` says what stands behind the trash of the tree: "folder" (default) the folder `_G.bin`; "program" the
---real backend, which starts the program of the platform (a sheet lists them as `fakes`); "none" a tree without a
---trash, where images.nvim asks itself and deletes for good.
---`images` is merged into the setup of images.nvim; `preview` is the tree's preview feature (off by default, as
---in filetree.nvim: `<Tab>`/`<CR>` on an image go through it).
---@param opts? { trash?: "folder"|"program"|"none", images?: table, preview?: table }
function _G.boot(opts)
  opts = opts or {}
  local trash = opts.trash or "folder"
  projects()
  vim.cmd("cd " .. vim.fn.fnameescape(_G.site))
  vim.cmd("edit " .. vim.fn.fnameescape(_G.site .. "/README.md"))
  _G.editor_win = vim.api.nvim_get_current_win()

  require("images").setup(
    vim.tbl_deep_extend("force", { deps_popup = false, display = { terminal_probe = false } }, opts.images or {})
  )
  -- before the setup of the tree: its trash feature asks the backend whether it is there, and a Linux without
  -- gio or trash-cli has none
  if trash == "folder" then _G.trash_is_a_folder() end
  require("filetree").setup({
    adapter = "native",
    deps_popup = false,
    native = { width = 36 },
    features = {
      tree_toggle = { enabled = true },
      session = { enabled = false }, -- writes into the data directory
      close_on_open = { enabled = false },
      trash = { enabled = trash ~= "none" },
      preview = opts.preview,
    },
  })
  require("ui.contextmenu").setup({ renderer = "kit" })
  _G.adapter = require("filetree").adapter()
  _G.adapter.open_cwd()
end

---The calls of the trash program of this platform, as the stand-ins of `fakes` recorded them: Windows starts
---`powershell`, macOS the `trash` CLI when there is one, Linux and WSL `gio trash` (lib.nvim's fs.trash: WSL is a
---Linux there, its files go to the desktop trash, not to the Recycle Bin).
---@return { program: string, argv: string[], cwd: string }[]
function _G.trash_calls()
  local read = require("testing.fake_programs").read
  local out = {}
  for _, program in ipairs({ "powershell", "trash", "gio" }) do
    vim.list_extend(out, read(vim.env.TESTING_FAKES, program))
  end
  return out
end

---The trash program this platform starts (see `_G.trash_calls`).
---@return string
function _G.trash_program()
  if vim.fn.has("win32") == 1 then return "powershell" end
  return vim.fn.has("mac") == 1 and "trash" or "gio"
end

---Focus the editor window of the first tab's layout (the window README.md was opened in).
function _G.editor()
  vim.api.nvim_set_current_win(_G.editor_win)
end

---Focus the tree window of the current tab.
function _G.tree()
  if not _G.adapter.is_open() then _G.adapter.open_cwd() end
  vim.api.nvim_set_current_win(_G.adapter.get_winid())
end

---The line of `path` in the tree of the current tab, or nil.
---@param path string
---@return integer|nil
function _G.line_of(path)
  return _G.adapter.get_node_line(path)
end

---Press `keys` as typed (mappings apply).
---@param keys string
function _G.press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---Put the cursor of the tree on `rel` below `root`, opening the folders above it the way a person does: the
---cursor on the folder, then <CR>.
---@param root string
---@param rel string
function _G.on(root, rel)
  _G.tree()
  local win = _G.adapter.get_winid()
  local path = root
  for _, part in ipairs(vim.split(rel, "/", { plain = true })) do
    local parent = path
    path = path .. "/" .. part
    -- entering the tree may draw it anew: a line that is not there yet gets a moment
    vim.wait(3000, function()
      return _G.line_of(path) ~= nil or _G.line_of(parent) ~= nil
    end, 20)
    if not _G.line_of(path) then
      vim.api.nvim_win_set_cursor(win, { assert(_G.line_of(parent), "the tree does not show " .. parent), 0 })
      _G.press("<CR>")
      vim.wait(3000, function()
        return _G.line_of(path) ~= nil
      end, 20)
    end
  end
  local line = assert(_G.line_of(path), "the tree does not show " .. rel)
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  vim.cmd("doautocmd CursorMoved")
end

---The screen row (as the text of the tree window shows it) of `path`, "" when the tree does not show it.
---The badges are virtual text the tree places while it draws: only the screen has them.
---@param path string
---@return string
function _G.row(path)
  local line = _G.line_of(path)
  if not line then return "" end
  local win = _G.adapter.get_winid()
  local pos = vim.fn.screenpos(win, line, 1)
  if pos.row == 0 then return "" end
  vim.cmd("redraw")
  local width = vim.api.nvim_win_get_width(win)
  local first = vim.api.nvim_win_get_position(win)[2]
  local cells = {}
  for col = first + 1, first + width do
    cells[#cells + 1] = vim.fn.screenstring(pos.row, col)
  end
  return (table.concat(cells):gsub("%s+$", ""))
end

---Whether the row of `path` shows `text`.
---@param path string
---@param text string
---@return boolean
function _G.row_has(path, text)
  return _G.row(path):find(text, 1, true) ~= nil
end

local clicks = 0

---A right click on the row of `path`, as the mouse does it (0-based screen cells).
---@param path string
function _G.right_click(path)
  local win = _G.adapter.get_winid()
  local pos = vim.fn.screenpos(win, assert(_G.line_of(path), "the tree does not show " .. path), 1)
  -- Never the cell of the click before: two clicks on one cell within 'mousetime' are a double click
  -- (<2-RightMouse>), which opens no menu.
  clicks = clicks + 1
  local col = pos.col + 3 + clicks % 2
  vim.api.nvim_input_mouse("right", "press", "", 0, pos.row - 1, col)
  vim.api.nvim_input_mouse("right", "release", "", 0, pos.row - 1, col)
end

---The floating windows: `{ win, lines }` each.
---@return { win: integer, lines: string[] }[]
function _G.floats()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      out[#out + 1] = { win = win, lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false) }
    end
  end
  return out
end

---The text of every floating window, joined.
---@return string
function _G.float_text()
  local out = {}
  for _, float in ipairs(_G.floats()) do
    out[#out + 1] = table.concat(float.lines, "\n")
  end
  return table.concat(out, "\n")
end

---Put the cursor of the open menu on the entry that holds `label`; false when no float has it.
---@param label string
---@return boolean
function _G.menu_on(label)
  for _, float in ipairs(_G.floats()) do
    for i, text in ipairs(float.lines) do
      if text:find(label, 1, true) then
        vim.api.nvim_set_current_win(float.win)
        vim.api.nvim_win_set_cursor(float.win, { i, 0 })
        return true
      end
    end
  end
  return false
end

-- ── The sheets without a tree: one document with two images ──────────────────────────────────────────────────────

-- Captured while the child's cwd is still the project root: `_G.desk` moves it into the temp project.
local FIXTURES = vim.fs.normalize(vim.fn.getcwd()) .. "/TESTS/sheets/fixtures"

---Programs the sheet needs, `name -> spec` (`testing.fake_programs`: `stdout`, `exit_code`). A program this machine
---has runs for real, which is what `testing perf` measures; one it lacks (ImageMagick and tesseract on a CI runner)
---becomes a recording stand-in first on this editor's PATH, so the feature still makes the call and the sheet can
---read it. Call it before the setup: the setup looks the programs up.
---@param specs table<string, table>
---@return table<string, boolean> real  name -> the real program runs
function _G.tools(specs)
  local real, missing = {}, {}
  for name, spec in pairs(specs) do
    real[name] = vim.fn.executable(name) == 1
    if not real[name] then missing[name] = spec end
  end
  if next(missing) then
    _G.stand_ins = require("testing.fake_programs").new(missing)
    vim.env.PATH = _G.stand_ins:path(vim.env.PATH)
  end
  _G.real = real
  return real
end

---The calls a stand-in of `_G.tools` recorded (`{ program, argv, cwd }`), none for a program that ran for real.
---@param name string
---@return { program: string, argv: string[], cwd: string }[]
function _G.stand_in_calls(name)
  return _G.stand_ins and _G.stand_ins:calls(name) or {}
end

---Windows: `vim.system` gets the bare program name for `powershell.exe` and `explorer.exe`. A stand-in of `fakes`
---is a `.cmd` file there and only the bare name reaches it (testing.nvim task
---fakes-unter-windows-exe-namen-explorer-exe-rundll32-exe-und); elsewhere nothing changes.
function _G.bare_exe_names()
  if vim.fn.has("win32") ~= 1 then return end
  local system = vim.system
  vim.system = function(argv, ...)
    if type(argv) == "table" and type(argv[1]) == "string" then
      argv = vim.list_extend({ (argv[1]:gsub("%.exe$", "")) }, argv, 2)
    end
    return system(argv, ...)
  end
end

---The calls of the `fakes` stand-ins of the sheet to `program`.
---@param program string
---@return { program: string, argv: string[], cwd: string }[]
function _G.faked(program)
  return require("testing.fake_programs").read(vim.env.TESTING_FAKES, program)
end

---A project below the temp directory, `_G.desk_root`: `notes.md` links `assets/photo.png` (1x1) and
---`assets/hello.png` (160x48, the word HELLO, from TESTS/sheets/fixtures); the editor's cwd is there and notes.md is
---open with the cursor on line 1. images.nvim is set up with `images` merged into the defaults of the sheets (no
---dependency popup, no terminal probe).
---@param images? table
function _G.desk(images)
  local root = fresh_dir(vim.fn.tempname())
  _G.desk_root = root
  _G.write(root, "assets/photo.png")
  vim.fn.mkdir(root .. "/assets", "p")
  assert(vim.uv.fs_copyfile(FIXTURES .. "/hello.png", root .. "/assets/hello.png"))
  _G.write(root, "notes.md", { "# Notes", "", "![photo](assets/photo.png)", "", "![hello](assets/hello.png)" })
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/notes.md"))
  require("images").setup(
    vim.tbl_deep_extend("force", { deps_popup = false, display = { terminal_probe = false } }, images or {})
  )
end

---A small HTTP server in this editor on a free local port, serving the fixture hello.png at `/hello.png` (anything
---else is a 404); `_G.requests` counts what it was asked. The real curl fetches from it, nothing leaves the machine
---(the pattern of diff.nvim's url sheet). `_G.port` is its port.
function _G.serve()
  local fd = assert(io.open(FIXTURES .. "/hello.png", "rb"))
  local png = fd:read("*a")
  fd:close()
  _G.requests = {}
  local server = assert(vim.uv.new_tcp())
  assert(server:bind("127.0.0.1", 0))
  assert(server:listen(16, function()
    local client = assert(vim.uv.new_tcp())
    server:accept(client)
    client:read_start(function(_, data)
      if not data then return end
      client:read_stop()
      local path = data:match("^GET (%S+)") or "?"
      _G.requests[#_G.requests + 1] = path
      local found = path == "/hello.png"
      local body = found and png or "not found\n"
      local head = ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"):format(
        found and "200 OK" or "404 Not Found",
        found and "image/png" or "text/plain",
        #body
      )
      client:write(head .. body, function()
        client:close()
      end)
    end)
  end))
  _G.port = server:getsockname().port
end

---Count the pictures images.nvim sends to the terminal instead of sending them: the child has no terminal that draws
---them. `_G.sent` is the count.
function _G.count_pictures()
  _G.sent = 0
  require("lib.nvim.terminal.osc").send = function(seq)
    if seq:find("1337", 1, true) then _G.sent = _G.sent + 1 end
    return true
  end
end

---Put the cursor on the first line of the current buffer that holds `text`.
---@param text string
function _G.cursor_on(text)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local col = line:find(text, 1, true)
    if col then
      vim.api.nvim_win_set_cursor(0, { i, col - 1 })
      return
    end
  end
  error("no line holds " .. text, 0)
end

---Whether `path` (any slashes) begins with `prefix`, or an error that names both.
---@param path string
---@param prefix string
---@return boolean
function _G.starts(path, prefix)
  local got = path:gsub("\\", "/")
  if got:sub(1, #prefix) ~= prefix then error(("%s does not begin with %s"):format(got, prefix), 0) end
  return true
end

---The lines of the current buffer.
---@return string[]
function _G.lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

return M
