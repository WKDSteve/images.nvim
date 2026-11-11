-- TESTS/selftest_spec.lua -- `:Image selftest`: recheck, then the generated card handed to `show`.
-- No terminal needed: `images.show` and the notifier are replaced for the duration.

---@param H table harness from TESTS/run.lua
return function(H)
  local images = require("images")
  local config = require("images.config")
  local prev_cfg = config.get()

  local real_notify = package.loaded["lib.nvim.notify"]
  local real_show = images.show
  local said = {}
  package.loaded["lib.nvim.notify"] = {
    create = function()
      local function rec(msg)
        said[#said + 1] = tostring(msg)
      end
      return { info = rec, warn = rec, error = rec, debug = rec }
    end,
  }
  local shown
  images.show = function(path)
    shown = path
    return true
  end

  local terminal = require("images.terminal")
  local real_capability = terminal.capability

  -- A capable terminal (stubbed: the headless runner has no UI to ask): the card is written and handed to show.
  terminal.capability = function()
    return { ok = true, source = "stub" }
  end
  local drawn = images.selftest()
  H.ok(drawn, "selftest: draws when the terminal is capable")
  H.ok(shown and shown:find("testcard", 1, true), "selftest: show gets the generated test card")
  H.ok(shown and vim.uv.fs_stat(shown) ~= nil, "selftest: the card file exists when handed over")
  H.contains(table.concat(said, " "), "do you see it", "selftest: the question stays with the user")
  if shown then pcall(os.remove, shown) end

  -- An incapable terminal: nothing is drawn, recheck says why.
  shown, said = nil, {}
  terminal.capability = function()
    return { ok = false, reason = "stub says no", hint = "" }
  end
  H.falsy(images.selftest(), "selftest: refuses on an incapable terminal")
  H.eq(shown, nil, "selftest: ...and draws nothing")
  H.contains(table.concat(said, " "), "stub says no", "selftest: the reason is printed")

  terminal.capability = real_capability
  images.show = real_show
  package.loaded["lib.nvim.notify"] = real_notify
  config.setup(prev_cfg)
  terminal.reset_capability()
end
