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

  -- ── the roots of the trees ────────────────────────────────────────────────
  -- A second project, which is not the working directory (that is still `root`, with the orphan
  -- assets/new.png from above).
  local other = vim.fn.tempname()
  vim.fn.mkdir(other .. "/assets", "p")
  other = index.norm(vim.uv.fs_realpath(other) or other)
  vim.fn.writefile({ "![a](assets/a.png)" }, other .. "/doc.md")
  vim.fn.writefile({ "x" }, other .. "/assets/a.png")
  vim.fn.writefile({ "x" }, other .. "/assets/lost.png")

  ---@param set table<string, any>
  ---@return string  the keys, sorted, one per line
  local function keys_of(set)
    local out = vim.tbl_keys(set)
    table.sort(out)
    return table.concat(out, "\n")
  end
  local function roots_changed()
    vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeRoots", modeline = false })
  end

  H.ok(tree.register())
  decorator = registry.get("decorator", tree.NAME)
  local shown = { other }
  emitted = {}
  local unsubscribe3 = decorator.subscribe(function(keys)
    emitted[#emitted + 1] = keys or "all"
  end, {
    roots = function()
      return shown
    end,
  })
  H.ok(
    vim.wait(5000, function()
      return #emitted > 0
    end, 5),
    "the scan of the root of the tree reports"
  )
  H.eq(keys_of(decorator.all()), other .. "/assets/lost.png", "the root the tree shows is scanned, not the working directory")
  H.eq(tree.last_scan(root), nil, "the working directory was not walked")
  H.eq(table.concat(tree.roots(), "\n"), other)

  -- a second tree on another root: that one is scanned, the first is left alone
  local scan_other = tree.last_scan(other)
  shown = { other, root }
  roots_changed()
  H.ok(
    vim.wait(5000, function()
      return decorator.get(root .. "/assets/new.png") ~= nil
    end, 5),
    "a root that is new is scanned"
  )
  H.ok(tree.last_scan(other) == scan_other, "the root that stayed was not scanned again")
  H.ok(decorator.get(other .. "/assets/lost.png"), "and keeps its badge")

  -- `:cd` is nothing to a tree that says which roots it shows
  local scan_root = tree.last_scan(root)
  vim.api.nvim_exec_autocmds("DirChanged", { pattern = "global", modeline = false })
  vim.wait(100, function()
    return tree.last_scan(root) ~= scan_root
  end, 5)
  H.ok(tree.last_scan(root) == scan_root, "DirChanged scans nothing while every tree names its roots")

  -- the tree of the second project is given up: its badges go, and its scan is forgotten
  emitted = {}
  shown = { root }
  roots_changed()
  H.eq(table.concat(emitted[1] or {}, "\n"), other .. "/assets/lost.png", "the badge below a root no tree shows goes at once")
  H.eq(tree.last_scan(other), nil)

  -- two roots, one below the other: sub/ alone has no document that embeds w.png and v.png (wiki/page.md
  -- does, outside of it), so its scan names them; the scan of the project knows better, and wins
  shown = { root, root .. "/sub" }
  roots_changed()
  H.ok(
    vim.wait(5000, function()
      return tree.last_scan(root .. "/sub") ~= nil
    end, 5),
    "the root below is scanned"
  )
  H.ok(
    tree.last_scan(root .. "/sub").orphans[root .. "/sub/assets/w.png"],
    "fixture: on its own the folder calls the image unreferenced"
  )
  H.eq(decorator.get(root .. "/sub/assets/w.png"), nil, "an image the wider root knows a link to carries no badge")
  H.eq(keys_of(decorator.all()), root .. "/assets/new.png")
  shown = { root }
  roots_changed()

  -- a tree that hands no context stands for the working directory
  unsubscribe3()
  emitted = {}
  local unsubscribe4 = decorator.subscribe(function(keys)
    emitted[#emitted + 1] = keys or "all"
  end)
  local roots, by_cwd = tree.roots()
  H.eq(table.concat(roots, "\n"), root, "without a context: the working directory")
  H.eq(by_cwd, true)
  H.ok(vim.wait(5000, function()
    return decorator.get(root .. "/assets/new.png") ~= nil
  end, 5))
  unsubscribe4()

  -- ── the two actions ───────────────────────────────────────────────────────
  local delete = registry.get("action", tree.DELETE)
  local again = registry.get("action", tree.RESCAN)
  H.ok(delete and again, "both actions are at the registry")
  H.eq(delete.key, nil, "no key unless one is configured: the menu of the tree has them")
  H.eq(delete.mutates, true)
  H.eq(again.mutates, false)
  H.eq(table.concat(delete.needs, ","), "file")
  H.eq(table.concat(again.needs, ","), "dir")

  shown = { root }
  local unsubscribe5 = decorator.subscribe(function(keys)
    emitted[#emitted + 1] = keys or "all"
  end, {
    roots = function()
      return shown
    end,
  })
  H.ok(vim.wait(5000, function()
    return decorator.get(root .. "/assets/new.png") ~= nil
  end, 5))
  write("assets/second.png")
  write("assets/third.png")
  tree.rescan()
  H.ok(vim.wait(5000, function()
    return decorator.get(root .. "/assets/third.png") ~= nil
  end, 5))

  H.ok(delete.when({ path = root .. "/assets/new.png" }), "delete applies to an image with the badge")
  H.falsy(delete.when({ path = root .. "/assets/a.png" }), "not to a linked one")
  H.falsy(delete.when({ path = root .. "/doc.md" }), "nor to a document")
  H.falsy(delete.when({}), "nor to a node without a path")

  -- no tree with a trash here: one question of its own, and "no" deletes nothing
  local confirm, notify = vim.fn.confirm, vim.notify
  local asked, said = {}, {}
  local answer = 2
  vim.fn.confirm = function(question)
    asked[#asked + 1] = question
    return answer
  end
  vim.notify = function(message, level)
    said[#said + 1] = { message = message, level = level }
  end
  delete.run({ { path = root .. "/assets/new.png" } })
  H.eq(#asked, 1, "it asks")
  H.contains(asked[1], "new.png")
  H.ok(vim.uv.fs_stat(root .. "/assets/new.png"), "cancel: the image stays")
  H.ok(decorator.get(root .. "/assets/new.png"), "and its badge")

  -- yes: the file goes, the badge goes with it, and no scan was needed for that
  answer = 1
  emitted = {}
  local scan_before = tree.last_scan(root)
  local changed_fired = 0
  local changed_id = vim.api.nvim_create_autocmd("User", {
    pattern = "FileopsChanged",
    callback = function()
      changed_fired = changed_fired + 1
    end,
  })
  delete.run({ { path = root .. "/assets/new.png" }, { path = root .. "/assets/a.png" }, { path = root .. "/doc.md" } })
  H.eq(vim.uv.fs_stat(root .. "/assets/new.png"), nil, "the unreferenced image is deleted")
  H.ok(vim.uv.fs_stat(root .. "/assets/a.png"), "a linked image in the selection is left alone")
  H.ok(vim.uv.fs_stat(root .. "/doc.md"), "and so is a document")
  H.eq(decorator.get(root .. "/assets/new.png"), nil, "the badge is gone at once")
  H.eq(table.concat(emitted[1], "\n"), root .. "/assets/new.png", "only its key is named")
  H.ok(tree.last_scan(root) == scan_before, "without a scan of the project")
  H.eq(changed_fired, 1, "a tree is told that a file went")
  vim.api.nvim_del_autocmd(changed_id)
  -- that event starts a scan a moment later: let it end before the next case
  vim.wait(5000, function()
    return tree.last_scan(root) ~= scan_before
  end, 5)

  -- an image that was linked since the last scan is judged again right before, and stays
  asked, said = {}, {}
  write("late.md", "![s](assets/second.png)\n")
  H.ok(decorator.get(root .. "/assets/second.png"), "fixture: the table still calls it unreferenced")
  delete.run({ { path = root .. "/assets/second.png" } })
  H.eq(#asked, 0, "nothing is asked")
  H.ok(vim.uv.fs_stat(root .. "/assets/second.png"), "an image a document links by now is not deleted")
  H.eq(#said, 1)
  H.contains(said[1].message, "linked by now")
  H.eq(said[1].level, vim.log.levels.WARN)
  H.ok(
    vim.wait(5000, function()
      return decorator.get(root .. "/assets/second.png") == nil
    end, 5),
    "and the table is brought up to date"
  )

  -- with a tree that has a trash: the tree asks and deletes, images.nvim asks nothing
  asked, said = {}, {}
  local handed = {}
  local trash_ok = false
  local third = root .. "/assets/third.png"
  local restore_filetree = package.loaded["filetree"]
  package.loaded["filetree"] = {
    feature = function(name)
      if name ~= "trash" then return nil end
      return {
        available = function()
          return true
        end,
        -- what the delete key of the tree does: it asks, trashes, and says that files changed
        delete_current = function(opts)
          handed[#handed + 1] = table.concat(opts.paths, ",")
          if not trash_ok then return end
          for _, image in ipairs(opts.paths) do
            vim.uv.fs_unlink(image)
          end
          vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeChanged", modeline = false })
        end,
      }
    end,
  }
  delete.run({ { path = third }, { path = root .. "/assets/a.png" } })
  H.eq(table.concat(handed, "\n"), third, "the trash of the tree is handed the unreferenced image, and only that")
  H.eq(#asked, 0, "the tree asks in its own words")
  H.ok(decorator.get(third), "a delete the tree did not do (the person said no) keeps the badge")
  trash_ok = true
  emitted = {}
  local scan_then = tree.last_scan(root)
  delete.run({ { path = third } })
  H.eq(vim.uv.fs_stat(third), nil, "fixture: the tree trashed it")
  H.eq(decorator.get(third), nil, "the badge goes when the tree says that files changed")
  H.eq(table.concat(emitted[1], "\n"), third, "only its key is named")
  H.ok(tree.last_scan(root) == scan_then, "before any scan of the project")
  package.loaded["filetree"] = restore_filetree
  -- that event starts a scan a moment later: let it end before the next case
  vim.wait(5000, function()
    return tree.last_scan(root) ~= scan_then
  end, 5)

  -- "look again" on a folder: a scan, and one line that says what there is
  said = {}
  write("assets/fourth.png")
  again.run({ { path = root .. "/assets" } })
  H.ok(
    vim.wait(5000, function()
      return #said > 0
    end, 5),
    "the action reports when the scan is through"
  )
  H.contains(said[1].message, "1 unreferenced image")
  H.ok(decorator.get(root .. "/assets/fourth.png"), "and the new one has its badge")
  unsubscribe5()
  said = {}
  again.run({})
  H.contains(said[1].message, "no tree shows the badges")
  vim.fn.confirm, vim.notify = confirm, notify

  -- keys, and no actions at all
  H.ok(tree.register({ keys = { delete = "gD" } }))
  H.eq(registry.get("action", tree.DELETE).key, "gD", "a configured key")
  H.eq(registry.get("action", tree.RESCAN).key, nil)
  H.ok(tree.register({ actions = false }))
  H.eq(registry.get("action", tree.DELETE), nil, "actions = false: only the badge")
  H.ok(registry.get("decorator", tree.NAME))
  tree.unregister()
  H.eq(registry.get("action", tree.RESCAN), nil, "unregister takes the actions out")
  config.setup({ tree = { actions = false, keys = { delete = "gD", rescan = { "gR" } } } })
  H.eq(#config.issues(), 0, "the options are known: " .. table.concat(config.issues(), "; "))
  config.setup(nil)

  tree.DEBOUNCE_MS = 400
  vim.cmd.cd(cwd)
  vim.fn.delete(root, "rf")
  vim.fn.delete(other, "rf")
end
