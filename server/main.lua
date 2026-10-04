-- server/main.lua
-- Authority for every admin action. The client menu is presentation only: each
-- callback re-checks the ace here, so nothing is reachable by triggering the
-- event directly.

Admin = {}

function Admin.IsAdmin(src)
    src = tonumber(src)
    if not src then return false end
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, Config.Ace)
end
-- Late-bound so server/admins.lua can widen the check (menu-granted admins).
exports('IsAdmin', function(src) return Admin.IsAdmin(src) end)

function Admin.Online(src)
    return src and GetPlayerName(src) ~= nil
end

function Admin.NameOf(src)
    local st = Player(src).state
    local n = st and st['spz:name']
    if not n or n == '' or n == '**INVALID**' then n = GetPlayerName(src) end
    return n or ('Player ' .. tostring(src))
end

function Admin.Notify(src, description, ntype)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Admin', description = description, type = ntype or 'inform',
    })
end

function Admin.Log(src, title, message)
    if GetResourceState('spz-analytics') == 'started' then
        pcall(function() exports['spz-analytics']:AdminAction(src, title, message) end)
    end
    print(('^5[spz-admin]^7 %s (%d): %s — %s'):format(GetPlayerName(src) or 'console', src, title, message or ''))
    if GetResourceState('spz-log') == 'started' then
        pcall(function()
            exports['spz-log']:Info(Config.LogCategory, 'Admin: ' .. title, message or '', nil, src)
        end)
    end
end

--- Move a player into a routing bucket. spz-core owns the bucket registry, so go
--- through it when the bucket is one it knows; a raw move would be undone by
--- its reconciliation sweep.
function Admin.SetBucket(src, bucket)
    if GetResourceState('spz-core') == 'started' then
        local ok, known = pcall(function()
            return exports['spz-core']:GetBucketRegistry()[bucket] ~= nil
        end)
        if ok and known then
            local moved = exports['spz-core']:AssignPlayerToBucket(src, bucket)
            if moved then return true end
        end
    end
    SetPlayerRoutingBucket(src, bucket)
    return true
end

--- Register an admin-only callback: `spz-admin:<name>`.
function Admin.Callback(name, fn)
    lib.callback.register('spz-admin:' .. name, function(src, ...)
        if not Admin.IsAdmin(src) then return false, 'Not authorised' end
        return fn(src, ...)
    end)
end

function Admin.Coords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
end

local function identifiers(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        local kind = id:match('^(%w+):')
        -- IPs stay out of the menu on purpose.
        if kind and kind ~= 'ip' then out[kind] = id end
    end
    return out
end

-- ── Queries ──────────────────────────────────────────────────────────────────

Admin.Callback('isAdmin', function() return true end)

Admin.Callback('players', function()
    local out = {}
    for _, sid in ipairs(GetPlayers()) do
        local s   = tonumber(sid)
        local st  = Player(s).state
        local ped = GetPlayerPed(s)
        out[#out + 1] = {
            id      = s,
            name    = Admin.NameOf(s),
            bucket  = GetPlayerRoutingBucket(s),
            ping    = GetPlayerPing(s),
            inRace  = st and st.inRace == true or false,
            inQueue = st and st.inQueue == true or false,
            inVeh   = ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0,
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

Admin.Callback('player', function(_, target)
    target = tonumber(target)
    if not Admin.Online(target) then return nil end
    local st  = Player(target).state
    local ped = GetPlayerPed(target)
    local veh = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0

    return {
        id       = target,
        name     = Admin.NameOf(target),
        steam    = GetPlayerName(target),
        bucket   = GetPlayerRoutingBucket(target),
        ping     = GetPlayerPing(target),
        health   = ped ~= 0 and GetEntityHealth(ped) or 0,
        coords   = Admin.Coords(target),
        vehicle  = veh ~= 0 and GetEntityModel(veh) or nil,
        plate    = veh ~= 0 and GetVehicleNumberPlateText(veh) or nil,
        inRace   = st and st.inRace == true or false,
        inQueue  = st and st.inQueue == true or false,
        crew     = st and st['spz:crew'] or nil,
        license  = st and st['spz:license'] or nil,
        frozen   = st and st['spz:adminFrozen'] == true or false,
        admin    = Admin.AdminStatus(target),
        ids      = identifiers(target),
    }
end)

Admin.Callback('buckets', function()
    local labels = {}
    if GetResourceState('spz-core') == 'started' then
        local ok, reg = pcall(function() return exports['spz-core']:GetBucketRegistry() end)
        if ok and type(reg) == 'table' then
            for id, b in pairs(reg) do labels[id] = b.label end
        end
    end

    local map = {}
    for id, label in pairs(labels) do map[id] = { id = id, label = label, players = {} } end
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        local b = GetPlayerRoutingBucket(s)
        map[b] = map[b] or { id = b, label = labels[b], players = {} }
        table.insert(map[b].players, { id = s, name = Admin.NameOf(s) })
    end

    local out = {}
    for _, b in pairs(map) do out[#out + 1] = b end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end)

Admin.Callback('myBucket', function(src)
    return GetPlayerRoutingBucket(src)
end)

-- ── Movement ─────────────────────────────────────────────────────────────────

Admin.Callback('goto', function(src, target)
    target = tonumber(target)
    if not Admin.Online(target) or target == src then return false end
    local c = Admin.Coords(target)
    if not c then return false end
    Admin.SetBucket(src, GetPlayerRoutingBucket(target))
    Admin.Log(src, 'Goto', ('%s → %s'):format(GetPlayerName(src), Admin.NameOf(target)))
    return c
end)

Admin.Callback('bring', function(src, target)
    target = tonumber(target)
    if not Admin.Online(target) or target == src then return false end
    local c = Admin.Coords(src)
    if not c then return false end
    Admin.SetBucket(target, GetPlayerRoutingBucket(src))
    TriggerClientEvent('spz-admin:teleport', target, c)
    Admin.Notify(target, 'You were brought by an admin')
    Admin.Log(src, 'Bring', ('%s brought %s'):format(GetPlayerName(src), Admin.NameOf(target)))
    return true
end)

Admin.Callback('joinBucket', function(src, bucket)
    bucket = tonumber(bucket)
    if not bucket then return false end
    Admin.SetBucket(src, bucket)
    Admin.Log(src, 'Bucket', ('%s joined bucket %d'):format(GetPlayerName(src), bucket))
    return true
end)

Admin.Callback('sendBucket', function(src, target, bucket)
    target, bucket = tonumber(target), tonumber(bucket)
    if not Admin.Online(target) or not bucket then return false end
    Admin.SetBucket(target, bucket)
    Admin.Log(src, 'Bucket', ('%s moved %s to bucket %d'):format(GetPlayerName(src), Admin.NameOf(target), bucket))
    return true
end)

-- ── Player actions ───────────────────────────────────────────────────────────

-- Actions carried out on the target's own client (they own their ped/vehicle).
local ClientActions = {
    heal   = 'Healed',
    kill   = 'Killed',
    repair = 'Repaired vehicle of',
    flip   = 'Flipped vehicle of',
}

Admin.Callback('action', function(src, target, action)
    target = tonumber(target)
    if not Admin.Online(target) or not ClientActions[action] then return false end
    TriggerClientEvent('spz-admin:action', target, action)
    Admin.Log(src, 'Action', ('%s %s %s'):format(GetPlayerName(src), ClientActions[action]:lower(), Admin.NameOf(target)))
    return true
end)

-- Trolls: whitelisted here, carried out on the target's client (the driver
-- owns the car and the player owns their ped, so only their client can move or
-- break either). `veh` = needs the target to be in a vehicle.
local Trolls = {
    -- car
    launch   = { 'Launch', veh = true },      boost    = { 'Boost', veh = true },
    brake    = { 'Brake wall', veh = true },  spin     = { 'Spin out', veh = true },
    upside   = { 'Flip upside down', veh = true }, tires = { 'Pop tyres', veh = true },
    stall    = { 'Stall engine', veh = true }, eject   = { 'Eject', veh = true },
    lockin   = { 'Lock in', veh = true },     slippery = { 'Ice tyres', veh = true },
    limiter  = { 'Speed limit', veh = true }, smoke    = { 'Smoking engine', veh = true },
    paint    = { 'Random paint', veh = true }, horn    = { 'Stuck horn', veh = true },
    lights   = { 'Disco lights', veh = true }, explode = { 'Explode car', veh = true },
    throttle = { 'Stuck throttle', veh = true }, nobrakes = { 'Brake failure', veh = true },
    wobble   = { 'Wobbly steering', veh = true }, moon   = { 'Moon gravity', veh = true },
    ghostcar = { 'Invisible car', veh = true }, hop     = { 'Bunny hop', veh = true },
    -- player (work on foot or in a car)
    invert   = { 'Invert controls' },         drunk    = { 'Drunk' },
    lookback = { 'Look backwards' },          blind    = { 'Blackout' },
    ragdoll  = { 'Ragdoll' },                 fling    = { 'Fling' },
    fire     = { 'Set on fire' },
}

local function trollGate(target)
    if not Admin.Online(target) then return 'Player is offline' end
    local st = Player(target).state
    if st and st.inRace == true and not Config.Troll.allowInRace then
        return 'Player is racing (Config.Troll.allowInRace)'
    end
end

Admin.Callback('troll', function(src, target, action)
    target = tonumber(target)
    local def = Trolls[action]
    if not def then return false, 'Unknown troll' end
    local blocked = trollGate(target)
    if blocked then return false, blocked end

    if def.veh then
        local ped = GetPlayerPed(target)
        if ped == 0 or GetVehiclePedIsIn(ped, false) == 0 then return false, 'Player is not in a vehicle' end
    end

    TriggerClientEvent('spz-admin:troll', target, action, Config.Troll.duration)
    Admin.Log(src, 'Troll', ('%s → %s: %s'):format(GetPlayerName(src), Admin.NameOf(target), def[1]))
    return true, def[1]
end)

-- ── Possess ──────────────────────────────────────────────────────────────────
-- The admin drives the target: the admin's client streams its WASD state here,
-- and it is relayed to the target's client, which feeds it into the game as if
-- it were their own input (client/troll.lua). Only relayed for an admin with an
-- active possession, so the event can't be used to drive anyone otherwise.

local Possess = {}   -- [admin] = target

Admin.Callback('possess', function(src, target)
    target = tonumber(target)
    if target == src then return false, 'Not yourself' end
    local blocked = trollGate(target)
    if blocked then return false, blocked end

    if Possess[src] and Possess[src] ~= target then
        TriggerClientEvent('spz-admin:possessed', Possess[src], false)
    end
    Possess[src] = target
    TriggerClientEvent('spz-admin:possessed', target, true)
    Admin.Log(src, 'Possess', ('%s possessed %s'):format(GetPlayerName(src), Admin.NameOf(target)))
    return true
end)

local function release(admin)
    local target = Possess[admin]
    if not target then return end
    Possess[admin] = nil
    if Admin.Online(target) then TriggerClientEvent('spz-admin:possessed', target, false) end
end

Admin.Callback('unpossess', function(src)
    release(src)
    return true
end)

RegisterNetEvent('spz-admin:possessInput', function(input)
    local target = Possess[source]
    if not target or type(input) ~= 'table' then return end
    TriggerClientEvent('spz-admin:possessInput', target, input)
end)

AddEventHandler('playerDropped', function()
    local dropped = source
    release(dropped)
    for admin, target in pairs(Possess) do
        if target == dropped then
            Possess[admin] = nil
            TriggerClientEvent('spz-admin:possessEnded', admin)
        end
    end
end)

Admin.Callback('freeze', function(src, target)
    target = tonumber(target)
    if not Admin.Online(target) then return false end
    local st = Player(target).state
    local frozen = not (st['spz:adminFrozen'] == true)
    st:set('spz:adminFrozen', frozen, true)
    TriggerClientEvent('spz-admin:freeze', target, frozen)
    Admin.Notify(target, frozen and 'You were frozen by an admin' or 'You were unfrozen', frozen and 'warning' or 'inform')
    Admin.Log(src, 'Freeze', ('%s %s %s'):format(GetPlayerName(src), frozen and 'froze' or 'unfroze', Admin.NameOf(target)))
    return frozen
end)

Admin.Callback('message', function(src, target, text)
    target = tonumber(target)
    if not Admin.Online(target) or type(text) ~= 'string' or text == '' then return false end
    TriggerClientEvent('ox_lib:notify', target, {
        title = 'Message from admin', description = text:sub(1, 300), type = 'warning', duration = 10000,
    })
    Admin.Log(src, 'Message', ('%s → %s: %s'):format(GetPlayerName(src), Admin.NameOf(target), text))
    return true
end)

Admin.Callback('kick', function(src, target, reason)
    target = tonumber(target)
    if not Admin.Online(target) or target == src then return false end
    reason = (type(reason) == 'string' and reason ~= '') and reason or 'Kicked by an admin'
    Admin.Log(src, 'Kick', ('%s kicked %s: %s'):format(GetPlayerName(src), Admin.NameOf(target), reason))
    DropPlayer(target, reason)
    return true
end)

-- Race control: DNF runs spz-races' own cleanup, so the racer leaves the race
-- properly instead of being yanked out of the bucket.
Admin.Callback('dnf', function(src, target)
    target = tonumber(target)
    if not Admin.Online(target) or GetResourceState('spz-races') ~= 'started' then return false end
    local ok = pcall(function() exports['spz-races']:MarkDNF(target, 'admin') end)
    if ok then Admin.Log(src, 'DNF', ('%s DNF\'d %s'):format(GetPlayerName(src), Admin.NameOf(target))) end
    return ok
end)

Admin.Callback('unqueue', function(src, target)
    target = tonumber(target)
    if not Admin.Online(target) or GetResourceState('spz-races') ~= 'started' then return false end
    local ok = pcall(function() exports['spz-races']:LeaveQueue(target) end)
    if ok then Admin.Log(src, 'Unqueue', ('%s removed %s from the queue'):format(GetPlayerName(src), Admin.NameOf(target))) end
    return ok
end)

-- ── Server ───────────────────────────────────────────────────────────────────

Admin.Callback('announce', function(src, text)
    if type(text) ~= 'string' or text == '' then return false end
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'Announcement', description = text:sub(1, 300), type = 'inform',
        duration = 12000, position = 'top',
    })
    Admin.Log(src, 'Announce', text)
    return true
end)

Admin.Callback('weather', function(src, weather)
    if type(weather) ~= 'string' or GetResourceState('spz-core') ~= 'started' then return false end
    exports['spz-core']:SetSyncedWeather(weather)
    Admin.Log(src, 'Weather', weather)
    return true
end)

Admin.Callback('time', function(src, h, m)
    h, m = tonumber(h), tonumber(m) or 0
    if not h or GetResourceState('spz-core') ~= 'started' then return false end
    exports['spz-core']:SetSyncedTime(h, m)
    Admin.Log(src, 'Time', ('%02d:%02d'):format(h, m))
    return true
end)

-- Delete unoccupied vehicles in a radius around the admin (their bucket only).
Admin.Callback('clearVehicles', function(src, radius)
    radius = math.min(tonumber(radius) or 50.0, 500.0)
    local me = Admin.Coords(src)
    if not me then return 0 end
    local origin = vec3(me.x, me.y, me.z)
    local bucket = GetPlayerRoutingBucket(src)
    local n = 0
    for _, veh in ipairs(GetAllVehicles()) do
        if GetEntityRoutingBucket(veh) == bucket
            and #(GetEntityCoords(veh) - origin) <= radius then
            local occupied = false
            for seat = -1, 6 do
                if GetPedInVehicleSeat(veh, seat) ~= 0 then occupied = true break end
            end
            if not occupied then DeleteEntity(veh); n = n + 1 end
        end
    end
    Admin.Log(src, 'Clear vehicles', ('%d within %dm'):format(n, radius))
    return n
end)
