local M = {}

M.config = {
  port = 8000,
  host = "localhost",
}

M.job_id = nil
M.file_being_previewed = nil
M.log_path = vim.fn.stdpath("state") .. "/scalar-preview.log"
M.warned = false

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.start()
  local path = vim.fn.expand("%:p")

  if path == M.file_being_previewed then
    return
  end

  if M.job_id then
    M.stop()
  end

  vim.fn.writefile({}, M.log_path)
  M.warned = false

  -- @scalar/cli's watchFile does `path.join(process.cwd(), file)` without checking whether
  -- `file` is already absolute, so an absolute path gets double-prefixed with cwd and always
  -- "does not exist". Run with cwd = the file's own directory and pass just the basename so
  -- that join produces the right path regardless of Neovim's cwd.
  local dir = vim.fn.fnamemodify(path, ":h")
  local basename = vim.fn.fnamemodify(path, ":t")
  local cmd =
    string.format("npx --yes @scalar/cli document serve %s -w -p %d", vim.fn.shellescape(basename), M.config.port)

  M.job_id = vim.fn.jobstart(cmd, {
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
    -- single warning instead. Lines that are purely cursor-visibility ANSI codes (the CLI's
    -- spinner) aren't real warnings, so strip those before deciding whether to notify.
    on_stderr = function(_, data)
      vim.fn.writefile(data, M.log_path, "a")
      if not M.warned then
        for _, line in ipairs(data) do
          if line:gsub("\27%[%?25[lh]", ""):match("%S") then
            M.warned = true
            vim.notify("ScalarPreview: warnings in output, see " .. M.log_path, vim.log.levels.WARN)
            break
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("ScalarPreview exited with code " .. code, vim.log.levels.ERROR)
      end
      M.job_id = nil
      M.file_being_previewed = nil
    end,
  })
  M.file_being_previewed = path
end

function M.stop()
  if M.job_id then
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
