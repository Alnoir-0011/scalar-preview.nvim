local tools = require("tests.helpers.tools")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local preload_url = vim.uri_from_fname(root .. "/scripts/bind-loopback.mjs")

local is_unix = vim.fn.has("win32") == 0
local node_it = tools.it_requiring("node", tools.executable("node"))
local unix_it = tools.it_requiring("node on a unix-like system", tools.executable("node") and is_unix)

-- A variable from the developer's own shell must not leak into a spec, and the "not set"
-- spec needs one genuinely absent. `env -u` removes them without clearing the rest, which a
-- version manager's `node` shim still depends on. The variables a spec sets go on `env`'s
-- own command line, after the `-u`s, because they would otherwise be removed along with them.
local function node_command(code, variables)
  local command = { "node", "--import=" .. preload_url, "-e", code }
  if not tools.executable("env") then
    return command, variables
  end
  local prefix = { "env", "-u", "SCALAR_PREVIEW_BIND_HOST", "-u", "NODE_OPTIONS" }
  for name, value in pairs(variables) do
    table.insert(prefix, name .. "=" .. value)
  end
  return vim.list_extend(prefix, command), nil
end

-- Returns the child's exit code, stdout and stderr. Ports are always 0 so concurrent runs
-- (or a developer's own running preview) can't collide with these.
local function run_node(code, variables)
  local command, env = node_command(code, variables)
  local result = vim.system(command, { env = env, text = true, timeout = 10000 }):wait()
  return result.code, vim.trim(result.stdout), result.stderr
end

local function last_line(stdout)
  local lines = vim.split(stdout, "\n", { plain = true })
  return lines[#lines]
end

local function print_bound_address(listen_args)
  return string.format(
    [[const s = require("http").createServer(); s.listen(%s, () => { console.log(s.address().address); s.close(); });]],
    listen_args
  )
end

local ipv6_loopback_available = tools.executable("node")
  and vim
      .system({
        "node",
        "-e",
        [[require("net").createServer().listen(0, "::1", function () { console.log("yes"); this.close(); }).on("error", () => console.log("no"));]],
      }, { text = true, timeout = 10000 })
      :wait().stdout
      :find("yes", 1, true)
    ~= nil
local ipv6_it = tools.it_requiring("an IPv6 loopback", ipv6_loopback_available)

describe("bind preload", function()
  node_it("binds a listen(port) that names no host to the bind address", function()
    local code, stdout = run_node(print_bound_address("0"), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" })

    assert.are.equal(0, code)
    assert.are.equal("127.0.0.1", last_line(stdout))
  end)

  node_it("replaces an explicit all-interfaces host with the bind address", function()
    for _, wildcard in ipairs({ '0, "0.0.0.0"', '0, "::"' }) do
      local code, stdout = run_node(print_bound_address(wildcard), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" })

      assert.are.equal(0, code, wildcard)
      assert.are.equal("127.0.0.1", last_line(stdout), wildcard)
    end
  end)

  node_it("applies the bind address to the options-object form of listen()", function()
    for _, options in ipairs({ "{ port: 0 }", '{ port: 0, host: "0.0.0.0" }' }) do
      local code, stdout = run_node(print_bound_address(options), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" })

      assert.are.equal(0, code, options)
      assert.are.equal("127.0.0.1", last_line(stdout), options)
    end
  end)

  -- Each of these names no real host, so node would bind every interface. The post-bind
  -- check alone would stop them; rewriting them keeps the preview working.
  for _, arguments in ipairs({
    "0, 511",
    "0, null",
    '0, ""',
    "0, undefined, 511",
    '0, "::0"',
    '0, "0:0:0:0:0:0:0:0"',
    '{ port: 0, host: "" }',
    "{ port: 0, host: null }",
  }) do
    node_it("binds listen(" .. arguments .. ") to the bind address too", function()
      local code, stdout = run_node(print_bound_address(arguments), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" })

      assert.are.equal(0, code)
      assert.are.equal("127.0.0.1", last_line(stdout))
    end)
  end

  unix_it("leaves a unix socket path alone", function()
    -- Not vim.fn.tempname(): on macOS that lives under /var/folders/... and a socket path
    -- longer than about 104 bytes makes listen() fail with EINVAL, which would hide the
    -- behavior under test.
    local socket_path = "/tmp/scalar-preview-spec-" .. vim.uv.hrtime() .. ".sock"
    local code, stdout = run_node(
      string.format(
        [[const s = require("net").createServer(); s.listen(%q, () => { s.close(); console.log("ok"); });]],
        socket_path
      ),
      { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" }
    )

    assert.are.equal(0, code)
    assert.are.equal("ok", stdout)
  end)

  node_it("accepts a bind address that is itself all-interfaces", function()
    local code, stdout = run_node(print_bound_address("0"), { SCALAR_PREVIEW_BIND_HOST = "0.0.0.0" })

    assert.are.equal(0, code)
    assert.are.equal("0.0.0.0", last_line(stdout))
  end)

  ipv6_it("binds to an IPv6 bind address and compares it in its canonical form", function()
    for _, spelling in ipairs({ "::1", "0:0:0:0:0:0:0:1" }) do
      local code, stdout = run_node(print_bound_address('0, "::"'), { SCALAR_PREVIEW_BIND_HOST = spelling })

      assert.are.equal(0, code, spelling)
      assert.are.equal("::1", last_line(stdout), spelling)
    end
  end)

  node_it("stops a listen() it cannot recognize instead of leaving it on every interface", function()
    local code, stdout, stderr = run_node(
      [[const s = require("http").createServer(); s.listen(() => { console.log("callback"); s.close(); });]],
      { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" }
    )

    assert.are.equal(1, code)
    assert.are.equal("", stdout)
    assert.truthy(stderr:find("scalar-preview:", 1, true))
  end)

  node_it("stops with a message when the server ends up on an address other than the bind address", function()
    local code, stdout, stderr =
      run_node(print_bound_address('0, "127.0.0.1"'), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.2" })

    assert.are.equal(1, code)
    assert.are.equal("", stdout)
    assert.truthy(stderr:find("scalar-preview:", 1, true))
  end)

  node_it("stops with a message when SCALAR_PREVIEW_BIND_HOST is not set", function()
    local code, _, stderr = run_node(print_bound_address("0"), {})

    assert.are.equal(1, code)
    assert.truthy(stderr:find("scalar-preview:", 1, true))
  end)

  node_it("stops with a message when SCALAR_PREVIEW_BIND_HOST is not an IP address", function()
    local code, _, stderr = run_node(print_bound_address("0"), { SCALAR_PREVIEW_BIND_HOST = "localhost" })

    assert.are.equal(1, code)
    assert.truthy(stderr:find("scalar-preview:", 1, true))
  end)

  node_it("announces the address it bound, before any other listening handler runs", function()
    local code, stdout = run_node(
      [[const s = require("http").createServer();
        s.on("listening", () => console.log("earlier-handler"));
        s.listen(0, () => { console.log("callback"); s.close(); });]],
      { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" }
    )

    assert.are.equal(0, code)
    local lines = vim.split(stdout, "\n", { plain = true })
    assert.truthy(lines[1]:match("^scalar%-preview: bound 127%.0%.0%.1:%d+$"))
    assert.are.equal("earlier-handler", lines[2])
    assert.are.equal("callback", lines[3])
  end)

  ipv6_it("writes an IPv6 address in brackets so the port stays readable", function()
    local code, stdout = run_node(
      [[const s = require("http").createServer(); s.listen(0, () => s.close());]],
      { SCALAR_PREVIEW_BIND_HOST = "::1" }
    )

    assert.are.equal(0, code)
    assert.truthy(stdout:match("^scalar%-preview: bound %[::1%]:%d+$"))
  end)
end)
