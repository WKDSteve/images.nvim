---@diagnostic disable: duplicate-set-field
-- TESTS/pty_osc1337_spec.lua -- the OSC 1337 image in the byte stream of a real terminal.
--
-- osc1337_sequence_spec.lua compares the string handed to nvim_ui_send. Here a real Neovim runs inside
-- tmux (WSL on Windows, testing.nvim's `testing.pty`), draws a tiny image and the bytes that reach the
-- terminal are read back: the sequence as the program wrote it (inside tmux wrapped in the passthrough
-- envelope), which the screen grid of the terminal would swallow. Skipped (n/a) without tmux or without
-- testing.nvim on the runtimepath.

---@param H table harness from TESTS/run.lua
return function(H)
  local ok_pty, pty = pcall(require, "testing.pty")
  if not ok_pty then
    print("n/a  testing.nvim is not on the runtimepath (testing.pty)")
    return
  end
  local available, reason = pty.available()
  if not available then
    print("n/a  " .. reason)
    return
  end

  local ESC, BEL = string.char(27), string.char(7)

  ---Windows path -> the path WSL sees (`E:\x` -> `/mnt/e/x`); Linux paths stay.
  ---@param path string
  ---@return string
  local function host_path(path)
    path = path:gsub(string.char(92), "/")
    local drive, rest = path:match("^(%a):(.*)$")
    if not drive then return path end
    return "/mnt/" .. drive:lower() .. rest
  end

  local function root_of(module)
    local found = vim.api.nvim_get_runtime_file("lua/" .. module:gsub("%.", "/") .. "/init.lua", false)[1]
      or vim.api.nvim_get_runtime_file("lua/" .. module:gsub("%.", "/") .. ".lua", false)[1]
    return found and vim.fn.fnamemodify(found, ":p"):match("^(.*)[/" .. string.char(92) .. "]lua[/" .. string.char(92) .. "]")
  end

  local images_root, lib_root = root_of("images"), root_of("lib.nvim")
  if not (images_root and lib_root) then
    print("n/a  the plugin or lib.nvim root is not on the runtimepath")
    return
  end

  H.tmpdir(function(dir)
    local img = dir .. "/probe.png"
    local raw = "\137PNG\r\n\26\nbytes of a tiny image"
    H.write(img, raw)

    local lua_cmd = ("lua require('images.terminal').draw(%q, 3, 7, 10, 4)"):format(host_path(img))
    local session, err = pty.open({
      "nvim",
      "--clean",
      "--cmd",
      "set rtp+=" .. host_path(images_root) .. "," .. host_path(lib_root),
      "-c",
      lua_cmd,
    }, { cols = 100, rows = 30 })
    H.ok(session ~= nil, "the session starts: " .. tostring(err))
    if not session then return end

    local found = session:wait_for("]1337;File=inline=1", 10000, "raw")
    local stream = session:raw()
    session:close()

    H.ok(found, "the image sequence reaches the terminal")
    -- Inside tmux only the OSC payload sits in the passthrough envelope (ESC P tmux ; ... ESC \), its
    -- inner escapes doubled; the cursor sequences around it are plain.
    H.ok(stream:find(ESC .. "Ptmux;", 1, true), "the payload is wrapped for tmux")
    H.ok(
      stream:find(ESC .. ESC .. "]1337;File=inline=1;size=" .. #raw .. ";width=10;height=4;preserveAspectRatio=1:", 1, true),
      "the parameters: byte size of the file, box in cells, aspect kept"
    )
    H.ok(stream:find(vim.base64.encode(raw), 1, true), "the file travels base64-encoded")
    H.ok(stream:find(ESC .. "[3;7H", 1, true), "positioned at row 3, column 7 outside the envelope")
    H.ok(stream:find(BEL, 1, true), "terminated with BEL")
  end)
end
