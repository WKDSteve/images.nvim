-- TESTS/screenshot_spec.lua — `:Image screenshot`: availability detection,
-- and the Windows wait for the snip against a `vim.system` stand-in.
--
-- A real capture launches an interactive tool (Snipping
-- Tool/screencapture/grim+slurp/maim) and needs a human at the mouse, so it
-- stays a manual check; what is covered here is the plumbing around it: how
-- many processes the wait starts, and that every way it can end (snip,
-- timeout, failure, hang, cancel) ends it exactly once.

---@param H table harness from TESTS/run.lua
return function(H)
  local screenshot = require("images.screenshot")

  -- `available()` must run through cleanly whatever the actual result -- on
  -- every platform the suite runs on (here: the CI platform or the local
  -- machine), not only the one the concrete result applies to.
  local ok, available = pcall(screenshot.available)
  H.ok(ok, "available() does not throw: " .. tostring(available))
  H.ok(type(available) == "boolean", "available() returns a boolean")

  if not available then
    local ok2, reason = pcall(screenshot.unavailable_reason)
    H.ok(ok2, "unavailable_reason() does not throw: " .. tostring(reason))
    H.ok(type(reason) == "string" and #reason > 0, "…and returns a non-empty reason")
  end

  -- On Windows it is always available (ms-screenclip: ships with the system, no
  -- separate tool needed) -- the one case that can be checked unambiguously
  -- without mocking the platform.
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    H.ok(available, "always available on Windows (ms-screenclip: needs no external tool)")
  end

  -- ── Windows: one PowerShell for the whole wait ──────────────────────────
  --
  -- `testing perf` counted a fresh `powershell -STA` per poll tick (every
  -- 600 ms, up to 100 per screenshot). The capture now starts one watcher that
  -- polls on its own and answers once. `vim.system` is a stand-in (no real
  -- clipboard, no Snipping Tool): it counts PowerShell starts, throws from
  -- `wait()`, and hands stdout and `on_exit` to the spec, which answers by
  -- hand. The platform is faked as Windows, so this runs on every CI system.
  local config = require("images.config")
  local original = {
    system = vim.system,
    setup = vim.deepcopy(config.user_opts()),
    is_windows = package.loaded["lib.nvim.cross.platform.is_windows"],
    is_macos = package.loaded["lib.nvim.cross.platform.is_macos"],
    grace = screenshot.backstop_grace_ms,
  }
  package.loaded["lib.nvim.cross.platform.is_windows"] = function()
    return true
  end
  package.loaded["lib.nvim.cross.platform.is_macos"] = function()
    return false
  end
  ---@param timeout_ms integer
  local function timeouts(timeout_ms)
    config.setup({ display = { screenshot = { windows_timeout_ms = timeout_ms, windows_poll_interval_ms = 5 } } })
  end
  timeouts(5000) -- long enough for case 1 to see 20 poll intervals inside it

  local starts, last = {}, nil
  local spawn_throws = false
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(argv, opts, on_exit)
    if spawn_throws then error("ENOENT: powershell") end
    local call = { argv = argv, opts = opts, on_exit = on_exit, killed = false }
    starts[#starts + 1] = call
    -- What ends on its own in reality ends on its own here too: `explorer`
    -- returns at once, and a one-shot clipboard read (a script that does not
    -- wait for the snip) answers "no image". Only the watcher stays open for
    -- the spec to answer -- so a per-tick design gets to tick, and is counted.
    local script = tostring(argv[#argv])
    if argv[1]:match("^explorer") or not script:find("ms-screenclip:", 1, true) then
      vim.schedule(function()
        on_exit({ code = 0, stdout = "", stderr = "" })
      end)
      return { pid = -1, wait = function() end, kill = function() end }
    end
    last = call
    return {
      pid = -1,
      wait = function()
        error("images.screenshot must not wait for " .. tostring(argv[1]))
      end,
      kill = function()
        call.killed = true
      end,
    }
  end

  ---@param out string
  ---@return { done: boolean, ok: boolean|nil, err: string|nil }
  local function start(out)
    local r = { done = false }
    screenshot.capture(out, function(cb_ok, err)
      r.done, r.ok, r.err = true, cb_ok, err
    end)
    return r
  end

  ---@param r { done: boolean }
  local function settle(r)
    vim.wait(1000, function()
      return r.done
    end, 5)
  end

  ---@param program string
  ---@return integer
  local function count(program)
    local n = 0
    for _, call in ipairs(starts) do
      if call.argv[1] == program or call.argv[1] == program .. ".exe" then n = n + 1 end
    end
    return n
  end

  local ok_run, run_err = pcall(H.tmpdir, function(dir)
    -- 1. Many poll intervals pass, still one process; the snip arrives.
    local out = dir .. "/snip.png"
    local r = start(out)
    vim.wait(100, function()
      return r.done
    end, 5) -- 20 poll intervals of 5 ms
    H.falsy(r.done, "one process: still waiting while the watcher polls")
    H.eq(count("powershell"), 1, "one process: one PowerShell for 20 poll intervals")
    H.eq(count("explorer"), 0, "one process: the watcher opens the snip UI itself, no explorer start")
    H.eq(last.argv[1], "powershell", "one process: started by its bare name (a stand-in can take it)")
    local script = last.argv[#last.argv]
    H.contains(script, "ms-screenclip:", "one process: the script opens the snip UI")
    H.falsy(script:find('["|&<>%%^]'), "one process: no character a .cmd stand-in would read as cmd syntax")
    H.write(out, "PNG") -- what the watcher writes before it answers
    last.opts.stdout(nil, "IMAGES")
    last.opts.stdout(nil, "NVIM:0:\r\n")
    settle(r)
    H.ok(r.ok, "one process: the answer, split over two chunks, ends the capture with success")
    last.on_exit({ code = 0, stdout = "", stderr = "" })
    vim.wait(20)
    H.ok(r.ok, "one process: the process ending afterwards changes nothing")

    -- 2. The watcher's own timeout (short from here on, for the backstop case).
    timeouts(30)
    starts = {}
    r = start(dir .. "/none.png")
    last.opts.stdout(nil, "IMAGESNVIM:2:\n")
    settle(r)
    H.falsy(r.ok, "timeout: failure")
    H.contains(r.err or "", "timed out", "timeout: said as such")

    -- 3. A failure inside the watcher (the snip UI would not start).
    r = start(dir .. "/fail.png")
    last.opts.stdout(nil, "IMAGESNVIM:1:The system cannot find the file specified.\n")
    settle(r)
    H.falsy(r.ok, "watcher error: failure")
    H.contains(r.err or "", "cannot find the file", "watcher error: its reason is passed on")

    -- 4. The watcher dies without an answer.
    r = start(dir .. "/died.png")
    -- Like the real `vim.system` with a `stderr` handler: the text reaches
    -- the handler, `result.stderr` stays empty.
    last.opts.stderr(nil, "Add-Type : Could not load\r\nfile or assembly")
    last.on_exit({ code = 1, stdout = "", stderr = nil })
    settle(r)
    H.falsy(r.ok, "died: failure")
    H.contains(r.err or "", "without an answer", "died: said as such")
    H.contains(r.err or "", "Could not load file or assembly", "died: with PowerShell's reason, on one line")

    -- 5. Hung without answer or exit: the backstop kills it.
    screenshot.backstop_grace_ms = 20
    r = start(dir .. "/hung.png")
    local hung = last
    settle(r)
    H.ok(r.done, "hung: the backstop still ends the capture")
    H.contains(r.err or "", "timed out", "hung: as a timeout")
    H.ok(hung.killed, "hung: and kills the watcher")
    screenshot.backstop_grace_ms = original.grace

    -- 6. Cancelled, and replaced by a second capture.
    r = start(dir .. "/cancel.png")
    local first = last
    screenshot.cancel()
    H.ok(r.done and r.err == "cancelled", "cancel: the waiting capture ends as cancelled")
    H.ok(first.killed, "cancel: its watcher is killed")
    local older = start(dir .. "/older.png")
    local older_call = last
    local newer = start(dir .. "/newer.png")
    H.ok(older.done and older.err == "cancelled", "replaced: the older capture gives way")
    H.ok(older_call.killed, "replaced: its watcher is killed")
    H.falsy(newer.done, "replaced: the newer one waits")
    screenshot.cancel()

    -- 7. PowerShell cannot be started at all.
    spawn_throws = true
    r = start(dir .. "/nops.png")
    spawn_throws = false
    H.ok(r.done and not r.ok, "no PowerShell: failure at once")
    H.contains(r.err or "", "could not start PowerShell", "no PowerShell: said as such")
  end)

  screenshot.cancel()
  vim.system = original.system
  screenshot.backstop_grace_ms = original.grace
  package.loaded["lib.nvim.cross.platform.is_windows"] = original.is_windows
  package.loaded["lib.nvim.cross.platform.is_macos"] = original.is_macos
  config.setup(original.setup) -- restore for later specs
  H.ok(ok_run, "the Windows capture cases ran through: " .. tostring(run_err))
end
