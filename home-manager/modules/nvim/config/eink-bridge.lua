local M = {}

M.server = "http://localhost:3333"
M._last_session = nil
M._timer = nil

local function get_content(mode)
  if mode == "visual" then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    return table.concat(lines, "\n")
  end
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local function poll_result(session_id)
  if M._timer then
    M._timer:stop()
    M._timer:close()
  end
  M._timer = vim.uv.new_timer()
  M._timer:start(2000, 3000, vim.schedule_wrap(function()
    vim.fn.jobstart({
      "eink-review", "--server", M.server, "result", session_id,
    }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        local output = table.concat(data, "\n")
        if output:find("review notes") then
          if M._timer then
            M._timer:stop()
            M._timer:close()
            M._timer = nil
          end
          vim.schedule(function()
            vim.cmd("vnew")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, "\n"))
            vim.bo.buftype = "nofile"
            vim.bo.filetype = "markdown"
            vim.notify("eink-bridge: review received", vim.log.levels.INFO)
          end)
        end
      end,
      on_stderr = function(_, data)
        local msg = table.concat(data, "\n")
        if msg:find("cancelled") or msg:find("not found") then
          if M._timer then
            M._timer:stop()
            M._timer:close()
            M._timer = nil
          end
          vim.schedule(function()
            vim.notify("eink-bridge: " .. msg, vim.log.levels.WARN)
          end)
        end
      end,
    })
  end))
end

function M.push(mode)
  local content = get_content(mode)
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.split(content, "\n"), tmp)

  vim.fn.jobstart({
    "eink-review", "--server", M.server, "push", "--async", tmp,
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local id = vim.trim(table.concat(data, ""))
      if id ~= "" then
        M._last_session = id
        vim.schedule(function()
          vim.notify("eink-bridge: session " .. id .. " created, waiting...", vim.log.levels.INFO)
        end)
        poll_result(id)
      end
    end,
    on_exit = function(_, code)
      vim.fn.delete(tmp)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("eink-bridge: push failed", vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

function M.cancel()
  if not M._last_session then
    vim.notify("eink-bridge: no active session", vim.log.levels.WARN)
    return
  end
  vim.fn.jobstart({
    "eink-review", "--server", M.server, "cancel", M._last_session,
  }, {
    on_exit = function(_, code)
      if M._timer then
        M._timer:stop()
        M._timer:close()
        M._timer = nil
      end
      vim.schedule(function()
        if code == 0 then
          vim.notify("eink-bridge: cancelled " .. M._last_session, vim.log.levels.INFO)
        else
          vim.notify("eink-bridge: cancel failed", vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

function M.list()
  vim.fn.jobstart({
    "eink-review", "--server", M.server, "list",
  }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local output = table.concat(data, "\n")
      vim.schedule(function()
        if output == "" then
          vim.notify("eink-bridge: no sessions", vim.log.levels.INFO)
        else
          vim.cmd("vnew")
          vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, "\n"))
          vim.bo.buftype = "nofile"
        end
      end)
    end,
  })
end

vim.keymap.set("n", "<leader>ep", function() M.push("buffer") end, { desc = "eink: push buffer" })
vim.keymap.set("v", "<leader>ep", function() M.push("visual") end, { desc = "eink: push selection" })
vim.keymap.set("n", "<leader>ec", M.cancel, { desc = "eink: cancel review" })
vim.keymap.set("n", "<leader>ea", M.list, { desc = "eink: list sessions" })

return M
