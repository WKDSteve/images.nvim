-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "images",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  -- TESTS/sheets_spec.lua is busted style: one case per test sheet (`sheet:<id>`, testing sheets report).
  dialect = { ["TESTS/sheets_spec.lua"] = "busted", ["*"] = "h" },
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "testing.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next). "file" because setup() of the plugin and the
  -- specs leave autocmds, user commands and highlight groups behind (state guard).
  isolated = "file",
  -- Safety nets, all clean on this suite, so all fail the case.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
  },
  guard_allow = {
    spawn = {
      -- The plugin shells out to ImageMagick (convert, crop, scale, identify) and the specs run it for real.
      "magick",
      -- ocr_spec.lua runs the real tesseract binary (the specs skip when it is absent).
      "tesseract",
      -- proc_spec.lua starts the running Neovim as the stand-in for a process that hangs and one that exits 0;
      -- sheets_spec.lua starts a child editor per test sheet (TESTS/sheets/).
      "nvim",
      -- ps_path_spec.lua runs one real powershell.exe (skipped where absent) to prove a hostile path stays inside its string.
      "powershell",
      -- ...and under WSL first asks wslpath for the Windows form of the temp path that powershell.exe can open.
      "wslpath",
      -- pty_osc1337_spec.lua drives a real Neovim in tmux (WSL on Windows) to read the OSC 1337 bytes back.
      "wsl",
      "tmux",
      -- testing.pty reads the bytes the terminal got back through `cat` on Linux and macOS.
      "cat",
      -- browse_spec.lua: the file helper of filetree.nvim lists the images (lib.nvim.fs.fast), where a program is
      -- built next to this repository; a helper that ends hands the listing to fd.
      "filetree-helper",
      "fd",
      "fdfind",
    },
  },
  -- ps_path_spec.lua makes two real powershell.exe round trips and lets each take up to 120 s
  -- (PS_TIMEOUT_MS, images.nvim@f589a8e): a cold start on windows-latest took 36 s in a green run
  -- and just over 60 s in two red ones on 2026-10-20. The file limit has to be above what the spec
  -- itself allows, or the runner kills a slow but healthy file; it still catches a real hang.
  -- case_ms: a test sheet is one case that boots a child editor with the real tree of filetree.nvim and waits for
  -- scans in the background; under load that takes longer than the default 10 s.
  timeouts = { case_ms = 60000, file_ms = 300000 },
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  -- UI_NVIM_DIR, FILETREE_NVIM_DIR: how ui.nvim and filetree.nvim reach the test sheets from the worktree of
  -- `ci commit`, where they are no siblings (TESTS/minimal_init.lua names them, TESTS/sheets/_helpers.lua adds them).
  env_allow = { "MAGICK_*", "UI_NVIM_DIR", "FILETREE_NVIM_DIR", "LIB_FS_HELPER_TEST" },
  -- Findings the minimal conformance editor cannot avoid (docs/CONFORMANCE.md of testing.nvim); reviewed 2026-10-14.
  conformance = {
    -- gated: a failed check makes `scripts/test.sh conformance` exit 1
    gate = true,
    waivers = {
      {
        check = "K6",
        level = "warn",
        text = "terminal not recognised",
        reason = "the minimal headless editor has no graphics-capable terminal (TERM_PROGRAM empty); the health check is right to warn about it, only the environment lacks one",
        expires = "2027-04-14",
      },
      {
        check = "K1",
        file = "lua/images/integrations/menu.lua",
        reason = "a deliberate hard dependency on ui.contextmenu (TESTS/menu_spec.lua header): only a host that builds a ui.nvim menu loads it, and ui.nvim must stay off the suite's runtimepath for compare_spec.lua",
        expires = "2027-04-14",
      },
    },
  },
  ci = {
    -- The GitHub workflow, generated: `testing init --workflow=public --force` writes .github/workflows/ci.yml from
    -- this (testing.nvim docs/WORKFLOW-CI.md); the step workflow-in-sync keeps the two together.
    workflow = {
      name = "images.nvim",
      layout = "hosted",
      -- the steps that depend on the platform: the windows and macOS legs run only these
      platform = { "suite", "conformance" },
      -- `testing ci land`: a check branch ci/** runs the hosted legs, main moves to a commit only once it is green there
      land = true,
      -- more checkouts below .deps/, not on the runtimepath of the specs (TESTS/minimal_init.lua finds them there)
      checkouts = {
        {
          repo = "WKDSteve/ui.nvim",
          ref = "ci-verified",
          why = "only the test sheets load it (TESTS/sheets/): compare_spec.lua needs ui.kit off the runtimepath",
        },
        {
          repo = "WKDSteve/filetree.nvim",
          ref = "ci-verified",
          why = "only the test sheets load it: the badge and the actions in the real tree of filetree.nvim",
        },
        {
          repo = "WKDSteve/docmap.nvim",
          ref = "ci-verified",
          why = "the step map runs docmap's generator (scripts/gen_map.lua finds it in .deps/)",
        },
      },
      packages = {
        {
          -- choco has no tmux; on Windows the pty specs run through WSL, which the hosted runner lacks (n/a there)
          name = "tmux",
          choco = false,
          why = "TESTS/pty_osc1337_spec.lua drives a real Neovim in tmux on the Linux and macOS legs",
        },
      },
    },
    steps = {
      ["workflow-in-sync"] = { preset = "workflow-in-sync" },
      -- the layer rules of scripts/gen_map.lua: its exit code is the gate. Not --check: docs/map/ is in .gitignore,
      -- so a fresh checkout has no map to compare against. The worktree of `ci commit` has neither .deps/ nor
      -- siblings: env names the two checkouts the generator probes for.
      map = {
        run = { "nvim", "-n", "-i", "NONE", "--headless", "-l", "scripts/gen_map.lua" },
        env = { LIB_NVIM_DIR = "${deps.lib.nvim}", DOCMAP_NVIM_DIR = "${deps.docmap.nvim}" },
      },
    },
  },
}
