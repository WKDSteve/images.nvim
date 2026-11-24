-- TESTS/paste_selection_spec.lua — `:Image paste` over a visual selection: the
-- selected text is replaced by `![<text>](path)` instead of the link landing at
-- the selection's start. Fake capture (no clipboard), like paste_target_spec.

---@param H table harness from TESTS/run.lua
return function(H)
  local paste = require("images.paste")
  require("images.config").setup({ paste = { confirm_create_dir = false } })

  ---@param lines string[]
  ---@return integer buf, string root
  local function make_buf(lines)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    return buf, root
  end

  local function capture(out, cb)
    local fd = assert(io.open(out, "wb"))
    fd:write("x")
    fd:close()
    cb(true)
  end

  --- Select with real visual-mode keys, leave it (sets the marks), and paste.
  ---@param keys string normal-mode keys that make the selection
  ---@param lines string[]
  ---@return string[] result lines
  local function paste_over(keys, lines)
    local buf = make_buf(lines)
    vim.cmd("normal! gg0")
    vim.cmd("normal! " .. keys .. vim.api.nvim_replace_termcodes("<Esc>", true, true, true))
    paste.paste_with_name(buf, "shot.png", capture, nil, paste.visual_selection(buf))
    local res = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return res
  end

  local r = paste_over("wwve", { "see the red fox now" })
  H.eq(r[1], "see the ![red](assets/shot.png) fox now", "charwise selection becomes the alt text and is replaced")

  r = paste_over("V", { "a whole line", "next" })
  H.eq(r[1], "![a whole line](assets/shot.png)", "linewise selection")
  H.eq(r[2], "next", "…leaves the following line alone")

  r = paste_over("vj$", { "first part", "  second part", "tail" })
  H.eq(r[1], "![first part second part](assets/shot.png)", "multi-line selection collapses to spaces")
  H.eq(#r, 2, "…and joins into one line")

  r = paste_over("vf]", { "[b] c" })
  H.ok(r[1]:find("![\\[b\\]](assets/shot.png)", 1, true) ~= nil, "brackets in the selection are escaped: " .. r[1])

  -- No selection: the link goes at the cursor, empty alt text, as before.
  local buf = make_buf({ "abc" })
  vim.cmd("normal! gg0")
  paste.paste_with_name(buf, "shot.png", capture)
  H.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "![](assets/shot.png)abc", "no selection: unchanged")
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end
