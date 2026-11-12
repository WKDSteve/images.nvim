-- TESTS/export_set_spec.lua -- `:Image export <dir|glob>`: which files make the PDF, in which order, when it asks.
--
-- Real files in a scratch directory; the conversion itself is stubbed at `images.convert.to_pdf_multi` (its argv is
-- convert_spec's), so this needs no magick and pins what is this feature's own: the selection, the natural order, the
-- extension filter, "no match" as a message, the question above `export.confirm_over`, and that a real file is never
-- taken for a glob.

---@param H table harness from TESTS/run.lua
return function(H)
  local set = require("images.export_set")
  local convert = require("images.convert")
  local images = require("images")

  local base = vim.fs.normalize(vim.fn.tempname()) .. "_export_set"
  local function touch(rel)
    local p = base .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(p), "p")
    vim.fn.writefile({ "x" }, p)
    return p
  end
  ---@return string the relative names, `|`-joined (H.eq compares by identity, not by content)
  local function names(list)
    return table.concat(
      vim.tbl_map(function(p)
        return p:sub(#base + 2)
      end, list),
      "|"
    )
  end
  local function join(...)
    return table.concat({ ... }, "|")
  end

  touch("shots/page10.png")
  touch("shots/page2.png")
  touch("shots/Alpha1.PNG")
  touch("shots/notes.txt")
  touch("shots/cover.jpg")
  touch("shots/sub/deep.png")
  touch("shots/odd[1].png")

  -- ── is_set ───────────────────────────────────────────────────────────────
  H.ok(set.is_set(base .. "/shots/*.png"), "is_set: a glob")
  H.ok(set.is_set(base .. "/shots"), "is_set: a directory")
  H.falsy(set.is_set(base .. "/shots/page2.png"), "is_set: a plain file is one image")
  H.falsy(set.is_set(base .. "/shots/odd[1].png"), "is_set: an existing file with brackets in its name is still one file")
  H.falsy(set.is_set(nil), "is_set: nothing")
  H.falsy(set.is_set(""), "is_set: an empty string")
  H.falsy(set.is_set(base .. "/missing.png"), "is_set: a missing plain name is not a set")

  -- ── collect: directory ───────────────────────────────────────────────────
  H.eq(
    names(set.collect(base .. "/shots")),
    join("shots/Alpha1.PNG", "shots/cover.jpg", "shots/odd[1].png", "shots/page2.png", "shots/page10.png"),
    "collect: a directory gives its images, natural order (page2 before page10), case ignored, no txt, no subfolder"
  )
  -- ── collect: glob ────────────────────────────────────────────────────────
  H.eq(
    names(set.collect(base .. "/shots/page*.png")),
    join("shots/page2.png", "shots/page10.png"),
    "collect: a glob keeps only its matches"
  )
  H.eq(
    names(set.collect(base .. "/shots/**/*.png")),
    join("shots/Alpha1.PNG", "shots/odd[1].png", "shots/page2.png", "shots/page10.png", "shots/sub/deep.png"),
    "collect: ** recurses"
  )
  H.eq(
    names(set.collect(base .. "/shots/*", { "jpg" })),
    join("shots/cover.jpg"),
    "collect: the extension list is the filter (a glob that matches everything still keeps only images)"
  )
  H.eq(#set.collect(base .. "/shots/*.gif"), 0, "collect: no match is an empty list")

  -- ── export_set ───────────────────────────────────────────────────────────
  local real_to_pdf_multi, real_confirm = convert.to_pdf_multi, set.confirm
  local got, asked, answer = nil, 0, true
  ---@diagnostic disable-next-line: duplicate-set-field
  convert.to_pdf_multi = function(paths, out, _)
    got = { paths = paths, out = out }
    return nil
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  set.confirm = function()
    asked = asked + 1
    return answer
  end
  local config = require("images.config")
  local prev = config.get()
  local ok, err = pcall(function()
    H.ok(images.export(base .. "/shots/page*.png", base .. "/out.pdf"), "export: a glob is started")
    H.eq(names(got.paths), join("shots/page2.png", "shots/page10.png"), "export: the matches, in order, make the PDF")
    H.eq(vim.fs.normalize(got.out), base .. "/out.pdf", "export: --out is the target")
    H.eq(asked, 0, "export: a small set is not asked about")

    got = nil
    H.falsy(images.export(base .. "/shots/*.gif"), "export: no match starts nothing")
    H.eq(got, nil, "export: ...and makes no PDF")

    config.setup({ export = { confirm_over = 2 } })
    got = nil
    answer = false
    H.falsy(images.export(base .. "/shots"), "export: a set above the limit is asked about, and a no stops it")
    H.eq(asked, 1, "export: ...asked once")
    H.eq(got, nil, "export: ...nothing was made")
    answer = true
    H.ok(images.export(base .. "/shots"), "export: a yes goes on")
    H.eq(#got.paths, 5, "export: ...with every image of the directory")
    asked, got = 0, nil
    H.ok(images.export(base .. "/shots", nil, { yes = true }), "export: --yes goes on without asking")
    H.eq(asked, 0, "export: ...and does not ask")
    config.setup({ export = { confirm_over = 0 } })
    asked = 0
    images.export(base .. "/shots")
    H.eq(asked, 0, "export: confirm_over = 0 never asks")
  end)
  convert.to_pdf_multi, set.confirm = real_to_pdf_multi, real_confirm
  config.setup(prev)
  vim.fn.delete(base, "rf")
  if not ok then error(err, 0) end
end
