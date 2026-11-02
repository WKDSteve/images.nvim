-- TESTS/menu_spec.lua — images.integrations.menu: the nvzone/menu-shaped
-- entry list a host splices into its own right-click menu.
--
-- `images.integrations.menu` hard-requires `ui.contextmenu` at module load
-- (unlike every soft integration in `images.init`, which `pcall`s `ui.kit` —
-- see images/init.lua's own `kit()`): a host only ever loads this module
-- because it is already building a menu with ui.nvim's builders, so that is
-- a deliberate hard dependency, not a bug (see docs/CONTRIBUTING.md: this is
-- one of the "soft-dependency bridges" under `integrations/`, soft meaning
-- the *target* — nvzone/menu — not ui.nvim itself).
--
-- TESTS/run.lua deliberately does NOT add ui.nvim to this suite's shared
-- runtimepath/package.path — compare_spec.lua's regression coverage for
-- `:Image compare` depends on `ui.kit` staying unreachable there (see its own
-- header). So this spec resolves ui.nvim on its own, scoped to this file: it
-- extends `package.path` only for the duration of this function and restores
-- the original value before returning, on every exit path, so no other spec
-- (run before or after this one) ever observes the change. If no sibling
-- checkout is found, this spec is a clean no-op, the same convention
-- resolve_spec.lua uses for its own gopath.nvim block.

---@param H table harness from TESTS/run.lua
return function(H)
  local repo = vim.fs.normalize(vim.uv.cwd())

  ---@return string|nil
  local function find_ui_nvim()
    local candidates = {}
    if vim.env.UI_NVIM_PATH then candidates[#candidates + 1] = vim.env.UI_NVIM_PATH end
    candidates[#candidates + 1] = repo .. "/../ui.nvim"
    candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/ui.nvim"
    for _, path in ipairs(candidates) do
      local norm = vim.fs.normalize(path)
      if vim.fn.isdirectory(norm .. "/lua/ui") == 1 then return norm end
    end
    return nil
  end

  local ui_nvim = find_ui_nvim()
  if not ui_nvim then
    -- no sibling checkout: nothing to test against
    print("n/a  the menu checks need a ui.nvim checkout")
    return
  end

  local original_package_path = package.path
  package.path = table.concat({ ui_nvim .. "/lua/?.lua", ui_nvim .. "/lua/?/init.lua", package.path }, ";")

  local ok_menu, menu = pcall(require, "images.integrations.menu")
  if not ok_menu then
    -- A sibling checkout exists but does not actually provide ui.contextmenu
    -- (an unrelated or half-built directory) — degrade the same as "absent".
    package.path = original_package_path
    return
  end

  require("images.config").setup(nil)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"

  -- ── enabled, allowed filetype: a populated, well-shaped list ─────────────
  local items = menu.items(buf)
  H.ok(#items > 0, "a markdown buffer with menu.enable = true gets entries")
  for i, item in ipairs(items) do
    H.ok(type(item.name) == "string" and #item.name > 0, ("item %d has a non-empty name"):format(i))
  end

  -- ── processing actions are part of the list, gated on their tool ─────────
  local function names(list)
    local out = {}
    for _, item in ipairs(list) do
      out[item.name or ""] = true
    end
    return out
  end
  local have_names = names(items)
  H.ok(have_names["Export as PDF"] and have_names["Zen view"], "tool-free actions are always listed")
  local exe = require("lib.nvim.cross.executable")
  local real_exists = exe.exists
  exe.exists = function()
    return false
  end
  local bare = names(menu.items(buf))
  exe.exists = real_exists
  H.ok(bare["Export as PDF"] and bare["Zen view"], "tool-free actions stay without any tool")
  H.ok(not bare["Read text (OCR)"] and not bare["Redact (black out areas)"], "OCR and redact need their tool")
  H.ok(not bare["Optimise copy"] and not bare["Scale copy…"] and not bare["Convert copy…"], "magick actions need magick")
  exe.exists = function()
    return true
  end
  local full = names(menu.items(buf))
  exe.exists = real_exists
  H.ok(full["Read text (OCR)"] and full["Optimise copy"], "with the tools every action is listed")

  -- ── items_for_path: no filetype gate, every action acts on the path ──────
  vim.bo[buf].filetype = "lua"
  H.eq(#menu.items_for_path(""), 0, "an empty path gives no entries")
  H.eq(#menu.items_for_path(nil), 0, "no path gives no entries")
  local path_items = menu.items_for_path("/tmp/pic.png")
  H.ok(#path_items > 0, "a path gives entries even in a lua buffer")
  local images = require("images")
  local seen = {}
  local real_info, real_zen = images.info, images.zen
  images.info = function(p)
    seen.info = p
  end
  images.zen = function(p)
    seen.zen = p
  end
  for _, item in ipairs(path_items) do
    if item.name == "Show image info" then item.cmd() end
    if item.name == "Zen view" then item.cmd() end
  end
  images.info, images.zen = real_info, real_zen
  H.eq(seen.info, "/tmp/pic.png", "info acts on the given path")
  H.eq(seen.zen, "/tmp/pic.png", "zen acts on the given path")
  require("images.config").setup({ menu = { enable = false } })
  H.eq(#menu.items_for_path("/tmp/pic.png"), 0, "menu.enable = false: no entries for a path either")
  require("images.config").setup({})
  vim.bo[buf].filetype = "markdown"

  -- ── menu.enable = false: no entries, regardless of filetype ──────────────
  require("images.config").setup({ menu = { enable = false } })
  H.eq(#menu.items(buf), 0, "menu.enable = false returns no entries")

  -- ── enabled(): what ui.nvim's ui.menu asks first ─────────────────────────
  require("images.config").setup({})
  H.eq(menu.enabled(), true, "enabled() is true by default")
  require("images.config").setup({ integrations = { ui_menu = false } })
  H.eq(menu.enabled(), false, "integrations.ui_menu = false -> enabled() false")
  H.ok(#menu.items(buf) > 0, "ui_menu = false leaves items() to other hosts")
  require("images.config").setup({ menu = { enable = false } })
  H.eq(menu.enabled(), false, "menu.enable = false -> enabled() false")

  -- ── filetype not in keymaps.filetypes: no entries ─────────────────────────
  require("images.config").setup({})
  vim.bo[buf].filetype = "lua"
  H.eq(#menu.items(buf), 0, "an unconfigured filetype returns no entries")

  -- ── no filetype at all: no entries (not an error) ─────────────────────────
  vim.bo[buf].filetype = ""
  H.eq(#menu.items(buf), 0, "a buffer with no filetype returns no entries")

  -- ── submenu(): nil when there is nothing to show, an item when there is ──
  vim.bo[buf].filetype = "markdown"
  require("images.config").setup({})
  H.ok(menu.submenu(nil, buf) ~= nil, "submenu() wraps a non-empty item list")
  require("images.config").setup({ menu = { enable = false } })
  H.eq(menu.submenu(nil, buf), nil, "submenu() is nil when items() is empty")

  require("images.config").setup({})
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  package.path = original_package_path
end
