-- TESTS/cache_spec.lua — images.cache: the sweep of the three disk caches. Files are aged with
-- `fs_utime`, so the spec needs no clock stub: old ones go, the young ones stay, a cache over its
-- size limit loses its oldest files first, a fresh `.part` download is left alone.

---@param H table harness from TESTS/run.lua
return function(H)
  local cache = require("images.cache")
  local day = 24 * 60 * 60

  local saved_stdpath = vim.fn.stdpath
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  vim.fn.stdpath = function(what)
    if what == "cache" then return root end
    return saved_stdpath(what)
  end

  ---@param name string
  ---@param file string
  ---@param age_days number
  ---@param bytes? integer
  ---@return string path
  local function put(name, file, age_days, bytes)
    local dir = cache.root() .. "/" .. name
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/" .. file
    local fd = assert(io.open(path, "wb"))
    fd:write(string.rep("x", bytes or 10))
    fd:close()
    local t = os.time() - age_days * day
    assert(vim.uv.fs_utime(path, t, t))
    return path
  end

  local function exists(path)
    return vim.uv.fs_stat(path) ~= nil
  end

  local ok, err = pcall(function()
    -- age: only the old file of each cache goes
    local old_svg, new_svg = put("svg", "old.png", 40), put("svg", "new.png", 1)
    local old_pdf = put("pdf", "old.png", 31)
    local old_remote, new_remote = put("remote", "old.png", 90), put("remote", "new.png", 0)
    local res = cache.sweep({ max_age_days = 30, max_size_mb = 200 })
    H.eq(res.removed, 3, "three aged files removed")
    H.ok(not exists(old_svg) and not exists(old_pdf) and not exists(old_remote), "the aged files are gone")
    H.ok(exists(new_svg) and exists(new_remote), "the young ones stay")

    -- a young .part download is never swept; an old one is
    local part = put("remote", "dl.part", 0)
    local stale_part = put("remote", "stale.part", 60)
    cache.sweep({ max_age_days = 30, max_size_mb = 200 })
    H.ok(exists(part), "a fresh .part survives")
    H.ok(not exists(stale_part), "a stale .part is removed")

    -- size: over the limit the oldest go first, per cache
    local mb = 1024 * 1024
    local a = put("pdf", "a.png", 3, mb)
    local b = put("pdf", "b.png", 2, mb)
    local c = put("pdf", "c.png", 1, mb)
    local other = put("svg", "keep.png", 3, mb)
    cache.sweep({ max_age_days = 30, max_size_mb = 2 })
    H.ok(not exists(a), "the oldest pdf file goes first")
    H.ok(exists(b) and exists(c), "the newer ones fit the limit")
    H.ok(exists(other), "another cache under its limit is untouched")

    -- stats
    local st = cache.stats()
    H.eq(st.pdf.count, 2, "stats counts a cache's files")
    H.ok(st.pdf.bytes >= 2 * mb, "…and their bytes")
    H.eq(cache.stats().svg.count, 2, "svg: new.png and keep.png")

    -- a used entry is not old: touch() restarts its age
    local used = put("svg", "used.png", 40)
    local unused = put("svg", "unused.png", 40)
    cache.touch(used)
    cache.sweep({ max_age_days = 30, max_size_mb = 200 })
    H.ok(exists(used), "a touched file survives the age limit")
    H.ok(not exists(unused), "an untouched one of the same age goes")

    -- an absent cache directory is not an error
    vim.fn.delete(cache.root() .. "/remote", "rf")
    H.eq(cache.stats().remote.count, 0, "a missing cache directory counts as empty")
    H.eq(cache.sweep().removed >= 0, true, "sweeping with a missing directory works")
  end)

  vim.fn.stdpath = saved_stdpath
  vim.fn.delete(root, "rf")
  if not ok then error(err, 0) end
end
