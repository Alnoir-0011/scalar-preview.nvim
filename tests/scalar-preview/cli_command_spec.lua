local stub = require("tests.helpers.stub")

describe("cli command construction", function()
  local sp, jobs, notifications, file_a

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs, notifications = stub.install()
    file_a = stub.tempfile("a.yaml")
  end)

  after_each(function()
    stub.restore()
  end)

  it("runs the command as a list, not a shell string", function()
    sp.setup({ port = 8000 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal("table", type(jobs.started[1].cmd))
  end)

  it("defaults to @scalar/cli@latest and passes port/watch", function()
    sp.setup({ port = 8123 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.same({
      "npx",
      "--yes",
      "@scalar/cli@latest",
      "document",
      "serve",
      "./a.yaml",
      "-w",
      "-p",
      "8123",
    }, jobs.started[1].cmd)
  end)

  it("pins the @scalar/cli version when cli_version is configured", function()
    sp.setup({ port = 8000, cli_version = "2.8.0" })
    vim.cmd.edit(file_a)

    sp.start()

    assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "@scalar/cli@2.8.0"))
    assert.falsy(vim.tbl_contains(jobs.started[1].cmd, "@scalar/cli@latest"))
  end)

  it("appends -c <path> when config is set to a readable file", function()
    local config_file = stub.tempfile("scalar.config.json")
    sp.setup({ port = 8000, config = config_file })
    vim.cmd.edit(file_a)

    sp.start()

    local cmd = jobs.started[1].cmd
    local c_index
    for i, arg in ipairs(cmd) do
      if arg == "-c" then
        c_index = i
      end
    end
    assert.truthy(c_index)
    assert.are.equal(config_file, cmd[c_index + 1])
  end)

  it("does not pass -c at all when config is unset", function()
    sp.setup({ port = 8000 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.falsy(vim.tbl_contains(jobs.started[1].cmd, "-c"))
  end)

  it("refuses to start when config points at an unreadable file", function()
    sp.setup({ port = 8000, config = vim.fn.fnamemodify(file_a, ":h") .. "/no-such-config.json" })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(0, #jobs.started)
    local errors = stub.errors(notifications)
    assert.are.equal(1, #errors)
    -- Regression test: M.config's own field is also named "config", and the refusal message
    -- once leaked that internal path as the literal text "config.config file is not
    -- readable", which is meaningless to a user who only ever wrote `config = "..."`.
    assert.truthy(errors[1].msg:match("^ScalarPreview: config file is not readable"))
    assert.falsy(errors[1].msg:match("config%.config"))
  end)

  -- Regression test for the config path being checked against Neovim's cwd but, before this
  -- fix, passed to the CLI as the same relative string while the job itself runs with a
  -- *different* cwd (the previewed file's directory) -- so a relative `config` could pass
  -- the readability check here yet have the CLI look for it in the wrong directory.
  it("resolves a relative config path once, to an absolute path, for both the check and the argv", function()
    local config_file = stub.tempfile("scalar.config.json")
    local tempdir = vim.fn.fnamemodify(config_file, ":h")
    local previous_cwd = vim.fn.getcwd()
    vim.cmd.cd(tempdir) -- Neovim's cwd now matches the file's own dir, as in the bug report
    local relative_name = vim.fn.fnamemodify(config_file, ":t")

    sp.setup({ port = 8000, config = relative_name })
    vim.cmd.edit(file_a) -- a.yaml lives in the *same* tempdir as config_file here

    local ok = pcall(sp.start)
    vim.cmd.cd(previous_cwd)
    assert.is_true(ok)

    assert.are.equal(1, #jobs.started)
    assert.are.equal(0, #stub.errors(notifications))
    local cmd = jobs.started[1].cmd
    local c_index
    for i, arg in ipairs(cmd) do
      if arg == "-c" then
        c_index = i
      end
    end
    assert.truthy(c_index)
    -- Compare against config_file's canonical realpath (rather than the raw tempfile path):
    -- the `vim.cmd.cd()` above makes Neovim's own cwd canonical too (on macOS, resolving
    -- /var -> /private/var), and resolving `relative_name` against that cwd picks up the
    -- same canonicalization, so the raw, pre-`:cd` tempfile path would no longer match.
    assert.are.equal((vim.uv or vim.loop).fs_realpath(config_file), cmd[c_index + 1])
  end)

  it("prefixes a basename starting with '-' with './' so it isn't parsed as a flag", function()
    local dashed = stub.tempfile("-dashed.yaml")
    sp.setup({ port = 8000 })
    vim.cmd.edit(dashed)

    sp.start()

    assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "./-dashed.yaml"))
  end)

  -- The whole point of switching from a shell string to a list {cmd} is that no shell ever
  -- sees these arguments, so characters that would otherwise need quoting/escaping for a
  -- POSIX shell reach the process completely unchanged, as a single argv element each.
  it("passes a filename containing shell metacharacters through as a single unescaped argv element", function()
    local tricky = stub.tempfile("a b;rm -rf ~ $(whoami).yaml")
    sp.setup({ port = 8000 })
    vim.cmd.edit(tricky)

    sp.start()

    assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "./a b;rm -rf ~ $(whoami).yaml"))
  end)

  describe("on Windows", function()
    local original_has

    before_each(function()
      original_has = vim.fn.has
      vim.fn.has = function(feature)
        if feature == "win32" then
          return 1
        end
        return original_has(feature)
      end
    end)

    after_each(function()
      vim.fn.has = original_has
    end)

    it("refuses a file name containing a cmd.exe metacharacter", function()
      local dangerous = stub.tempfile("openapi&calc.exe&.yaml")
      sp.setup({ port = 8000 })
      vim.cmd.edit(dangerous)

      sp.start()

      assert.are.equal(0, #jobs.started)
      assert.are.equal(1, #stub.errors(notifications))
    end)

    it("still starts normally for a file name with no cmd.exe metacharacters", function()
      sp.setup({ port = 8000 })
      vim.cmd.edit(file_a)

      sp.start()

      assert.are.equal(1, #jobs.started)
      assert.are.equal(0, #stub.errors(notifications))
    end)
  end)
end)
