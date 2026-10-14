local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local preload_url = vim.uri_from_fname(root .. "/scripts/bind-loopback.mjs")

local node_it = vim.fn.executable("node") == 1 and it or pending

-- Returns the child's exit code, stdout and stderr. Ports are always 0 so concurrent runs
-- (or a developer's own running preview) can't collide with these.
local function run_node(code, env)
  local result = vim
    .system({ "node", "--import=" .. preload_url, "-e", code }, { env = env, text = true, timeout = 10000 })
    :wait()
  return result.code, vim.trim(result.stdout), result.stderr
end

local function print_bound_address(listen_args)
  return string.format(
    [[const s = require("http").createServer(); s.listen(%s, () => { console.log(s.address().address); s.close(); });]],
    listen_args
  )
end

describe("bind preload", function()
  node_it("binds a listen(port) that names no host to the bind address", function()
    local code, stdout = run_node(print_bound_address("0"), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" })

    assert.are.equal(0, code)
    assert.are.equal("127.0.0.1", stdout)
  end)

  node_it("replaces an explicit all-interfaces host with the bind address", function()
    for _, wildcard in ipairs({ '0, "0.0.0.0"', '0, "::"' }) do
      local code, stdout = run_node(print_bound_address(wildcard), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" })

      assert.are.equal(0, code, wildcard)
      assert.are.equal("127.0.0.1", stdout, wildcard)
    end
  end)

  node_it("applies the bind address to the options-object form of listen()", function()
    for _, options in ipairs({ "{ port: 0 }", '{ port: 0, host: "0.0.0.0" }' }) do
      local code, stdout = run_node(print_bound_address(options), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" })

      assert.are.equal(0, code, options)
      assert.are.equal("127.0.0.1", stdout, options)
    end
  end)

  node_it("leaves a unix socket path alone", function()
    local socket_path = vim.fn.tempname()
    local code = run_node(
      string.format(
        [[const s = require("net").createServer(); s.listen(%q, () => { s.close(); console.log("ok"); });]],
        socket_path
      ),
      { SCALAR_PREVIEW_BIND_HOST = "127.0.0.1" }
    )

    assert.are.equal(0, code)
  end)

  node_it("stops with a message when the server ends up on an address other than the bind address", function()
    local code, _, stderr = run_node(print_bound_address('0, "127.0.0.1"'), { SCALAR_PREVIEW_BIND_HOST = "127.0.0.2" })

    assert.are.equal(1, code)
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
end)
