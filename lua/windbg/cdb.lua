local M = {}

--TODO посмотреть 'extmarks' и 'sign' для реализации брекпонтов

--- @type windbg.Config
local cfg = nil

--- @type vim.SystemObj? CDB process
local cdb = nil

--- @type vim.SystemObj? windbg process
local windbg = nil
local debugee_detached = false

local output_handlers = {}
local whole_output_handlers = {}

local log = require'windbg.buffers'.write_log

--- @param config windbg.Config
function M.setup(config, handlers, whole_handlers)
    log('Setup:\n'..vim.inspect(config))
    cfg = config
--    checkhealth_cdb()
    output_handlers = handlers;
    whole_output_handlers = whole_handlers;
end

local windbg_output = {
    is_kill = function (msg)
        return not not string.match(msg, '^Terminated.%s+Exit thread and process events will occur.')
    end,
    is_detach = function (msg)
        return not not string.match(msg, '^Detached')
    end,
    is_restart = function (msg)
        return not not string.match(msg, '>%s*%.restart')
    end
}

--TODO реализовать checkhealth

--local function checkhealth_cdb()
    --local success, so = pcall(vim.system, {cdb_path, '-version'}, {text=true})
    --if not success then
        --log('CDB is not available: `cdb -version` raises an error', vim.log.levels.WARN)
        --return
    --else
        --local sc = so:wait()
        --if sc.code ~= 0 or not string.match(sc.stdout, 'cdb version') then
            --log('CDB is not available: `cdb -version` returns '..sc.code..' and says "'..sc.stdout..'"', vim.log.levels.WARN)
            --return
        --end
    --end
    --log('CDB is healthy')
--end

local function focus_windbg()
    vim.system({"powershell", "-command", "$wshell = New-Object -ComObject wscript.shell ; $wshell.AppActivate('"..cfg.window_title.."')"})
end

local command_marker_fmt = 'nvim-command-#%02d'
local command_marker_counter = 0

local function do_command(cmd, callback)
    log('do_command: '..cmd)
    assert(cdb, "CDB not connected")
    if #output_handlers > 10 then log('more than 10 output handlers, it\'s probably a bug', vim.log.levels.WARN) end
    if not callback then
        cdb:write(cmd .. '\n')
    else
        local key = command_marker_fmt:format(command_marker_counter)
        log('marked cmd `'..key..'`: '..cmd)
        command_marker_counter = (command_marker_counter < 100) and (command_marker_counter + 1) or 0
        assert(not output_handlers[key])
        output_handlers[key] = function(output)
            if output:find(key, 0, true) then
                log('marked cmd `'..key..'` completed')
                output_handlers[key] = nil
                -- capture some output ?
                if callback then callback() end
            end
        end
        cdb:write(cmd .. '\n')
        cdb:write('.echo "' .. key .. '"\n')
    end
end

local output_line = ''
local output_lines = {}
local function cdb_output_callback(_, chunk)
    if not chunk then return end
    --log('Windbg says "'..chunk..'"')
    if windbg_output.is_kill(chunk) then
        log('`.kill` detected')
    elseif windbg_output.is_restart(chunk) then
        log('`.restart` detected')
    elseif windbg_output.is_detach(chunk) then
        log('`.detach` detected')
        debugee_detached = true
    end
    if chunk:match('^[%a%d :]+> ?$') then -- end of block (next prompt appeared)
        log('WinDbg outputs '..#output_lines..' lines')
        for _, handler in pairs(whole_output_handlers) do handler(output_lines) end
        output_lines = {}
        output_line = ''
    else
        for line in chunk:gmatch('[^\n]+\n?') do
            local eol = line:sub(#line) == '\n'
            if eol then line = line:sub(0, -2) end
            output_line = output_line .. line
            if eol then
                for _, handler in pairs(output_handlers) do handler(output_line) end
                table.insert(output_lines, output_line)
                output_line = ''
            end
        end
    end
end

local function start_windbg(command)
    local args = { vim.fn.expandcmd(cfg.windbg_path), "-T", cfg.window_title, '-server', "tcp:port="..cfg.port..',clicon=localhost', command };
    if cfg.windbg_log_file then
        table.insert(args, 2, '-loga'); table.insert(args, 3, cfg.windbg_log_file)
    end
    windbg = vim.system(args,
        {}, vim.schedule_wrap(function (exit_info)
            log(string.format('WinDbg (pid %d) exited with code 0x%08x', assert(windbg).pid, exit_info.code))
            windbg = nil
        end))
    log('WinDbg (pid '..windbg.pid..') started: '..table.concat(windbg.cmd, ' '))
end

local function start_cdb_clicon()
    if cdb then
        log('CDB (pid '..cdb.pid..') already started, port '..cfg.port)
        return
    end
    local function cdb_exit_callback(exit_info)
        log(string.format('CDB (pid %d) exited with code 0x%08x', assert(cdb).pid, exit_info.code))
        cdb = nil
        local RPC_E_CLIENT_DIED = 0x80010008
        if exit_info.code == RPC_E_CLIENT_DIED then
            start_cdb_clicon() -- CDB завершается, если в виндбг нажать stop debugging или restart, на этот случай перезапускаем CDB и ждем, когда WinDbg переподключится
        end
    end
    cdb = vim.system({ vim.fn.expandcmd(cfg.cdb_path), "-remote", 'tcp:clicon=localhost,port='..cfg.port },
        { stdin = true, text = true, stdout = vim.schedule_wrap(cdb_output_callback) }, vim.schedule_wrap(cdb_exit_callback))

    log('CDB (pid '..cdb.pid..') started: '..table.concat(cdb.cmd, ' '))
end

local function run(command, callback)
    start_cdb_clicon()
    if windbg then
        if not debugee_detached then do_command('.kill; .detach') end
        -- если после .detach позвать еще раз .detach, пайп отваливается (?)
        do_command('.create "'..command..'"', function ()
            debugee_detached = false
        end)
        do_command('g', callback) -- `g` will stop on initial breakpoint, run callback at this moment
    else
        start_windbg(command)
        if callback then callback() end
    end
    focus_windbg()
end

function M.Run(command)
    log('M.Run("'..command..'")')
    run(command)
end

function M.RunTo(command, sourceFile, sourceLine)
    log('M.RunTo("'..command..'", '..sourceFile..':'..sourceLine..')')
    local breakpoint_cmd = 'bp `' .. sourceFile .. ':' .. sourceLine .. '` ; g';
    run(command, function ()
        do_command(breakpoint_cmd)
    end)
end

function M.KillAndDetach()
    log('M.KillAndDetach()')
    if not windbg or debugee_detached then return end
    do_command('.kill; .detach')
    debugee_detached = true
end

function M.DoCommand(cmd)
    log('M.DoCommand("'..cmd..'")')
    do_command(cmd)
end

function M.Shutdown()
    if cdb then
        log('shutdown: killing CDB (pid '..cdb.pid..')')
        cdb:kill(9)
        cdb:wait()
    end
    if windbg then
        log('shutdown: killing WinDbg (pid '..windbg.pid..')')
        windbg:kill(9)
        windbg:wait()
    end
end

return M
