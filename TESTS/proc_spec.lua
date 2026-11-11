-- TESTS/proc_spec.lua -- images.proc: the timeout and the magick resource limits every external call gets.

---@param H table harness from TESTS/run.lua
return function(H)
  local config = require("images.config")
  local proc = require("images.proc")
  local prev = config.get()

  -- Defaults: limits right after the binary name, the rest of the argv untouched and in order.
  config.setup({})
  local argv = proc.magick({ "magick", "in.png", "-resize", "50%", "out.png" })
  H.eq(argv[1], "magick", "the binary stays first")
  local joined = table.concat(argv, " ")
  H.contains(joined, "-limit memory 512MiB", "memory limit by default")
  H.contains(joined, "-limit map 512MiB", "map limit by default")
  H.contains(joined, "-limit time 60", "time limit by default")
  H.eq(
    table.concat(vim.list_slice(argv, #argv - 3), " "),
    "in.png -resize 50% out.png",
    "the original arguments follow unchanged"
  )

  -- Configured values and `false`.
  config.setup({ process = { magick_memory = "64MiB", magick_time_s = 5 } })
  joined = table.concat(proc.magick({ "magick", "a.png", "b.png" }), " ")
  H.contains(joined, "-limit memory 64MiB", "configured memory limit")
  H.contains(joined, "-limit time 5", "configured time limit")
  config.setup({ process = { magick_memory = false, magick_time_s = false } })
  H.eq(table.concat(proc.magick({ "magick", "a.png", "b.png" }), " "), "magick a.png b.png", "false leaves both limits off")

  -- Only magick argv are touched.
  H.eq(proc.magick({ "tesseract", "a.png" })[1], "tesseract", "another program's argv is returned as it is")
  H.eq(#proc.magick({ "tesseract", "a.png" }), 2, "...unchanged")

  -- The timeout is one config value, and a process that never answers is killed, not waited for.
  config.setup({ process = { timeout_ms = 300 } })
  H.eq(proc.timeout_ms(), 300, "timeout comes from process.timeout_ms")
  local started = vim.uv.hrtime()
  local res, timed_out = proc.sync({ vim.v.progpath, "--headless", "-u", "NONE", "-c", "sleep 20" }, { text = true })
  local took_ms = (vim.uv.hrtime() - started) / 1e6
  H.ok(timed_out, "a hanging process is reported as timed out")
  H.ok(res.code ~= 0, "...with a failing exit code")
  H.ok(took_ms < 5000, "...long before the process would have ended (" .. math.floor(took_ms) .. " ms)")

  -- A fast process is untouched.
  config.setup({ process = { timeout_ms = 20000 } })
  local ok_res, ok_timed = proc.sync({ vim.v.progpath, "--version" }, { text = true })
  H.eq(ok_res.code, 0, "a normal process exits 0")
  H.falsy(ok_timed, "...and is not timed out")

  config.setup(prev)
end
