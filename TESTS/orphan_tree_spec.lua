-- TESTS/orphan_tree_spec.lua -- unreferenced images of a project (`images.orphan_index`) and the badge a
-- tree view gets for them (`images.integrations.tree`, the decorator `orphan` at lib.nvim.tree.registry).
-- That a tree draws a registered badge is filetree.nvim's own spec; here: what is found, that the lookup
-- touches no file, and that nothing is scanned before a tree listens.

---@diagnostic disable: need-check-nil, duplicate-set-field

---@param H table harness from TESTS/run.lua
return function(H)
  local index = require("images.orphan_index")
  local tree = require("images.integrations.tree")
  local registry = require("lib.nvim.tree.registry")
  require("images.config").setup(nil) -- default paste.dir = "assets"

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = index.norm(vim.uv.fs_realpath(root) or root)

  ---@param rel string
  ---@param text? string
  local function write(rel, text)
    local path = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = assert(io.open(path, "wb"))
    fd:write(text or "x")
    fd:close()
    return path
  end

  ---@param set table<string, any>
  ---@return string  the keys relative to the root, sorted, one per line
  local function rels(set)
    local out = {}
    for path in pairs(set) do
      out[#out + 1] = path:sub(#root + 2)
    end
    table.sort(out)
    return table.concat(out, "\n")
  end

  -- ── fixture ───────────────────────────────────────────────────────────────
  write(
    "doc.md",
    table.concat({
      "# Doc",
      "![a](assets/a.png)",
      '<img src="assets/c%20d.png" alt="html, with an escaped space">',
      "![from the root](/assets/root.png) and ![web](https://example.org/assets/b.png)",
      '![titled](assets/t.png "a title")',
      "",
    }, "\r\n")
  )
  write("assets/a.png")
  write("assets/b.png") -- nobody links it: an orphan (the web link of the same name is no file)
  write("assets/c d.png")
  write("assets/root.png")
  write("assets/t.png")
  write("assets/e.png") -- linked from sub/note.md with ..
  write("assets/notes.txt") -- no image
  write("sub/note.md", "![up](../assets/e.png)\n[plain link](assets/g.png)\n![ref][pic]\n\n[pic]: assets/h.png 'a title'\n")
  write("sub/assets/h.png") -- linked through a reference definition
  write("sub/assets/w.png") -- embedded the Obsidian way, from another folder
  write("sub/assets/v.png")
  write("wiki/page.md", "![[w.png]] and [[sub/assets/v.png|with a path and an alias]]\n")
  write("sub/assets/f.png") -- an orphan in the paste folder of another document
  write("sub/assets/g.png")
  write("icons/logo.png") -- no paste folder: an image the code may load, never judged
  write(".git/assets/x.png") -- a dot folder is not entered
  write(".git/readme.md", "x")
  write("node_modules/pkg/readme.md", "x")
  write("node_modules/pkg/assets/y.png")

  -- ── what is found ─────────────────────────────────────────────────────────
  local result = index.scan_sync(root)
  H.eq(rels(result.orphans), "assets/b.png\nsub/assets/f.png", "the two images no document links")
  H.eq(result.partial, false)
  H.eq(result.docs, 3, "doc.md, sub/note.md and wiki/page.md; nothing below .git or node_modules")
  H.eq(result.images, 11, "the images in the two paste folders")
  H.eq(result.root, root)

  H.eq(table.concat(index.wiki_names_in_line("![[a.png]] [[d/b.png|x]] [[c.png#top]]"), " "), "a.png b.png c.png")
  H.eq(table.concat(index.targets_in_line("  [pic]: assets/h.png"), " "), "assets/h.png")
  H.ok(tree.too_wide(vim.uv.os_homedir()), "the home folder is no project")
  H.ok(tree.too_wide("C:\\") and tree.too_wide("/"), "nor is the top of a drive")
  H.falsy(tree.too_wide(root))

  -- paths
  H.eq(index.collapse("C:/a/b/../c/./d.png"), "C:/a/c/d.png")
  H.eq(index.collapse("/a/../../b"), "/b", "a .. above the top is dropped")
  H.eq(index.norm("c:\\a\\b\\"), "C:/a/b")
  H.eq(index.target_path("img/a.png", "/p/docs", "/p"), "/p/docs/img/a.png")
  H.eq(index.target_path("<img/a b.png>", "/p/docs", "/p"), "/p/docs/img/a b.png", "angle brackets")
  H.eq(index.target_path("a.png?raw=1#frag", "/p", "/p"), "/p/a.png", "query and fragment")
  H.eq(index.target_path("https://example.org/a.png", "/p", "/p"), nil, "remote")
  H.eq(index.target_path("data:image/png;base64,AAAA", "/p", "/p"), nil)
  H.eq(index.target_path("#section", "/p", "/p"), nil)
  H.eq(index.target_path("D:\\pics\\a.png", "/p", "/p"), "D:/pics/a.png", "an absolute Windows path")
  local path, from_root = index.target_path("/img/a.png", "/p/docs", "/p")
  H.eq(path, "/img/a.png")
  H.eq(from_root, "/p/img/a.png", "a leading slash is also read from the root")

  -- a second scan reads no document again; a written one is read, and only that one
  local read_before = index.stats.docs_read
  H.eq(rels(index.scan_sync(root).orphans), "assets/b.png\nsub/assets/f.png", "the same answer from the cache")
  H.eq(index.stats.docs_read, read_before, "an unchanged project costs no document read")
  write("wiki/page.md", "![[w.png]] and [[sub/assets/v.png|x]] and now ![[f.png]] as well\n")
  H.eq(rels(index.scan_sync(root).orphans), "assets/b.png", "a written document is read again")
  H.eq(index.stats.docs_read, read_before + 1, "... and only that one")
  write("wiki/page.md", "![[w.png]] and [[sub/assets/v.png|with a path and an alias]]\n")
  vim.uv.fs_unlink(root .. "/sub/note.md")
  H.eq(
    rels(index.scan_sync(root).orphans),
    "assets/b.png\nassets/e.png",
    "a deleted document takes its links along, cache or not (and sub/assets is no paste folder without it)"
  )
  write("sub/note.md", "![up](../assets/e.png)\n[plain link](assets/g.png)\n![ref][pic]\n\n[pic]: assets/h.png 'a title'\n")
  H.eq(rels(index.scan_sync(root).orphans), "assets/b.png\nsub/assets/f.png", "fixture: as before")

  -- a walk that was cut short names nothing: an unread link would make an image look unlinked
  local max_entries = index.MAX_ENTRIES
  index.MAX_ENTRIES = 3
  local cut = index.scan_sync(root)
  index.MAX_ENTRIES = max_entries
  H.eq(cut.partial, true)
  H.eq(rels(cut.orphans), "", "no orphan from a partial walk")

  -- so does a document too large to read
  local max_bytes = index.MAX_DOC_BYTES
  index.MAX_DOC_BYTES = 10
  local unread = index.scan_sync(root)
  index.MAX_DOC_BYTES = max_bytes
  H.eq(unread.partial, true)
  H.eq(rels(unread.orphans), "")

  -- ── in the background ─────────────────────────────────────────────────────
  local slice = index.SLICE_MS
  index.SLICE_MS = 0 -- every step its own slice: the scan must survive being interrupted everywhere
  local done
  index.scan(root, function(r)
    done = r
  end)
  H.eq(done, nil, "scan() returns before anything is read")
  H.ok(
    vim.wait(5000, function()
      return done ~= nil
    end, 5),
    "the background scan ends"
  )
  H.eq(rels(done.orphans), "assets/b.png\nsub/assets/f.png", "the same answer in slices")
  local late
  local cancel = index.scan(root, function(r)
    late = r
  end)
  cancel()
  vim.wait(200, function()
    return late ~= nil
  end, 5)
  H.eq(late, nil, "a cancelled scan reports nothing")
  index.SLICE_MS = slice

  -- ── the decorator ─────────────────────────────────────────────────────────
  local cwd = vim.fn.getcwd()
  vim.cmd.cd(root)
  H.ok(tree.register(), "registered")
  local decorator = registry.get("decorator", tree.NAME)
  H.ok(decorator, "the entry is at the registry")
  H.eq(decorator.key, "path")
  H.eq(decorator.roll_up, "count", "a folder shows how many lie below it")
  H.eq(decorator.slot, "badge")

  vim.wait(100, function()
    return tree.last_scan() ~= nil
  end, 5)
  H.eq(tree.last_scan(), nil, "nothing is scanned before a tree subscribes")
  H.eq(decorator.get(root .. "/assets/b.png"), nil)
  H.falsy(pcall(vim.api.nvim_get_autocmds, { group = "images.tree.orphans" }), "and no autocommand waits")

  local emitted = {}
  local unsubscribe = decorator.subscribe(function(keys)
    emitted[#emitted + 1] = keys or "all"
  end)
  H.eq(#emitted, 0, "subscribing returns before the scan")
  H.ok(
    vim.wait(5000, function()
      return #emitted > 0
    end, 5),
    "the scan of the working directory reports"
  )
  H.eq(table.concat(emitted[1], "\n"), root .. "/assets/b.png\n" .. root .. "/sub/assets/f.png", "the keys that changed")

  -- `get` and `all` while every way to the disk is closed
  local fs_stat, fs_scandir, fs_open, io_open = vim.uv.fs_stat, vim.uv.fs_scandir, vim.uv.fs_open, io.open
  local function closed()
    error("the lookup touched the disk")
  end
  vim.uv.fs_stat, vim.uv.fs_scandir, vim.uv.fs_open, io.open = closed, closed, closed, closed
  local looked, badge = pcall(decorator.get, root .. "/assets/b.png")
  local looked_miss, miss = pcall(decorator.get, root .. "/assets/a.png")
  local listed, all = pcall(decorator.all)
  vim.uv.fs_stat, vim.uv.fs_scandir, vim.uv.fs_open, io.open = fs_stat, fs_scandir, fs_open, io_open
  H.ok(looked and looked_miss and listed, "get and all are table lookups")
  H.eq(badge.text, "orphan")
  H.eq(badge.count, 1)
  H.eq(badge.status, "orphan")
  H.eq(miss, nil, "a referenced image has no badge")
  H.eq(rels(all), "assets/b.png\nsub/assets/f.png")
  H.eq(decorator.get(root .. "/icons/logo.png"), nil, "an image outside a paste folder is not judged")

  -- a document is written that links the orphan: the badge goes, a moment later, and only its key is named
  tree.DEBOUNCE_MS = 10
  emitted = {}
  write("doc.md", "![a](assets/a.png) ![b](assets/b.png) ![c](<assets/c d.png>) ![r](assets/root.png) ![t](assets/t.png)\n")
  vim.api.nvim_exec_autocmds("BufWritePost", { pattern = root .. "/doc.md" })
  vim.api.nvim_exec_autocmds("BufWritePost", { pattern = root .. "/doc.md" })
  H.ok(
    vim.wait(5000, function()
      return #emitted > 0
    end, 5),
    "a written document starts a scan"
  )
  H.eq(table.concat(emitted[1], "\n"), root .. "/assets/b.png")
  H.eq(decorator.get(root .. "/assets/b.png"), nil)
  H.ok(decorator.get(root .. "/sub/assets/f.png"), "the other orphan stays")
  vim.wait(100, function()
    return #emitted > 1
  end, 5)
  H.eq(#emitted, 1, "two writes close together are one scan")

  -- a file that is neither a document nor an image starts nothing
  local scans = tree.last_scan()
  vim.api.nvim_exec_autocmds("BufWritePost", { pattern = root .. "/main.lua" })
  vim.wait(100, function()
    return tree.last_scan() ~= scans
  end, 5)
  H.ok(tree.last_scan() == scans, "a Lua file is no reason to scan")

  -- a file operation of a tree: the orphan is deleted
  emitted = {}
  vim.uv.fs_unlink(root .. "/sub/assets/f.png")
  vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeChanged" })
  H.ok(
    vim.wait(5000, function()
      return #emitted > 0
    end, 5),
    "a file operation starts a scan"
  )
  H.eq(rels(decorator.all()), "", "no orphan is left")

  -- the last tree leaves: nothing waits any more
  unsubscribe()
  H.falsy(pcall(vim.api.nvim_get_autocmds, { group = "images.tree.orphans" }), "the autocommands are gone")
  local before = tree.last_scan()
  tree.rescan()
  vim.wait(100, function()
    return tree.last_scan() ~= before
  end, 5)
  H.ok(tree.last_scan() == before, "rescan() without a listening tree scans nothing")

  -- ── the badge text, unregister, the option ────────────────────────────────
  write("assets/new.png")
  H.ok(tree.register({ badge = "unused" }))
  decorator = registry.get("decorator", tree.NAME)
  emitted = {}
  local unsubscribe2 = decorator.subscribe(function(keys)
    emitted[#emitted + 1] = keys or "all"
  end)
  vim.wait(5000, function()
    return #emitted > 0
  end, 5)
  H.eq(decorator.get(root .. "/assets/new.png").text, "unused", "a configured badge text")
  unsubscribe2()
  tree.unregister()
  H.eq(registry.get("decorator", tree.NAME), nil, "unregister takes the entry out")
  H.eq(tree.last_scan(), nil)

  local config = require("images.config")
  config.setup({ tree = false })
  H.eq(config.get().tree, false, "tree = false is a known option")
  H.eq(#config.issues(), 0, "and no issue: " .. table.concat(config.issues(), "; "))
  config.setup({ tree = { badge = "x" } })
  H.eq(config.get().tree.badge, "x")
  config.setup(nil)
  H.eq(config.get().tree, true, "on by default")

  tree.DEBOUNCE_MS = 400
  vim.cmd.cd(cwd)
  vim.fn.delete(root, "rf")
end
