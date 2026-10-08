-- server/rank.lua
-- Ranking (spz-progression) controls for the admin menu. spz-progression has
-- no admin chat commands: everything goes through these callbacks, which the
-- Admin.Callback wrapper gates on the admin ace before anything runs.

local function progression()
    return GetResourceState('spz-progression') == 'started'
end

local function call(fn, ...)
    if not progression() then return nil, 'spz-progression is not running' end
    local args = { ... }
    local ok, a, b = pcall(function()
        local res = exports['spz-progression']
        return res[fn](res, table.unpack(args))
    end)
    if not ok then return nil, tostring(a) end
    return a, b
end

Admin.Callback('rankInfo', function(_, target)
    return (call('AdminRankInfo', tonumber(target)))
end)

Admin.Callback('rankStats', function()
    return (call('AdminRankStats'))
end)

Admin.Callback('recentRaces', function()
    return (call('AdminRecentRaces', 20)) or {}
end)

Admin.Callback('setRP', function(src, target, value)
    target, value = tonumber(target), tonumber(value)
    if not Admin.Online(target) or not value or value < 0 then return false, 'Invalid player or value' end
    local ok, msg = call('AdminSetRP', target, value)
    if ok then Admin.Log(src, 'Set rank points', ('%s [%d]: %s'):format(Admin.NameOf(target), target, msg)) end
    return ok == true, msg
end)

Admin.Callback('voidRace', function(src, raceId)
    if type(raceId) ~= 'string' or raceId == '' then return false, 'No race id' end
    local ok, msg = call('AdminVoidRace', raceId)
    if ok then Admin.Log(src, 'Void race', msg) end
    return ok == true, msg
end)
