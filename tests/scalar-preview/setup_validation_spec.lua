local stub = require("tests.helpers.stub")

describe("setup() validation", function()
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

  -- Regression test: before cli_version was validated, concatenating a non-string into
  -- "@scalar/cli@" .. cli_version raised an *unprotected* Lua error (it's string concat, not
  -- jobstart, so the pcall around jobstart never saw it) -- and only after M.stop() had
  -- already torn down whatever was previously running and truncated the log.
  it("rejects a non-string cli_version instead of letting it reach string concatenation", function()
    sp.setup({ port = 8000, cli_version = false })
    vim.cmd.edit(file_a)

    local ok = pcall(sp.start)

    assert.is_true(ok)
    assert.are.equal(1, #jobs.started) -- falls back to the default ("latest"), still starts
    assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "@scalar/cli@latest"))
    assert.are.equal(1, #stub.errors(notifications)) -- but setup() did complain
  end)

  it("rejects a cli_version written as a non-version package-arg (npm:, github:, file:, a URL)", function()
    for _, bad in ipairs({ "npm:left-pad@1.0.0", "github:user/repo", "file:../evil", "https://example.com/x.tgz" }) do
      package.loaded["scalar-preview"] = nil
      sp = require("scalar-preview")
      jobs, notifications = stub.install()

      sp.setup({ port = 8000, cli_version = bad })
      vim.cmd.edit(file_a)
      sp.start()

      assert.are.equal(1, #jobs.started)
      assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "@scalar/cli@latest"), bad .. " should fall back to latest")
      assert.are.equal(1, #stub.errors(notifications), bad .. " should be rejected")

      stub.restore()
    end
  end)

  it("accepts ordinary version strings and dist-tags for cli_version", function()
    for _, good in ipairs({ "2.8.0", "latest", "next", "1.2.3-beta.1" }) do
      package.loaded["scalar-preview"] = nil
      sp = require("scalar-preview")
      jobs, notifications = stub.install()

      sp.setup({ port = 8000, cli_version = good })
      vim.cmd.edit(file_a)
      sp.start()

      assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "@scalar/cli@" .. good), good .. " should be accepted as-is")
      assert.are.equal(0, #stub.errors(notifications), good .. " should not be rejected")

      stub.restore()
    end
  end)

  it("rejects a non-number port and falls back to the default", function()
    sp.setup({ port = "8000" })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(1, #jobs.started)
    assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "8000")) -- default port, as a string arg
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("rejects a non-string host and falls back to the default", function()
    sp.setup({ host = 123 })

    assert.are.equal("localhost", sp.config.host)
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("rejects a non-string config and falls back to unset", function()
    sp.setup({ config = 123 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(1, #jobs.started)
    assert.falsy(vim.tbl_contains(jobs.started[1].cmd, "-c"))
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("keeps the rest of an otherwise-valid setup() call when only one field is invalid", function()
    sp.setup({ port = 9000, cli_version = false })

    assert.are.equal(9000, sp.config.port)
    assert.are.equal("latest", sp.config.cli_version) -- unaffected by the bad port
  end)

  -- Regression test: validate() originally wrote `opts[key] = nil` back into the caller's
  -- own table to drop an invalid field before merging. Harmless today (setup() doesn't reuse
  -- its argument afterwards), but mutating a table the caller still owns is a footgun for
  -- whoever touches this next -- e.g. a caller that builds `opts` once and passes it to
  -- setup() more than once, or inspects it afterwards, would see the field vanish.
  it("does not mutate the opts table passed in, even for an invalid field", function()
    local opts = { port = 9000, cli_version = false }

    sp.setup(opts)

    assert.are.equal(false, opts.cli_version)
    assert.are.equal(9000, opts.port)
  end)
end)
