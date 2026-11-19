-- Feature images.remote (TESTS/sheets/features.lua): with `display.remote.enabled`, `:Image show <url>` downloads the
-- picture with curl (images.remote, asynchronous) into the cache and shows it; a second `:Image show` of the same URL
-- is served from the cache without a download. The real curl fetches from a server inside the child editor on
-- 127.0.0.1 (so `allow_private_hosts`), nothing leaves the machine. The child has no terminal that draws pictures:
-- the bytes for the terminal are counted, not sent.
return {
  id = "images.remote",
  feature = "images.remote",
  title = "images.nvim: :Image show <url> downloads the picture once with curl and shows it, then from the cache",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        _G.desk({ display = { assume_supported = true, remote = { enabled = true, allow_private_hosts = true } } })
        _G.count_pictures()
        _G.serve()]],
      note = "remote images on, a server on 127.0.0.1 that has hello.png",
    },
    { lua = [[vim.cmd("Image show http://127.0.0.1:" .. _G.port .. "/hello.png")]], note = ":Image show <url>" },
    { wait = [[_G.sent > 0 or _G.loud() ~= ""]], timeout = 15000, note = "the picture went to the terminal" },
    { expect = [[_G.eq(_G.loud(), "")]], note = "nothing was said at warning level" },
    { expect = [[_G.eq(_G.requests, { "/hello.png" })]], note = "curl asked the server once for /hello.png" },
    { lua = [[require("images").clear(); _G.sent = 0]], note = "the picture cleared" },
    { lua = [[vim.cmd("Image show http://127.0.0.1:" .. _G.port .. "/hello.png")]], note = "the same URL again" },
    { wait = [[_G.sent > 0 or _G.loud() ~= ""]], timeout = 5000, note = "shown again" },
    { expect = [[_G.eq(#_G.requests, 1)]], note = "from the cache: no second download" },
    { lua = [[vim.cmd("Image show http://127.0.0.1:" .. _G.port .. "/missing.png")]], note = "a URL the server lacks" },
    { wait = [[_G.loud() ~= ""]], timeout = 15000, note = "the failure is said" },
    { expect = [[_G.loud():find("download failed", 1, true) ~= nil]], note = "as a failed download" },
  },
  manual = {
    "Once with the real network in WezTerm: :Image show on an https image URL shows the picture",
  },
}
