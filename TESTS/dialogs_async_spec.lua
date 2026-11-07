-- TESTS/dialogs_async_spec.lua — the questions images.nvim asks through lib.nvim's shared dialog
-- (`:Image orphans` delete, `:Image calibrate` save, the paste chain's file-name and alt-text
-- prompts), answered LATER than the call that asked, the way the kit answers: nothing may happen
-- before the answer, a "no" or a dismissal changes nothing, and the answer arriving after the
-- asking function returned still drives the rest.

---@param H table harness from TESTS/run.lua
return function(H)
  local dialog = require("lib.nvim.ui.dialog")
  local config = require("images.config")

  --- Replace `tbl[key]` for the duration of `fn`.
  ---@param tbl table
  ---@param key string
  ---@param value any
  ---@param fn fun()
  local function with(tbl, key, value, fn)
    local original = tbl[key]
    tbl[key] = value
    local ok, err = pcall(fn)
    tbl[key] = original
    if not ok then error(err, 0) end
  end

  -- ── 1. :Image orphans — Delete asks, and deletes only on a late yes ─────
  do
    local orphans = require("images.orphans")
    local deleted = {}
    local picked = { rel = "assets/a.png", path = "/nonexistent/assets/a.png" }
    local answers = {}
    local asked = {}
    local kit_before = package.loaded["ui.kit"]
    package.loaded["ui.kit"] = {
      select = function(o)
        o.on_select(o.items[1])
      end,
    }
    with(orphans, "find", function()
      return { picked }
    end, function()
      with(orphans, "delete", function(path)
        deleted[#deleted + 1] = path
        return true
      end, function()
        with(dialog, "yesno", function(question, label, cb)
          asked[#asked + 1] = { question = question, label = label }
          answers[#answers + 1] = cb
        end, function()
          require("images").orphans()
          H.eq(#asked, 1, "orphans: one question per pick")
          H.eq(asked[1].label, "delete", "orphans: the verb names the action")
          H.eq(#deleted, 0, "orphans: nothing is deleted before the answer")
          answers[1](false)
          H.eq(#deleted, 0, "orphans: a no deletes nothing")
          require("images").orphans()
          answers[2](true)
          H.eq(deleted[1], picked.path, "orphans: a late yes deletes the picked file")
        end)
      end)
    end)
    package.loaded["ui.kit"] = kit_before
  end

  -- ── 2. :Image calibrate — the save question ──────────────────────────────
  do
    local calibration = require("images.calibration")
    local calibrate = require("images.calibrate")
    local saved = {}
    local ask
    with(calibration, "save", function(values)
      saved[#saved + 1] = values
      return true
    end, function()
      with(dialog, "choose", function(msg, choices, default, cb)
        ask = { msg = msg, choices = choices, default = default, cb = cb }
      end, function()
        calibrate.offer_save(3, 4, 1.0)
        H.ok(ask ~= nil, "calibrate: the save question is asked")
        H.eq(ask.default, 1, "calibrate: not saving is the focused answer")
        H.eq(#saved, 0, "calibrate: nothing is saved before the answer")
        ask.cb(1)
        H.eq(#saved, 0, "calibrate: 'Just show me the values' saves nothing")
        ask.cb(0)
        H.eq(#saved, 0, "calibrate: a dismissal saves nothing")
        calibrate.offer_save(3, 4, 1.0)
        ask.cb(2)
        H.eq(#saved, 1, "calibrate: Save, answered later, saves once")
        H.eq(saved[1].terminal_padding and saved[1].terminal_padding.row, 3, "calibrate: the measured row is saved")
      end)
    end)
  end

  -- ── 3. paste chain — file-name prompt and alt-text prompt ────────────────
  do
    local paste = require("images.paste")
    config.setup({ paste = { dir = "docs/img", ask_alt_text = true, link_cursor = { startinsert = false } } })

    ---@return integer buf
    local function make_buf()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/docs/img", "p")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      vim.api.nvim_set_current_buf(buf)
      return buf
    end

    local function capture(out, cb)
      local fd = assert(io.open(out, "wb"))
      fd:write("x")
      fd:close()
      cb(true)
    end

    local function first_line(buf)
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    end

    for _, case in ipairs({
      { answer = "a cat", expect_alt = "![a cat](", label = "a late alt text ends up in the link" },
      { answer = nil, expect_alt = "![](", label = "a cancelled alt text still inserts the link, without alt text" },
    }) do
      local buf = make_buf()
      local pending
      with(dialog, "input", function(_, cb)
        pending = cb
      end, function()
        paste.paste_with_name(buf, "shot.png", capture)
        vim.wait(2000, function()
          return pending ~= nil
        end)
        H.ok(pending ~= nil, "paste: the alt-text prompt is asked")
        H.eq(first_line(buf), "", "paste: no link before the alt text is answered")
        pending(case.answer)
      end)
      vim.wait(2000, function()
        return first_line(buf) ~= ""
      end)
      H.ok(first_line(buf):find(case.expect_alt, 1, true) ~= nil, "paste: " .. case.label .. " (" .. first_line(buf) .. ")")
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end

    -- file-name prompt (a keymap's force_ask): cancelling does nothing, answering carries on
    config.setup({ paste = { dir = "docs/img", ask_alt_text = false, link_cursor = { startinsert = false } } })
    for _, answer in ipairs({ false, "My Shot" }) do
      local buf = make_buf()
      local captured = 0
      local pending
      with(dialog, "input", function(_, cb)
        pending = cb
      end, function()
        paste.capture_with_optional_name(function(out, cb)
          captured = captured + 1
          capture(out, cb)
        end, nil, true)
        H.ok(pending ~= nil, "paste: the file-name prompt is asked")
        H.eq(captured, 0, "paste: nothing is captured before the name is answered")
        pending(answer or nil)
      end)
      vim.wait(answer and 2000 or 50, function()
        return first_line(buf) ~= ""
      end)
      if answer then
        H.eq(captured, 1, "paste: a late name starts the capture")
        H.ok(first_line(buf):find("docs/img/", 1, true) ~= nil, "paste: ...and the link is inserted: " .. first_line(buf))
      else
        H.eq(captured, 0, "paste: a cancelled name captures nothing")
      end
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end
