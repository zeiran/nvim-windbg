local M = {}

local devmode = false

local function find_buffer(name)
    for _, buffer in pairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buffer):find(name, 0, true) then
            return buffer
        end
    end
    return nil
end

local function open_buffer(name)
    local b = find_buffer(name)
    if not b then
        b = vim.api.nvim_create_buf(devmode, true)
        if not b then error("can't create buffer") end
        vim.api.nvim_buf_set_name(b, name)
    else
        vim.fn.deletebufline(b, 1, '$')
    end
    return b
end

local out_buffer = 0
local log_buffer = 0
local log_file = nil

--- @param is_devmode boolean
function M.setup(is_devmode, log_file_path)
    devmode = is_devmode
    out_buffer = open_buffer('[WinDbg output]')
    if devmode then log_buffer = open_buffer('[WinDbg log]') end
    if log_file_path then log_file = io.open(log_file_path, 'w') end
end

local finalized = true

function M.finalize_output()
    finalized = true
end

function M.write_output(text)
    if finalized then
        vim.api.nvim_buf_set_lines(out_buffer, 0, -1, false, {})
    end
    for line in text:gmatch('[^\n]+') do
        vim.api.nvim_buf_set_lines(out_buffer, -1, -1, false, { line })
    end
    finalized = false
end

function M.write_log(msg, level)
    if log_file then log_file:write(msg..'\n') end

    if not devmode then
        if level and level > vim.log.levels.INFO then vim.notify(msg, level) end
        return
    end

    local prefix = (level and level > vim.log.levels.INFO) and '! ' or '  '
    vim.fn.appendbufline(log_buffer, '$', prefix..msg) ---@diagnostic disable-line:param-type-mismatch
end

return M
