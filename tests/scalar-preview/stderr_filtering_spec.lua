local stub = require("tests.helpers.stub")

describe("stderr filtering", function()
  local sp, jobs, notifications, file_a

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs, notifications = stub.install()
    file_a = stub.tempfile("a.yaml")
    vim.cmd.edit(file_a)
    sp.start()
  end)

  after_each(function()
    stub.restore()
  end)

  -- Per :help channel-lines, every element but the last in a single on_stderr call is a
  -- confirmed-complete line; the last one is only confirmed once an explicit "" follows it
  -- (in the same call or a later one) or the stream reaches EOF (a lone {""}). These tests
  -- append a trailing "" to each call to mark the preceding line(s) complete, matching real
  -- Neovim behavior instead of asserting on a still-pending partial line.

  it("does not warn on npm's own warnings (EBADENGINE, deprecated, ...)", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, {
      "npm warn EBADENGINE Unsupported engine {",
      "npm warn EBADENGINE   package: 'nanoid@6.0.1',",
      "npm warn deprecated inflight@1.0.6: this module is not supported",
      "",
    })

    assert.are.same({}, stub.warnings(notifications))
  end)

  it("still warns once on real warnings from @scalar/cli", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "npm warn EBADENGINE ...", "" })
    job.opts.on_stderr(job.id, { "[WARN] Could not find any paths in the OpenAPI file.", "" })
    job.opts.on_stderr(job.id, { "another real warning line", "" })

    assert.are.equal(1, #stub.warnings(notifications))
  end)

  it("still warns on an npm warning that isn't a known-noisy one (e.g. a corrupted tarball)", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "npm warn tarball tarball data for @scalar/cli@2.8.0 seems to be corrupted", "" })

    assert.are.equal(1, #stub.warnings(notifications))
  end)

  it("ignores lines that are purely cursor-visibility ANSI codes", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "\27[?25l", "\27[?25h", "" })

    assert.are.same({}, stub.warnings(notifications))
  end)

  it("does not warn on npm's own warnings even when npm colors them (npmrc color=always)", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "\27[33mnpm\27[39m warn EBADENGINE Unsupported engine {", "" })

    assert.are.same({}, stub.warnings(notifications))
  end)

  it("still warns on a real warning wrapped in color codes", function()
    local job = jobs.started[1]

    job.opts.on_stderr(
      job.id,
      { "\27[33m\27[1m[WARN] Could not find any paths in the OpenAPI file.\27[22m\27[39m", "" }
    )

    assert.are.equal(1, #stub.warnings(notifications))
  end)

  it("strips colon-separated true-color SGR codes and OSC sequences before matching", function()
    local job = jobs.started[1]

    -- 24-bit SGR (ESC[38:2:255:0:0m ... ESC[0m) and an OSC 8 hyperlink wrapper
    -- (ESC]8;;URL BEL ... ESC]8;; BEL), as some terminals/npm configs emit.
    job.opts.on_stderr(job.id, {
      "\27[38:2:255:0:0mnpm\27[0m warn EBADENGINE Unsupported engine {",
      "\27]8;;http://example.com\7npm\27]8;;\7 warn deprecated some-pkg@1.0.0: old",
      "",
    })

    assert.are.same({}, stub.warnings(notifications))
  end)

  it("reassembles a line split across multiple on_stderr calls before matching it", function()
    local job = jobs.started[1]

    -- "npm warn EBADENGINE ..." arriving in two chunks, as a raw byte stream might deliver it.
    job.opts.on_stderr(job.id, { "npm wa" })
    job.opts.on_stderr(job.id, { "rn EBADENGINE Unsupported engine {", "" })

    assert.are.same({}, stub.warnings(notifications))
  end)

  it("reassembles a split line and still warns if the complete line is a real warning", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "[WARN] Could not find any pat" })
    job.opts.on_stderr(job.id, { "hs in the OpenAPI file.", "" })

    assert.are.equal(1, #stub.warnings(notifications))
  end)

  it("flushes a still-pending line on EOF (a lone empty string) even with no trailing newline", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "npm warn EBADENGINE Unsupported engine {" })
    job.opts.on_stderr(job.id, { "" }) -- EOF for this stream

    assert.are.same({}, stub.warnings(notifications))
  end)

  it("ignores stderr from a stale job after a restart, without affecting the new job's state", function()
    local file_b = stub.tempfile("b.yaml")
    local job_a = jobs.started[1]

    vim.cmd.edit(file_b)
    sp.start() -- restarts: stops job A, starts job B
    local job_b = jobs.started[2]

    -- Job A's lingering stderr arrives late (jobstop() only sends SIGTERM; it doesn't
    -- guarantee the old process's stdio closes before the new one's output starts).
    job_a.opts.on_stderr(job_a.id, { "a real warning from the old job", "" })

    assert.are.same({}, stub.warnings(notifications))
    assert.is_false(sp.warned)

    -- The new job's own stderr is still processed normally afterwards.
    job_b.opts.on_stderr(job_b.id, { "a real warning from the new job", "" })

    assert.are.equal(1, #stub.warnings(notifications))
  end)
end)
