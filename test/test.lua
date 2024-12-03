

local test_root = debug.getinfo(1, "S").short_src:gsub('\\[^\\]+$', '')
assert(vim.fn.filereadable(test_root..'\\test.lua'))

local build_dir = test_root..'\\_build'
vim.print('build dir: '..build_dir)
vim.uv.fs_mkdir(build_dir, 1)

local sc
sc = vim.system({'cmake', '..'}, {cwd = build_dir}):wait()
if sc.code ~= 0 then vim.print(sc) end
assert(sc.code == 0, 'cmake generation failed')
local exe_path = build_dir..'\\app.exe'
vim.print('exe path: '..exe_path)

local function build_test_app()
    local cmake_res = vim.system({'cmake', '--build', '.'}, {cwd = build_dir}):wait()
    assert(cmake_res.code == 0, 'cmake build failed')
    assert(vim.fn.filereadable(exe_path))
end
local function delete_test_app()
    vim.fn.delete(exe_path)
    assert(0 == vim.fn.filereadable(exe_path))
end
build_test_app()

local function wait_for_logs(log_path, patterns)
    local step = 5000 / 20
    for i = 1, 20 do
        --print ('match logs, try #'..i)
        local pattern_index = 1
        local log = io.open(log_path, 'r')
        if log then
            local _, matched = pcall(function()
                for line in log:lines() do
                    if string.match(line, patterns[pattern_index]) then
                        --print('`'..patterns[pattern_index]..'` -> `'..line..'`')
                        pattern_index = pattern_index + 1
                        if pattern_index > #patterns then
                            return true
                        end
                    end
                end
                return false
            end)
            log:close()
            if matched then return end
        end
        vim.wait(step)
    end
    assert(false, 'logs no matched')
end

package.path = test_root..'\\..\\lua\\?.lua;'..package.path

local logs_dir = test_root..'\\logs'
assert(0 == vim.fn.delete(logs_dir, 'rf'))
vim.uv.fs_mkdir(logs_dir, 1)
local log_path_fmt = logs_dir..'\\%s.log'

--- @type windbg.Windbg?
local plugin = {}
local log_path = nil
local failed_tests = {}


local function run_test(name, body)

    print(' ==== running test `'..name..'` ====')

    log_path = vim.fn.tempname()..'.log'
    log_path = log_path_fmt:format(name)
    --print('log:\nedit '..log_path..'')

    plugin = require('windbg')

    plugin.setup({
        cdb_path = '$SYSTEMDRIVE\\Program Files (x86)\\Windows Kits\\10\\Debuggers\\x64\\cdb.exe',
        windbg_path = '$LOCALAPPDATA\\Microsoft\\WindowsApps\\WinDbgX.exe',
        devmode = true,
        windbg_log_file = log_path,
        plugin_log_file = log_path..'p',
    })

    local succeeded, err_info = pcall(body)
    if err_info == 'detach' then return end
    if not succeeded then vim.print(err_info) end
    log_path = nil
    plugin.shutdown()
    plugin = nil
    package.loaded.windbg = nil
    print(' ==== test `'..name..'` '..(succeeded and "succeeded" or "FAILED")..' ====')
    if not succeeded then table.insert(failed_tests, name) end
end

local tests = {
    run = function()
        assert(plugin)
        plugin.run(exe_path)
        plugin.send_command('bp app!app')
        plugin.send_command('g')
        plugin.send_command('kc')
        plugin.send_command('g')

        wait_for_logs(assert(log_path), {
            'Breakpoint 0 hit',
            '00%s+app!app',
            '01%s+app!main',
            'NtTerminateProcess'
        })
    end,
    run_to = function()
        assert(plugin)
        plugin.run_to_line(exe_path, test_root..'\\app.c', 4)
        plugin.send_command('kc')
        plugin.send_command('g')

        wait_for_logs(assert(log_path), {
            '00%s+app!app',
            '01%s+app!main',
            'NtTerminateProcess'
        })
    end,
    hard_restart = function()
        assert(plugin)
        plugin.run_to_line(exe_path, test_root..'\\app.c', 4)

        plugin.send_command('.echo "here I am"')
        plugin.send_command('kc')
        plugin.send_command('.restart')

        wait_for_logs(assert(log_path), {
            'here I am',
            '00%s+app!app',
            '01%s+app!main',
            '.restart',
            'connected at', -- new CDB instance connected
        })

        plugin.send_command('.echo "still here"')
        plugin.send_command('bp app!app')
        plugin.send_command('g')
        plugin.send_command('kc')

        wait_for_logs(assert(log_path), {
            'here I am',
            '00%s+app!app',
            '01%s+app!main',
            '.restart',
            'connected at',
            'still here',
            '00%s+app!app',
            '01%s+app!main',
        })

    end,
    kill_run = function()
        assert(plugin)
        plugin.run(exe_path)

        plugin.send_command('.echo "here I am"')
        wait_for_logs(assert(log_path), {'here I am'})

        plugin.kill()

        plugin.send_command('.echo "still here"')
        wait_for_logs(assert(log_path), {'still here'})

        delete_test_app()
        build_test_app()

        plugin.run(exe_path)

        plugin.send_command('bp app!app')
        plugin.send_command('g')
        plugin.send_command('kc')

        wait_for_logs(assert(log_path), {
            '00%s+app!app',
        })
    end,
    kill_run_to = function()
        assert(plugin)
        plugin.run(exe_path)

        plugin.send_command('.echo "here I am"')
        wait_for_logs(assert(log_path), {'here I am'})

        plugin.kill()

        plugin.send_command('.echo "still here"')
        wait_for_logs(assert(log_path), {'still here'})

        delete_test_app()
        build_test_app()

        plugin.run_to_line(exe_path, test_root..'\\app.c', 4)

        wait_for_logs(log_path, {'Breakpoint 0 hit'})

        plugin.send_command('kc')

        wait_for_logs(assert(log_path), {'00%s+app!app'})
    end,
}

local filter='.*'
for k, v in pairs(tests) do
    if k:find(filter) then run_test(k, v) end
end

if #failed_tests == 0 then
    print('\n\nAll tests succeeded.\n\n')
else
    print('\n\nFAILED TESTS:')
    for _, v in ipairs(failed_tests) do
        print('    '..v)
    end
    print('\n')
end

return 0
