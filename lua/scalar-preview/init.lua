local M = {}

M.config = {
  port = 8000,
  host = "localhost",
  cli_version = "latest", -- @scalar/cli version/dist-tag to run, e.g. "2.8.0" to pin it
  config = nil, -- path to a JSON file with API Reference configuration (CLI's `-c`/`--config`)
}

M.job_id = nil
M.stopped_jobs = {}
M.file_being_previewed = nil
M.log_path = vim.fn.stdpath("state") .. "/scalar-preview.log"
M.warned = false
M.stderr_tail = ""

-- Reads `opts[key]` (the caller's partial table) without writing back to it -- `opts` isn't
-- ours to mutate, and a future caller that reuses its own table across setup() calls would
-- otherwise see fields silently disappear. Returns the value to actually use: the original
-- if valid or absent, or nil (meaning "leave M.config's current value alone") if invalid.
local function validate(opts, key, is_valid, expected_description)
  local value = opts[key]
  if value == nil or is_valid(value) then
    return value
  end
  vim.notify(
    string.format(
      "ScalarPreview: ignoring invalid config.%s (expected %s, got %s)",
      key,
      expected_description,
      vim.inspect(value)
    ),
    vim.log.levels.ERROR
  )
  return nil
end

function M.setup(opts)
  opts = opts or {}
  -- Each of these is either the caller's own (valid) value or nil -- never written into
  -- `opts` itself -- so assigning it as a table field below either carries it through to the
  -- vim.tbl_deep_extend() or, for nil, simply never sets that field at all, leaving M.config's
  -- existing value for it untouched either way.
  local sanitized = {
    port = validate(opts, "port", function(v)
      return type(v) == "number"
    end, "a number"),
    host = validate(opts, "host", function(v)
      return type(v) == "string"
    end, "a string"),
    -- Anchored to exclude ":" and "/", which would otherwise let this be interpreted not as a
    -- version/dist-tag but as an entirely different package-arg form (`npm:other-pkg@1.0.0`,
    -- `github:user/repo`, `file:../elsewhere`, `https://...`) when concatenated after
    -- "@scalar/cli@" -- confirmed against npm's own npm-package-arg parser.
    cli_version = validate(opts, "cli_version", function(v)
      return type(v) == "string" and v:match("^[%w][%w%.%+%-]*$") ~= nil
    end, 'a version or dist-tag string (e.g. "2.8.0" or "latest"), not a package-arg like "npm:..."/"github:..."/a URL'),
    config = validate(opts, "config", function(v)
      return type(v) == "string"
    end, "a string (a path) or nil"),
  }

  M.config = vim.tbl_deep_extend("force", M.config, sanitized)
end

-- On Windows, `npx` resolves to `npx.cmd`, a batch file, and CreateProcess implicitly runs
-- .cmd/.bat through cmd.exe -- whose argument-splitting and metacharacter rules differ from
-- the CommandLineToArgvW-style quoting jobstart's list {cmd} applies (see the Windows note
-- under :help jobstart()). `&`, `|`, `^`, `%`, `(`, `)`, `!`, `<`, `>`, `"` are cmd.exe syntax
-- that quoting doesn't neutralize, and all of them are valid in a Windows path, so a
-- previewed file or a configured `config` path with one -- e.g. a file from an untrusted
-- cloned repo -- could run an arbitrary command the moment :ScalarPreview starts. This
-- couldn't happen with the previous shellescape()-based string {cmd}, which quoted
-- specifically for cmd.exe, so refuse rather than risk it. Used for both the previewed
-- file's basename and the resolved `config` path, since both reach argv the same way.
local function has_cmd_exe_metachar(s)
  return vim.fn.has("win32") == 1 and s:match('[&|%^%%%(%)!<>"]') ~= nil
end

-- If a guard below refuses to (re)start, say so plainly, and if a previous preview is still
-- running say that too: refusing doesn't stop it, so whatever it's serving (see the note on
-- $ref in README's "Known limitations") stays reachable on the network regardless. `path` is
-- the file the current call is refusing to (re)start on, so when it's the very file already
-- being previewed (e.g. it was deleted out from under a still-running preview), say that
-- explicitly instead of the generic "previous preview of <same file> is still running", which
-- reads as if two different files were involved.
local function notify_refused(reason, path)
  local suffix = ""
  if M.job_id then
    if path ~= nil and path == M.file_being_previewed then
      suffix = " (the running preview of this file is unaffected and keeps serving its last-known contents)"
    else
      suffix = " (previous preview of " .. M.file_being_previewed .. " is still running)"
    end
  end
  vim.notify("ScalarPreview: " .. reason .. suffix, vim.log.levels.ERROR)
end

function M.start()
  local path = vim.fn.expand("%:p")

  if path == "" then
    notify_refused("no file to preview in this buffer (unnamed buffer)", nil)
    return
  end

  -- Special buffers (terminal, help, quickfix, scratch, ...) have a 'buftype', and while some
  -- of them do point at a real file on disk, serving it generally isn't what was intended.
  if vim.bo.buftype ~= "" then
    notify_refused("no file to preview in this buffer (buftype=" .. vim.bo.buftype .. ")", path)
    return
  end

  if vim.fn.filereadable(path) == 0 then
    notify_refused("file is not readable on disk: " .. path, path)
    return
  end

  if has_cmd_exe_metachar(vim.fn.fnamemodify(path, ":t")) then
    notify_refused("file name contains characters that aren't safe to pass through cmd.exe on Windows: " .. path, path)
    return
  end

  -- Resolved once, to an absolute path, and reused below for both the check and the argv:
  -- `vim.fn.expand()` would otherwise run the value through Vim's `` ` `` (shell-executes
  -- its contents) and glob handling, which this plugin has no business doing to a config
  -- *path*, and a relative path would resolve against two different directories at the two
  -- places it's used (Neovim's cwd here vs. the job's own cwd -- the previewed file's
  -- directory, see below -- when actually passed to the CLI), silently pointing the CLI at
  -- the wrong file. vim.fs.normalize() does neither of those; it only expands "~".
  local config_path = M.config.config ~= nil and vim.fn.fnamemodify(vim.fs.normalize(M.config.config), ":p") or nil
  if config_path ~= nil and vim.fn.filereadable(config_path) == 0 then
    notify_refused("config file is not readable: " .. config_path, path)
    return
  end

  if config_path ~= nil and has_cmd_exe_metachar(config_path) then
    notify_refused(
      "config path contains characters that aren't safe to pass through cmd.exe on Windows: " .. config_path,
      path
    )
    return
  end

  -- The preview always reflects what's on disk, not the buffer's in-memory contents, so warn
  -- (but don't block) whenever they can currently differ -- including when :ScalarPreview is
  -- called again on the file it's already previewing, since the warning is about the buffer
  -- being out of sync with disk right now, not about (re)starting the job below.
  if vim.bo.modified then
    vim.notify("ScalarPreview: previewing the version on disk; unsaved changes aren't shown", vim.log.levels.WARN)
  end

  if path == M.file_being_previewed then
    return
  end

  if M.job_id then
    M.stop()
  end

  vim.fn.writefile({}, M.log_path)
  M.warned = false
  -- on_stderr's data may split a single line across multiple calls (see the comment there);
  -- this holds whatever's been received so far of the not-yet-newline-terminated last line.
  M.stderr_tail = ""

  -- @scalar/cli's watchFile does `path.join(process.cwd(), file)` without checking whether
  -- `file` is already absolute, so an absolute path gets double-prefixed with cwd and always
  -- "does not exist". Run with cwd = the file's own directory and pass just the basename so
  -- that join produces the right path regardless of Neovim's cwd. The "./" prefix keeps a
  -- basename that happens to start with "-" (e.g. "-weird.yaml") from being parsed as a CLI
  -- flag instead of the file argument.
  local dir = vim.fn.fnamemodify(path, ":h")
  local basename = "./" .. vim.fn.fnamemodify(path, ":t")

  -- A list {cmd} runs the executable directly, with no 'shell' involved, so none of these
  -- arguments need (or benefit from) shell-escaping -- each one reaches the process exactly
  -- as given, whatever characters it contains.
  local cmd = {
    "npx",
    "--yes",
    "@scalar/cli@" .. M.config.cli_version,
    "document",
    "serve",
    basename,
    "-w",
    "-p",
    tostring(M.config.port),
  }
  if config_path ~= nil then
    vim.list_extend(cmd, { "-c", config_path })
  end

  local job_opts = {
    cwd = dir,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line:find("listening on") then
          vim.ui.open(string.format("http://%s:%d", M.config.host, M.config.port))
        end
      end
    end,
    -- Multi-line stack traces come through as one on_stderr line per frame; notifying each
    -- individually floods the UI with dozens of popups, so log them to a file and surface a
    -- single warning instead. Lines that are purely cursor-visibility or color ANSI codes
    -- (the CLI's spinner, or `npm`'s own colored output if the user has `color=always` in
    -- their npmrc) aren't real warnings on their own, so strip those before deciding whether
    -- to notify. Specific `npm warn` lines we know are just noise (EBADENGINE, deprecated
    -- subdependencies) are logged but don't trigger the notification either -- but anything
    -- else from npm, e.g. `npm warn tarball ... corrupted`, still does, since blanket-ignoring
    -- every `npm warn` line would silently swallow ones actually worth seeing.
    on_stderr = function(id, data)
      -- Ignore a stale job: jobstop() only sends SIGTERM and doesn't guarantee immediate
      -- termination, so a fast restart (switching the file being previewed) can have the old
      -- job's trailing stderr arrive after M.job_id already points at the new job. Without
      -- this check, M.warned and the just-truncated M.log_path (see M.start()) would end up
      -- mixing the old and new jobs' output and incorrectly suppressing/triggering the new
      -- job's own notification.
      if id ~= M.job_id then
        return
      end

      -- on_stderr's `data` may split a single line across multiple calls, so a line like
      -- "npm warn EBADENGINE ..." could otherwise arrive as "npm wa" then "rn EBADENGINE ...",
      -- with the first half failing the `npm warn` match below and wrongly triggering the
      -- notification. Per :help channel-lines: every element but the last in `data` is a
      -- complete line; the last one may still be partial unless this call is EOF (`data` is
      -- exactly `{ "" }`), so only the confirmed-complete ones are processed each time.
      local eof = #data == 1 and data[1] == ""
      data = { M.stderr_tail .. data[1], unpack(data, 2) }
      local complete_lines = data
      if not eof then
        complete_lines = { unpack(data, 1, #data - 1) }
        M.stderr_tail = data[#data]
      end
      if #complete_lines == 0 then
        return
      end

      vim.fn.writefile(complete_lines, M.log_path, "a")
      if not M.warned then
        for _, line in ipairs(complete_lines) do
          local stripped = line:gsub("\27%[[%d:;?]*[a-zA-Z]", ""):gsub("\27%][^\7]*\7", "")
          local is_noisy_npm_warning = stripped:lower():match("^npm warn ebadengine")
            or stripped:lower():match("^npm warn deprecated")
          if stripped:match("%S") and not is_noisy_npm_warning then
            M.warned = true
            vim.notify("ScalarPreview: warnings in output, see " .. M.log_path, vim.log.levels.WARN)
            break
          end
        end
      end
    end,
    -- on_exit fires asynchronously, so after a restart the old job's exit can arrive once
    -- the new job is already running. Only clear state that still belongs to this job. We
    -- suppress the error notification purely based on whether *we* called stop() for this
    -- job id, not the exit code (SIGTERM is 143 on POSIX, but jobstop()'s behavior on
    -- Windows isn't guaranteed to match), so a deliberate stop never reports as a failure
    -- regardless of platform.
    on_exit = function(id, code)
      local stopped = M.stopped_jobs[id]
      M.stopped_jobs[id] = nil
      if code ~= 0 and not stopped then
        vim.notify("ScalarPreview exited with code " .. code, vim.log.levels.ERROR)
      end
      if M.job_id == id then
        M.job_id = nil
        M.file_being_previewed = nil
      end
    end,
  }

  -- jobstart is documented to return -1 if cmd[0] isn't executable, but with a list {cmd}
  -- some Neovim versions instead raise a hard Lua error for that case (observed: nightly
  -- v0.13.0-dev raises `E475: ... is not executable` for a cmd[0] not found on $PATH, e.g.
  -- `npx` missing, instead of returning -1). pcall covers both: a thrown error here is just
  -- as much "jobstart failed to start" as a -1 return is, handled identically below.
  local ok, id = pcall(vim.fn.jobstart, cmd, job_opts)

  -- A failed jobstart (whether it returned 0/-1 or raised, see above) must not fall through
  -- to the assignment below: 0 and -1 are both truthy in Lua, so an unguarded assignment
  -- would treat a failed start as a running job id and leave an orphaned M.stopped_jobs entry
  -- if stop() is ever called for it.
  if not ok or id <= 0 then
    vim.notify("ScalarPreview: failed to start (" .. tostring(id) .. ")", vim.log.levels.ERROR)
    return
  end

  M.job_id = id
  M.file_being_previewed = path
end

function M.stop()
  if M.job_id then
    M.stopped_jobs[M.job_id] = true
    vim.fn.jobstop(M.job_id)
  end
  M.job_id = nil
  M.file_being_previewed = nil
end

function M.toggle()
  if M.job_id then
    M.stop()
  else
    M.start()
  end
end

return M
