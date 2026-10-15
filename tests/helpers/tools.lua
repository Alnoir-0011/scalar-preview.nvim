-- Specs that drive a real executable can only run where it exists. Locally that is a
-- pending spec; on CI it must be a failure, otherwise the safety checks these specs exist
-- for would quietly stop running the day the runner image drops the tool.
local M = {}

function M.it_requiring(name, available)
  if available then
    return it
  end
  if vim.env.CI then
    return function(description)
      it(description, function()
        error(name .. " is required on CI but was not found")
      end)
    end
  end
  return pending
end

function M.executable(name)
  return vim.fn.executable(name) == 1
end

return M
