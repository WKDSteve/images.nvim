-- TESTS/sheets/features.lua -- the functionalities of images.nvim as its user meets them; `testing sheets report` says
-- which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names an
-- id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The entries follow docs/FEATURES/, one per functionality that starts a process (what `testing perf` measures);
-- `perf` says why one has no sheet. The `images.tree-*` entries are the part of docs/FEATURES/INTEGRATIONS.md a tree
-- view shows (the own tree of filetree.nvim).
-- The sheets of the tree run in the real tree: the workflow checks filetree.nvim and ui.nvim out below .deps/
-- (a `requires` skip of a feature sheet is red under CI).
return {
  {
    id = "images.display",
    title = "The image under the cursor, a gallery of the buffer, full-screen zen and a side-by-side compare, drawn "
      .. "by the terminal",
    perf = "manual:the picture itself needs a terminal that draws images (WezTerm, iTerm2); what starts a process "
      .. "around it has its own entries (ascii, remote, info, zen-zoom)",
    docs = "docs/FEATURES/DISPLAY.md",
  },
  {
    id = "images.ascii",
    title = "In a terminal without pictures, :Image shows the image as block characters sampled by ImageMagick",
    surface = { ":Image", "config:display.ascii_fallback" },
    docs = "docs/FEATURES/DISPLAY.md",
  },
  {
    id = "images.remote",
    title = ":Image show <url> downloads a remote picture with curl into a cache and shows it",
    surface = { ":Image show", "config:display.remote" },
    docs = "docs/FEATURES/DISPLAY.md",
  },
  {
    id = "images.info",
    title = ":Image info names the format, the pixel size and the file size of an image (magick identify)",
    surface = { ":Image info" },
    docs = "docs/FEATURES/DISPLAY.md",
  },
  {
    id = "images.zen-zoom",
    title = "+ and - in the zen window show a part of the picture larger, cut out by ImageMagick",
    surface = { ":Image zen", "config:display.zen.keys.zoom_in" },
    docs = "docs/FEATURES/DISPLAY.md",
  },
  {
    id = "images.terminal-probe",
    title = "The setup asks the terminal its name (XTVERSION), under tmux through tmux display-message",
    surface = { ":Image check", "config:display.terminal_probe" },
    docs = "docs/FEATURES/DISPLAY.md",
  },
  {
    id = "images.paste",
    title = ":Image paste saves the clipboard image next to the document and writes the link",
    surface = { ":Image paste", "config:paste" },
    docs = "docs/FEATURES/CAPTURE.md",
  },
  {
    id = "images.screenshot",
    title = ":Image screenshot captures a screen selection (Snipping Tool, screencapture, grim/slurp, maim) and links it",
    surface = { ":Image screenshot", "config:display.screenshot" },
    docs = "docs/FEATURES/CAPTURE.md",
  },
  {
    id = "images.redact",
    title = ":Image redact marks boxes in a zen window and w writes a copy with them burned in",
    surface = { ":Image redact" },
    docs = "docs/FEATURES/CAPTURE.md",
  },
  {
    id = "images.browse",
    title = ":Image pickers lists every image below the working directory (the file helper where built) and shows one",
    surface = { ":Image pickers", ":Image compare" },
    docs = "docs/FEATURES/BROWSING.md",
  },
  {
    id = "images.convert",
    title = ":Image scale, :Image convert and :Image optimise write a copy beside the source through ImageMagick",
    surface = { ":Image scale", ":Image convert", ":Image optimise" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
  {
    id = "images.export",
    title = ":Image export writes an image, or several, as a PDF beside it",
    surface = { ":Image export" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
  {
    id = "images.ocr",
    title = ":Image ocr reads the text of an image into a scratch buffer (tesseract, optionally enlarged by magick)",
    surface = { ":Image ocr" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
  {
    id = "images.tree-orphan-badge",
    title = "In a tree view an image no document links carries a badge, and its folders count such images",
    surface = { "config:tree" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
  {
    id = "images.tree-orphan-roots",
    title = "The search for unreferenced images follows the roots the trees show: two tabs, two projects",
    surface = { "config:tree" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
  {
    id = "images.tree-orphan-rescan",
    title = "The menu of a folder in the tree looks for unreferenced images again and says how many there are",
    surface = { "config:tree.actions", "config:tree.keys.rescan" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
  {
    id = "images.tree-orphan-delete",
    title = "The menu of an unreferenced image in the tree deletes it, through the trash of the tree and its question",
    surface = { "config:tree.actions", "config:tree.keys.delete" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
  {
    id = "images.tree-zen-open",
    title = "<CR> on an image in a tree view opens the zen float: the tree's preview goes, no process starts, one draw",
    surface = { "config:display.zen" },
    docs = "docs/FEATURES/INTEGRATIONS.md",
  },
}
