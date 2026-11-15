-- TESTS/sheets/features.lua -- the functionalities of images.nvim as its user meets them; `testing sheets report` says
-- which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that names an
-- id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The four groups follow docs/scope.md and docs/FEATURES/; the `images.tree-*` entries are the part of
-- docs/FEATURES/INTEGRATIONS.md a tree view shows (the own tree of filetree.nvim).
-- The sheets of the tree run in the real tree: the workflow checks filetree.nvim and ui.nvim out below .deps/
-- (a `requires` skip of a feature sheet is red under CI).
return {
  {
    id = "images.display",
    title = "The image under the cursor, a gallery of the buffer, full-screen zen and a side-by-side compare",
    docs = "docs/FEATURES/DISPLAY.md",
  },
  {
    id = "images.capture",
    title = "Paste from the clipboard into a file next to the document with the link written, screenshot, redaction",
    docs = "docs/FEATURES/CAPTURE.md",
  },
  {
    id = "images.browsing",
    title = "Walk the images of a buffer, find the ones nothing links, browse every image below the working directory",
    docs = "docs/FEATURES/BROWSING.md",
  },
  {
    id = "images.processing",
    title = "OCR, scale, optimise and convert, each as a copy beside the source",
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
}
