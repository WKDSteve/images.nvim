-- scripts/bench_open.lua -- where the time goes when an image opens: `images.zen` against `images.show`.
--
-- Run it in a real Neovim on a real terminal (headless Neovim neither repaints nor fires `WinResized`, so a
-- second draw could not show up there), with images.nvim set up the way you use it:
--
--   :luafile scripts/bench_open.lua
--   :lua ImagesBench.run({ "C:/path/a.png", "C:/path/b.jpg" })
--
-- Each image is opened four times -- `zen` (the way filetree's `<CR>` asks for it) and `show` (its `<Tab>`),
-- each cold (caches of `images.info`/`images.pixels` dropped) and warm -- with the editor left idle in between
-- (repaint, autocommands, the deferred draw). The report lands in a scratch buffer and in
-- `vim.g.images_bench_report`. Restart Neovim afterwards: the module functions stay wrapped.
--
-- Every phase is timed with `vim.uv.hrtime()` (not `uv.now()`, the loop's cached time), and the expensive steps
-- are counted: process starts (`vim.system`), pictures sent to the terminal (`lib.nvim.terminal.osc.send`) and
-- full repaints (`:mode`, `:redraw`). On Windows under an endpoint scanner a process start costs far more than
-- here, so the counts say more than the milliseconds. `ImagesBench.run(files, { dry = true })` counts the
-- pictures without sending them (for a terminal that cannot draw).
--
-- Measured with it: TESTS/zen_open_cost_spec.lua pins the counts.

local uv = vim.uv

local B = { phase = {}, counts = {}, spawned = {}, dry = false }
_G.ImagesBench = B

function B.reset()
  B.phase = {}
  B.counts = { spawn = 0, send = 0, bytes = 0, mode = 0, redraw = 0 }
  B.spawned = {}
end
B.reset()

local function add(label, ms)
  B.phase[label] = (B.phase[label] or 0) + ms
end

local function wrap(orig, label)
  return function(...)
    local t0 = uv.hrtime()
    local r = { orig(...) }
    add(label, (uv.hrtime() - t0) / 1e6)
    return unpack(r, 1, table.maxn(r))
  end
end

local function timed(mod, name, label)
  mod[name] = wrap(mod[name], label)
end

-- What a process start looked like, without the resource limits and directories.
local LIMIT_ARGS = { ["-limit"] = true, memory = true, map = true, time = true }

local real_system = vim.system
vim.system = function(argv, ...)
  B.counts.spawn = B.counts.spawn + 1
  local args = {}
  for _, a in ipairs(argv) do
    if not (LIMIT_ARGS[a] or a:match("^%d") or a:match("MiB$")) then args[#args + 1] = vim.fn.fnamemodify(a, ":t") end
  end
  B.spawned[#B.spawned + 1] = table.concat(args, " ")
  return real_system(argv, ...)
end

local real_cmd = vim.cmd
vim.cmd = setmetatable({}, {
  __call = function(_, c)
    if c == "mode" then B.counts.mode = B.counts.mode + 1 end
    if c == "redraw" then B.counts.redraw = B.counts.redraw + 1 end
    return real_cmd(c)
  end,
  __index = real_cmd,
})

local osc = require("lib.nvim.terminal.osc")
local real_send = osc.send
osc.send = function(seq)
  B.counts.send = B.counts.send + 1
  B.counts.bytes = B.counts.bytes + #seq
  if B.dry then return true end
  local t0 = uv.hrtime()
  local ok, err = real_send(seq)
  add("send", (uv.hrtime() - t0) / 1e6)
  return ok, err
end

local terminal = require("images.terminal")
timed(require("images.resolve"), "path_or_cursor", "resolve")
timed(require("images.resolve"), "to_path", "resolve")
timed(terminal, "capability", "capability")
timed(require("images.guard"), "check", "guard")
timed(require("images.info"), "collect", "info")
timed(require("images.pixels"), "read", "pixels")
timed(terminal, "draw", "draw")
timed(terminal, "clear", "clear")
package.loaded["lib.nvim.window.make_scratch"] = wrap(require("lib.nvim.window.make_scratch"), "window")

local function drop_caches()
  for _, ns in ipairs({ "images.info", "images.pixels" }) do
    require("lib.nvim.cache.memory").namespace(ns, { ttl = 300 }).clear()
  end
end

---@param file string
---@return string
local function describe(file)
  local px = require("images.pixels").read(file)
  return ("%s: %.0f KB, %sx%s px, editor %dx%d"):format(
    vim.fn.fnamemodify(file, ":t"),
    (uv.fs_stat(file) or { size = 0 }).size / 1024,
    px and px.width or "?",
    px and px.height or "?",
    vim.o.columns,
    vim.o.lines
  )
end

---@param label string
---@param call_ms number
---@return string
local function report(label, call_ms)
  local parts = {}
  for _, k in ipairs({ "resolve", "capability", "guard", "info", "pixels", "window", "clear", "draw", "send" }) do
    if B.phase[k] then parts[#parts + 1] = ("%s=%.1f"):format(k, B.phase[k]) end
  end
  local c = B.counts
  return ("  %-10s call=%7.1f ms  spawn=%d send=%d (%d KB) mode=%d redraw=%d | %s%s"):format(
    label,
    call_ms,
    c.spawn,
    c.send,
    math.floor(c.bytes / 1024),
    c.mode,
    c.redraw,
    table.concat(parts, " "),
    #B.spawned > 0 and (" | " .. table.concat(B.spawned, "; ")) or ""
  )
end

--- How long the editor is left alone after an open, and after a close.
local SETTLE_MS = 800

---@param files string[]
---@param opts { dry?: boolean, on_done?: fun(lines: string[]) }|nil
function B.run(files, opts)
  opts = opts or {}
  B.dry = opts.dry == true
  local steps, out = {}, {}
  for _, f in ipairs(files) do
    local file = vim.fs.normalize(vim.fn.fnamemodify(f, ":p"))
    steps[#steps + 1] = function()
      out[#out + 1] = describe(file)
    end
    for _, kind in ipairs({ "zen", "show" }) do
      for _, warm in ipairs({ false, true }) do
        local label = kind .. (warm and " warm" or " cold")
        steps[#steps + 1] = function()
          if not warm then drop_caches() end
          B.reset()
          local t0 = uv.hrtime()
          if kind == "zen" then
            require("images").zen(file, { width = 0.66, height = 0.66 })
          else
            require("images").show(file)
          end
          local call_ms = (uv.hrtime() - t0) / 1e6
          vim.defer_fn(function()
            out[#out + 1] = report(label, call_ms)
            require("images.zen").close()
            terminal.clear()
          end, SETTLE_MS)
          return SETTLE_MS * 2
        end
      end
    end
  end

  local i = 0
  local function next_step()
    i = i + 1
    local step = steps[i]
    if not step then
      vim.g.images_bench_report = out
      if opts.on_done then return opts.on_done(out) end
      vim.cmd("new")
      vim.bo.buftype, vim.bo.bufhidden = "nofile", "wipe"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, out)
      return
    end
    vim.defer_fn(next_step, step() or 0)
  end
  next_step()
end
