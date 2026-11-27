---@module 'images.integrations.menu'
---@brief Context menu entries for a host's right-click menu (`ui.contextmenu` item shape; a soft, opt-in integration).
---@description
--- images.nvim has no dependency on a menu plugin. It *supplies* a list of
--- entries built with the helpers from `ui.contextmenu` (ui.nvim's menu), and a host — typically the user's own RightMouse
--- dispatcher — composes them into its own menu, e.g.:
--- >
---   local items = require("images.integrations.menu").items()
---   -- append/prepend `items` to your own menu, then menu.open(composed)
--- <
--- `items(bufnr)` is bound to `keymaps.filetypes` (default markdown/vimwiki/norg/text) — the
--- same condition under which the buffer-local keys from
--- `images.bindings.keymaps` are registered at all. No pre-check for "is the
--- cursor really on an image": the underlying functions (hover/info/…) report
--- that themselves via notify, exactly as the double-click handler already
--- does. `items_for_path(path)` is the variant for hosts that already know the file
--- (a tree node, an image buffer): no filetype gate, every action acts on `path`.
--- Entries that need a tool (tesseract, magick) are left out when it is missing.
--- Opt out via `config.menu.enable`.

local contextmenu = require("ui.contextmenu")
local nerd = require("lib.nvim.ui.nerd_font")

---@internal
--- One glyph per entry, drawn in the renderer's icon column (`opts.icon`), never in the
--- label: a label that starts with spaces or a glyph indents its row past every other one.
--- ASCII fallback without a declared Nerd Font.
---@type table<string, string>
local ICON = {
  show = nerd.glyph("F0208", "v"), -- eye-outline
  gallery = nerd.glyph("F02E9", "g"), -- image-multiple
  next = nerd.glyph("F0054", ">"), -- arrow-right
  prev = nerd.glyph("F004D", "<"), -- arrow-left
  paste = nerd.glyph("F0192", "p"), -- content-paste
  screenshot = nerd.glyph("F0100", "s"), -- camera
  info = nerd.glyph("F02FC", "i"), -- information-outline
  ocr = nerd.glyph("F0A5B", "t"), -- text-recognition
  redact = nerd.glyph("F01B4", "#"), -- trash-can
  export = nerd.glyph("F0226", "P"), -- file-pdf-box
  scale = nerd.glyph("F0BB1", "%"), -- swap-horizontal
  optimise = nerd.glyph("F0BB1", "o"), -- swap-horizontal
  convert = nerd.glyph("F0BB1", "c"), -- swap-horizontal
  zen = nerd.glyph("F0208", "z"), -- eye-outline
  replace = nerd.glyph("F0192", "r"), -- content-paste
  compare = nerd.glyph("F0BB1", "="), -- swap-horizontal
  images = nerd.glyph("F02E9", "I"), -- image-multiple
}

---@internal
---@param bin string
---@return boolean
local function have(bin)
  return require("lib.nvim.cross.executable").exists(bin)
end

---@internal
--- The processing actions (OCR, redact, export, scale, optimise, convert, zen, replace, compare),
--- each acting on `path` (nil: the image under the cursor) and gated on what it needs.
---@param path? string
---@return Ui.ContextMenu.Item|nil ...
local function processing_entries(path)
  local images = require("images")
  local magick = have("magick")
  return contextmenu.entry(have("tesseract"), "Read text (OCR)", function()
    images.ocr(path)
  end, nil, { icon = ICON.ocr }),
    contextmenu.entry(magick, "Redact (black out areas)", function()
      images.redact(path)
    end, nil, { icon = ICON.redact }),
    contextmenu.entry(true, "Export as PDF", function()
      images.export(path)
    end, nil, { icon = ICON.export }),
    contextmenu.entry(magick, "Scale copy…", function()
      vim.ui.input({ prompt = "Scale to (50%, 800x600, 800): " }, function(spec)
        if spec and spec ~= "" then images.scale(spec, path) end
      end)
    end, nil, { icon = ICON.scale }),
    contextmenu.entry(magick, "Optimise copy", function()
      images.optimise(path)
    end, nil, { icon = ICON.optimise }),
    contextmenu.entry(magick, "Convert copy…", function()
      vim.ui.select(require("images.convert").target_formats(), { prompt = "Convert to:" }, function(format)
        if format then images.convert(format, path) end
      end)
    end, nil, { icon = ICON.convert }),
    contextmenu.entry(true, "Zen view", function()
      images.zen(path)
    end, nil, { icon = ICON.zen }),
    contextmenu.entry(true, "Replace with clipboard image", function()
      images.replace(path)
    end, nil, { icon = ICON.replace }),
    contextmenu.entry(true, "Compare two images…", function()
      -- Searched in the folder of the clicked image, not the working directory.
      if path then
        images.compare("path", vim.fs.dirname(path))
      else
        images.compare()
      end
    end, nil, { icon = ICON.compare })
end

local M = {}

---@internal
---@param ft string|nil
---@param fts string[]
---@return boolean
local function ft_allowed(ft, fts)
  if not ft or ft == "" then return false end
  for _, f in ipairs(fts) do
    if f == ft then return true end
  end
  return false
end

--- Whether a host that asks first (ui.nvim's `ui.menu`) may show this
--- plugin's fly-out: `integrations.ui_menu` is not false and the `menu` group
--- is not switched off. `items()`/`submenu()` themselves stay governed by
--- `menu` alone, so other hosts are unaffected by `ui_menu`.
---@return boolean
function M.enabled()
  local cfg = require("images.config").get()
  if (cfg.integrations or {}).ui_menu == false then return false end
  return (cfg.menu or {}).enable ~= false
end

--- Build the images.nvim menu entries for `bufnr`.
--- Returns an empty list when the integration is disabled or the filetype is
--- not configured, so a host can splice it in with `vim.list_extend` without
--- further checks.
---@param bufnr? integer default: current buffer
---@return Ui.ContextMenu.Item[]
function M.items(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local cfg = require("images.config").get()
  local mcfg = cfg.menu or {}
  if mcfg.enable == false then return {} end

  local fts = (cfg.keymaps and cfg.keymaps.filetypes) or {}
  if not ft_allowed(vim.bo[bufnr].filetype, fts) then return {} end

  local km = cfg.keymaps or {}
  local images = require("images")
  local out = {}

  contextmenu.group(
    out,
    contextmenu.entry(true, "Show image under cursor", images.hover, km.show, { icon = ICON.show }),
    contextmenu.entry(true, "Gallery (every image in the buffer)", images.gallery, km.gallery, { icon = ICON.gallery }),
    contextmenu.entry(true, "Next image", function()
      images.step(1)
    end, km.next, { icon = ICON.next }),
    contextmenu.entry(true, "Previous image", function()
      images.step(-1)
    end, km.prev, { icon = ICON.prev })
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "Paste image from clipboard", function()
      images.paste()
    end, km.paste, { icon = ICON.paste }),
    contextmenu.entry(true, "Take a screenshot", images.screenshot, km.screenshot, { icon = ICON.screenshot })
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "Show image info", function()
      images.info()
    end, nil, { icon = ICON.info })
  )

  contextmenu.group(out, processing_entries(nil))

  return out
end

--- The entries for a host that already knows the file (a filetree node, an image buffer, open.nvim):
--- every action acts on `path`, and there is no filetype gate. Empty when the integration is
--- disabled or `path` is not a non-empty string.
---@param path string
---@return Ui.ContextMenu.Item[]
function M.items_for_path(path)
  if type(path) ~= "string" or path == "" then return {} end
  if (require("images.config").get().menu or {}).enable == false then return {} end

  local images = require("images")
  local out = {}
  contextmenu.group(
    out,
    contextmenu.entry(true, "Show image", function()
      images.show(path)
    end, nil, { icon = ICON.show }),
    contextmenu.entry(true, "Show image info", function()
      images.info(path)
    end, nil, { icon = ICON.info })
  )
  contextmenu.group(out, processing_entries(path))
  return out
end

--- Convenience: the images.nvim entries as a single nested submenu, for hosts
--- that prefer an "Images ▸" fly-out. Returns nil when there is nothing to
--- show.
---@param label? string submenu label (default "Images")
---@param bufnr? integer
---@return Ui.ContextMenu.Item|nil
function M.submenu(label, bufnr)
  return contextmenu.submenu(label or "Images", M.items(bufnr), { icon = ICON.images })
end

return M
