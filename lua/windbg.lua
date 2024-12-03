

--- @class windbg.Windbg
local M = {}

--- @class windbg.Config
--- @field cdb_path? string path to `cdb.exe` binary
--- @field windbg_path? string path to `windbgx.exe` binary
--- @field port? integer TCP port used for cdb-windbg communication
--- @field window_title? string WinDbg window title
--- @field devmode? boolean developer mode
--- @field windbg_log_file? string path to WinDbg log file (passed to `-loga` agrument)
--- @field plugin_log_file? string path to plugin log file
local default_config = {
    cdb_path = 'cdb.exe', -- you can add `cdb.exe` to PATH or specify absolute path:
    --cdb_path = '$SYSTEMDRIVE\\Program Files (x86)\\Windows Kits\\10\\Debuggers\\x64\\cdb.exe',
    windbg_path = 'windbgx.exe', -- you can add `windbgx.exe` to PATH or specify absolute path:
    --windbg_path = '$LOCALAPPDATA\\Microsoft\\WindowsApps\\WinDbgX.exe',
    port = 1989,
    window_title = 'NVim-WinDbg',
    devmode = false,
    windbg_log_file = nil,
    plugin_log_file = nil
}
--- @type windbg.Config?
local cfg = nil
local function chkcfg() assert(cfg, 'you should call `require("windbg").setup()` first') end

local buffers_package = 'windbg.buffers'
local buffers = require(buffers_package)
local cdb_package = 'windbg.cdb'
local cdb = require(cdb_package)

--- @param user_config? windbg.Config plugin configuration
function M.setup(user_config)
    cfg = vim.tbl_extend('force', default_config, user_config)

    buffers.setup(cfg.devmode, cfg.plugin_log_file)
    buffers.write_log(vim.inspect(cfg))
    cdb.setup(cfg,
        { write_to_vim_buffer=function(out) vim.schedule(function() buffers.write_output(out) end) end },
        { finalize_vim_buffer = function(_) vim.schedule(buffers.finalize_output) end })
end

--- @param command string windbg command
function M.send_command(command)
    chkcfg()
    cdb.DoCommand(command)
end

--- @param command_line string path to executable + arguments
function M.run(command_line)
    chkcfg()
    cdb.Run(command_line)
end

--- @param command_line string path to executable + arguments
--- @param source_file string path to source file
--- @param source_line integer source line number
function M.run_to_line(command_line, source_file, source_line)
    chkcfg()
    cdb.RunTo(command_line, source_file, source_line)
end
--- @param command_line string path to exetutable + arguments
function M.run_to_cursor(command_line)
    chkcfg()
    M.run_to_line(command_line, vim.fn.expand('%:p'), vim.fn.line('.'))
end

function M.kill()
    chkcfg()
    cdb.KillAndDetach()
end

function M.shutdown()
    chkcfg()
    cdb.Shutdown()
    package.loaded[cdb_package] = nil
    package.loaded[buffers_package] = nil
    cfg = nil
end

return M

