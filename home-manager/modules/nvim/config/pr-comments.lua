-- Record a review comment at the cursor, for the GitHub review posted at the end.
--
-- The reading workspace sets EINK_PR_NUMBER; the fallbacks cover an editor opened by
-- hand from a pr-<n> worktree. Comments go to
-- ~/.local/state/eink-bridge/comments/pr-<n>.jsonl, the same file the e-ink notes use,
-- so `pr_comments.py post` can turn both into one review.

local M = {}

local state_dir = vim.env.EINK_PR_STATE or (vim.env.HOME .. "/.local/state/eink-bridge")

local function git(args)
  local command = { "git", "-C", vim.fn.getcwd() }
  vim.list_extend(command, args)
  local output = vim.fn.systemlist(command)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return output[1]
end

local function repo_root()
  return git({ "rev-parse", "--show-toplevel" })
end

local function pr_number()
  local explicit = vim.env.EINK_PR_NUMBER or ""
  if explicit:match("^%d+$") then
    return tonumber(explicit)
  end
  local from_url = (vim.env.EINK_REVIEW_PR or ""):match("/pull/(%d+)")
  if from_url then
    return tonumber(from_url)
  end
  -- ~/programming/<org>/worktrees/pr-<n>/<repo>
  local parent = vim.fn.fnamemodify(vim.fn.getcwd(), ":h")
  return tonumber(parent:match("pr%-(%d+)$"))
end

--- The file and side under the cursor, or nil and a reason.
--
-- Diffview names the new side with the real file path and the base side
-- `diffview://<root>/<sha>/<path>`, so the side is not a guess: the base buffer's line
-- numbers are the old file's, which is what GitHub's LEFT side means.
local function buffer_location()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return nil, nil, "open a file from the diff, not a scratch buffer"
  end
  local root = repo_root()
  if not root then
    return nil, nil, "not inside a git checkout"
  end
  local prefix = root .. "/"

  local path, side
  if name:sub(1, 12) == "diffview://" then
    local rest = name:sub(13)
    if rest:sub(1, #prefix) ~= prefix then
      return nil, nil, "this diff belongs to a different checkout"
    end
    local _, relative = rest:sub(#prefix + 1):match("^([^/]+)/(.+)$")
    path, side = relative, "LEFT"
  else
    local absolute = vim.fn.fnamemodify(name, ":p")
    if absolute:sub(1, #prefix) ~= prefix then
      return nil, nil, "this buffer is outside the review worktree"
    end
    path, side = absolute:sub(#prefix + 1), "RIGHT"
  end

  if not path or path == "" or path:find("/$") then
    return nil, nil, "this buffer does not name a file in the checkout"
  end
  return path, side
end

function M.add()
  local pr = pr_number()
  if not pr then
    vim.notify("PR comments: no pull request (EINK_PR_NUMBER is not set)",
      vim.log.levels.WARN)
    return
  end
  local path, side, reason = buffer_location()
  if not path then
    vim.notify("PR comments: " .. reason, vim.log.levels.WARN)
    return
  end
  local line = vim.fn.line(".")
  local prompt = string.format("Comment on %s:%d (%s): ", path, line, side)
  vim.ui.input({ prompt = prompt }, function(text)
    text = vim.trim(text or "")
    if text == "" then
      return
    end
    local entry = {
      pr = pr,
      path = path,
      line = line,
      side = side,
      body = text,
      source = "nvim",
      worktree = repo_root() or "",
      created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    local directory = state_dir .. "/comments"
    vim.fn.mkdir(directory, "p")
    local file, error = io.open(directory .. "/pr-" .. pr .. ".jsonl", "a")
    if not file then
      vim.notify("PR comments: cannot write " .. tostring(error), vim.log.levels.ERROR)
      return
    end
    file:write(vim.json.encode(entry) .. "\n")
    file:close()
    vim.fn.sign_define("EinkReviewComment", { text = "▎", texthl = "DiagnosticInfo" })
    vim.fn.sign_place(0, "eink-review", "EinkReviewComment",
      vim.api.nvim_get_current_buf(), { lnum = line })
    vim.notify(string.format("Comment recorded at %s:%d (%s)", path, line, side),
      vim.log.levels.INFO)
  end)
end

function M.list()
  local pr = pr_number()
  if not pr then
    vim.notify("PR comments: no pull request (EINK_PR_NUMBER is not set)",
      vim.log.levels.WARN)
    return
  end
  local file = state_dir .. "/comments/pr-" .. pr .. ".jsonl"
  local raw = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or {}
  local output = {}
  for _, line in ipairs(raw) do
    local ok, entry = pcall(vim.json.decode, line)
    if ok then
      table.insert(output, string.format("[%s] %s:%d (%s) — %s",
        entry.source or "?", entry.path, entry.line, entry.side or "RIGHT", entry.body))
    end
  end
  if #output == 0 then
    table.insert(output, "No comments recorded for PR " .. pr)
  end
  vim.cmd("vnew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
  vim.bo.buftype = "nofile"
  vim.bo.filetype = "markdown"
  vim.bo.swapfile = false
end

vim.api.nvim_create_user_command("EinkComment", M.add, {})
vim.api.nvim_create_user_command("EinkComments", M.list, {})
vim.keymap.set({ "n", "v" }, "<leader>gc", M.add,
  { desc = "PR: comment at this line" })

return M
