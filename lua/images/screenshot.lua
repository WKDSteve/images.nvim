---@module 'images.screenshot'
---@brief Capture an interactive screen selection straight into a file.
---@description
--- Replaces three everyday steps (launch a screenshot tool by hand ->
--- clipboard -> `:Image paste`) with one: `:Image screenshot` starts the
--- selection and then continues exactly like `:Image paste` (see
--- `images.paste`'s `capture_with_optional_name`).
---
--- Asynchronous throughout (`vim.system` without `:wait()`, every
--- continuation inside `vim.schedule`), never a blocking `sleep`: a selection
--- takes the user anywhere from seconds to a minute, and `:wait()` blocks
--- Neovim's entire event loop for the subprocess's lifetime — a frozen editor
--- while all you are doing is dragging a rectangle. The same construction as
--- `lib.nvim.system.job`, which avoids `:wait()` for precisely this reason.
---
--- Platforms, in decreasing order of reliability:
---
--- * macOS — `screencapture -i`: interactive selection by dragging or clicking
---   a window, writing straight to the target file. If the user cancels with
---   <Esc>, `screencapture` still exits 0 — a cancellation is not visible in
---   the exit code, only in the missing/empty file.
---
--- * Linux — `grim -g "$(slurp)"` (Wayland, both tools needed) or `maim -s`
---   (X11, one tool suffices). `slurp` writes the region the user dragged to
---   stdout; if they cancel it writes nothing and `grim` is never invoked.
---
--- * Windows — the least certain of the three. There is no documented CLI
---   invocation that makes the modern Snipping Tool write directly to a file.
---   Opening the `ms-screenclip:` URI launches the selection UI (the same as
---   Win+Shift+S) but returns immediately and copies the result to the
---   clipboard when finished — with no signal for when that happens. One
---   PowerShell process (see the Windows section below) takes the clipboard
---   baseline, opens the URI, polls for a *new* image in its own loop with a
---   timeout and answers once; Neovim only waits for that answer. Whether
---   `ms-screenclip:` launches as documented on every Windows version could
---   not be simulated in this environment — `:Image paste` remains the
---   unchanged, proven two-step route should this automation ever fail.

local M = {}

---@return ImagesNvim.Config
local function cfg()
  return require("images.config").get()
end

--- A configured millisecond value, made safe to hand to `timer:start` (ERR-22):
--- libuv's binding throws synchronously for a non-number (`bad argument #1 to
--- 'start' (number expected, got string)`, reproduced with a string and a
--- boolean alike) rather than degrading, and that call is not `pcall`'d --
--- `x or default` alone only catches `nil`/`false`, not a wrong type. `>= 1`
--- also rules out 0 and negative values: libuv accepts both without error,
--- but 0 busy-fires the timer every loop tick and a negative `timeout_ms`
--- would make `elapsed >= timeout_ms` below never trip -- a silent hang
--- instead of a crash, still not a value that should reach the timer as-is.
---@param value any
---@param default integer
---@return integer
local function valid_ms(value, default)
  if type(value) == "number" and value == value and value >= 1 then return math.floor(value) end
  return default
end

--- Check the file after a capture: does it exist, and is it non-empty? The
--- shared ending for macOS/Linux, where a cancellation (<Esc>) is not visible
--- in the exit code, only in the missing/empty file.
---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function finish_from_file(out, callback)
  local stat = vim.uv.fs_stat(out)
  if not stat or stat.size == 0 then
    pcall(vim.uv.fs_unlink, out)
    callback(false, "cancelled")
    return
  end
  callback(true)
end

-- ── macOS ────────────────────────────────────────────────────────────────────

---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_mac(out, callback)
  vim.system({ "screencapture", "-i", out }, { text = true }, function()
    vim.schedule(function()
      finish_from_file(out, callback)
    end)
  end)
end

-- ── Linux ────────────────────────────────────────────────────────────────────

---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_linux(out, callback)
  local executable = require("lib.nvim.cross.executable")
  if executable.exists("grim") and executable.exists("slurp") then
    vim.system({ "slurp" }, { text = true }, function(sel)
      vim.schedule(function()
        if sel.code ~= 0 or vim.trim(sel.stdout or "") == "" then
          callback(false, "cancelled")
          return
        end
        vim.system({ "grim", "-g", vim.trim(sel.stdout), out }, { text = true }, function(gr)
          vim.schedule(function()
            if gr.code ~= 0 then
              callback(false, "grim failed: " .. vim.trim(gr.stderr or ""))
              return
            end
            finish_from_file(out, callback)
          end)
        end)
      end)
    end)
  elseif executable.exists("maim") then
    -- -s: interactive drag selection. Cancelling (<Esc>) exits non-zero.
    vim.system({ "maim", "-s", out }, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(false, "cancelled")
          return
        end
        finish_from_file(out, callback)
      end)
    end)
  else
    callback(false, "neither `grim`+`slurp` (Wayland) nor `maim` (X11) found")
  end
end

-- ── Windows ──────────────────────────────────────────────────────────────────
--
-- **One PowerShell for the whole wait.** This used to start a fresh
-- `powershell -STA` for the baseline and then one per poll tick (every 600 ms,
-- up to 100 for the 60 s timeout; `testing perf` counted them), each paying
-- the PowerShell start and the `System.Windows.Forms` load again -- far more
-- under an endpoint scanner. Now a single process reads the baseline, opens
-- the snip UI itself (`Start-Process 'ms-screenclip:'`: the same ShellExecute
-- of the URI that `explorer ms-screenclip:` did, minus a process), polls the
-- clipboard in its own loop and answers exactly once:
--
--   IMAGESNVIM:0:          a new image, written to the target file
--   IMAGESNVIM:2:          the timeout passed without one
--   IMAGESNVIM:1:<reason>  something failed (the snip UI would not start, ...)
--
-- Not the persistent `images.win_clipboard_worker` of `:Image paste`: its
-- protocol is one request, one answer, under a per-request timeout of a few
-- seconds, and it can be switched off (`paste.windows_persistent_helper`).
-- Polling it would still mean a request per tick for up to a minute; a script
-- that waits on its own needs no traffic at all until it has the answer.
--
-- The script is one line without `"`, `|`, `&`, `<`, `>`, `%` or `^`: the
-- test stand-ins on Windows are `.cmd` files, and cmd reads those characters
-- even inside an argument.

--- The watcher script: baseline, snip UI, poll, one answer.
---@param out string target file
---@param timeout_ms integer
---@param interval_ms integer
---@return string
local function watch_script(out, timeout_ms, interval_ms)
  return table.concat({
    "try {",
    "Add-Type -AssemblyName System.Windows.Forms,System.Drawing -ErrorAction Stop;",
    "function Snap { $img = [System.Windows.Forms.Clipboard]::GetImage();",
    "if ($null -eq $img) { return '' };",
    "$ms = New-Object System.IO.MemoryStream;",
    "$img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $img.Dispose();",
    "return [Convert]::ToBase64String($ms.ToArray()) };",
    "$base = Snap;",
    "Start-Process 'ms-screenclip:' -ErrorAction Stop;",
    ("$deadline = (Get-Date).AddMilliseconds(%d);"):format(timeout_ms),
    "while ((Get-Date) -lt $deadline) {",
    ("Start-Sleep -Milliseconds %d;"):format(interval_ms),
    "if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) { continue };",
    "$cur = Snap;",
    "if ($cur -ne '' -and $cur -ne $base) {",
    ("[System.IO.File]::WriteAllBytes(%s, [Convert]::FromBase64String($cur));"):format(require("images.ps_path").expr(out)),
    "Write-Output 'IMAGESNVIM:0:'; exit 0 } };",
    "Write-Output 'IMAGESNVIM:2:'",
    "} catch { Write-Output ('IMAGESNVIM:1:' + $_.Exception.Message.Replace([char]13, ' ').Replace([char]10, ' ')) }",
  }, " ")
end

--- How long past the configured timeout the process may stay silent before
--- it is killed: the script's own deadline starts only once PowerShell runs,
--- and a PowerShell start under an endpoint scanner can take seconds. Without
--- this backstop a watcher that never answers (hung on load) would hang the
--- capture for good. A field so a spec can shorten it.
M.backstop_grace_ms = 15000

--- The Windows capture in flight, if any: `cancel()` and `VimLeavePre` end it.
---@type { finish: fun(ok: boolean, err: string|nil) }|nil
local running = nil

--- Start the watcher and report its single answer.
---@param out string
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
local function capture_windows(out, callback)
  local c = cfg().display.screenshot
  local timeout_ms = valid_ms(c.windows_timeout_ms, 60000)
  local interval_ms = valid_ms(c.windows_poll_interval_ms, 600)

  -- A second capture while one waits: the older one gives way, its process
  -- is killed and it reports "cancelled", so only one snip UI and one
  -- watcher are ever about.
  if running then running.finish(false, "cancelled") end

  local done = false
  local proc, timer = nil, nil
  local buffer = ""
  -- Collected by hand: with a `stderr` handler of its own, `vim.system` leaves
  -- `result.stderr` empty. Bounded, it is only the reason in an error message.
  local errtext = ""

  ---@param ok boolean
  ---@param err string|nil
  local function finish(ok, err)
    if done then return end
    done = true
    if running and running.finish == finish then running = nil end
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if proc then pcall(proc.kill, proc, "sigkill") end
    callback(ok, err)
  end
  running = { finish = finish }

  ---@param code string
  ---@param message string
  local function on_answer(code, message)
    if code == "0" then
      local stat = vim.uv.fs_stat(out)
      if not stat or stat.size == 0 then
        finish(false, "target file not writable: " .. out)
        return
      end
      finish(true)
    elseif code == "2" then
      finish(false, "timed out — no new capture detected in the clipboard")
    else
      local reason = vim.trim(message or "")
      finish(false, reason ~= "" and reason or "could not watch the clipboard")
    end
  end

  local ok, obj = pcall(vim.system, {
    "powershell",
    "-NoProfile",
    "-NonInteractive",
    "-STA",
    "-Command",
    watch_script(out, timeout_ms, interval_ms),
  }, {
    text = true,
    stdout = function(err, data)
      if err or not data then return end
      buffer = buffer .. data
      for line in buffer:gmatch("[^\n]*\n") do
        local code, message = line:gsub("\r?\n$", ""):match("^IMAGESNVIM:(%d):(.*)$")
        if code then vim.schedule(function()
          on_answer(code, message)
        end) end
      end
      buffer = buffer:match("[^\n]*$") or ""
    end,
    stderr = function(err, data)
      if not err and data and #errtext < 2000 then errtext = errtext .. data end
    end,
  }, function(result)
    vim.schedule(function()
      -- After the answer this is the process ending as it should; without
      -- one, the watcher died or never got going.
      local detail = vim.trim(errtext ~= "" and errtext or tostring(result.stderr or "")):gsub("%s+", " ")
      finish(false, "the clipboard watcher ended without an answer" .. (detail ~= "" and (": " .. detail) or ""))
    end)
  end)
  if not ok or not obj then
    finish(false, "could not start PowerShell to watch the clipboard")
    return
  end
  if done then return end -- the spawn answered synchronously (a stand-in)
  proc = obj

  timer = assert(vim.uv.new_timer())
  timer:start(
    timeout_ms + M.backstop_grace_ms,
    0,
    vim.schedule_wrap(function()
      finish(false, "timed out — no new capture detected in the clipboard")
    end)
  )
end

--- End a capture that is still waiting for the snip (Windows): the watcher is
--- killed and its callback runs with `false, "cancelled"`. A no-op when none
--- waits, and on macOS/Linux, where the platform tool itself ends the wait.
---@return nil
function M.cancel()
  if running then running.finish(false, "cancelled") end
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Whether this platform offers any capture route at all.
---@return boolean
function M.available()
  local executable = require("lib.nvim.cross.executable")
  if require("lib.nvim.cross.platform.is_macos")() then
    return executable.exists("screencapture")
  elseif require("lib.nvim.cross.platform.is_windows")() then
    return true -- ms-screenclip: ships with Windows, no separate tool needed
  else
    return (executable.exists("grim") and executable.exists("slurp")) or executable.exists("maim")
  end
end

--- The reason `available()` is false — for the error message.
---@return string
function M.unavailable_reason()
  if require("lib.nvim.cross.platform.is_macos")() then return "`screencapture` not found (normally ships with macOS)" end
  return "neither `grim`+`slurp` (Wayland) nor `maim` (X11) found"
end

--- Start an interactive screen selection and write it to `out`. Returns
--- immediately; `callback(ok, err)` runs once the user is done, has cancelled,
--- or (Windows only) the timeout was reached.
---@param out string target path (PNG)
---@param callback fun(ok: boolean, err: string|nil)
---@return nil
function M.capture(out, callback)
  if require("lib.nvim.cross.platform.is_macos")() then
    capture_mac(out, callback)
  elseif require("lib.nvim.cross.platform.is_windows")() then
    capture_windows(out, callback)
  else
    capture_linux(out, callback)
  end
end

return M
