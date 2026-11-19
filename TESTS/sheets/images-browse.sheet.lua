-- Feature images.browse (TESTS/sheets/features.lua): `:Image pickers cwd` lists every image below the working
-- directory and shows the one picked. Where filetree.nvim's file helper is built (a program beside the repository,
-- or $LIB_FS_HELPER_TEST) the listing runs in that program (lib.nvim.fs.fast, the start `testing perf` measures);
-- without it (the CI) images.browse walks the tree itself, with the same list. The picker is the plain
-- `vim.ui.select` (no snacks.nvim, no ui.nvim here), answered by the sheet like a person choosing an entry; the
-- child has no terminal that draws pictures, so the bytes for the terminal are counted.
return {
  id = "images.browse",
  feature = "images.browse",
  title = "images.nvim: :Image pickers cwd lists the images below the working directory and shows the one picked",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        local helper = require("lib.nvim.fs.helper")
        local program = vim.env.LIB_FS_HELPER_TEST
        local filetree = (vim.g.images_sheets_deps or {})["filetree.nvim"]
        if (not program or program == "") and type(filetree) == "string" then
          program = filetree .. "/helper/target/release/" .. helper.binary_name()
        end
        _G.helper_used = program ~= nil and vim.fn.executable(program) == 1
        helper.configure(_G.helper_used and program or false)
        _G.desk({ display = { assume_supported = true } })
        _G.write(_G.desk_root, "deep/er/inside.jpg", { "not really a jpeg" })
        _G.write(_G.desk_root, "node_modules/pkg/logo.png")
        _G.count_pictures()
        _G.offered = nil
        vim.ui.select = function(items, opts, on_choice)
          _G.offered = vim.tbl_map(opts.format_item or tostring, items)
          for _, item in ipairs(items) do
            if item:find("hello.png", 1, true) then return on_choice(item) end
          end
          on_choice(nil)
        end]],
      note = "a project with images in three folders (one excluded), the file helper where it is built",
    },
    { keys = ":Image pickers cwd<CR>", note = ":Image pickers cwd" },
    { wait = [[_G.offered ~= nil or _G.loud() ~= ""]], timeout = 15000, note = "the picker is offered" },
    {
      expect = [[_G.eq(_G.offered, { "assets/hello.png", "assets/photo.png", "deep/er/inside.jpg" })]],
      note = "the three images, node_modules left out",
    },
    { wait = [[_G.sent > 0 or _G.loud() ~= ""]], timeout = 5000, note = "the picked one is shown" },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
    { lua = [[require("lib.nvim.fs.helper").stop()]], note = "the file helper ends with the editor" },
  },
  manual = {
    "With snacks.nvim installed: :Image pickers shows the live preview of each image while moving through the list",
  },
}
