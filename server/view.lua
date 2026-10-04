-- server/view.lua
-- Spectate + ride-along. Both need the admin in the target's routing bucket so
-- the target actually streams in. We remember the bucket the admin came from
-- (only on the first hop, so switching targets never loses it), keep following
-- the target if their bucket changes (race start/end), and put the admin back
-- when they stop.

local Viewing = {}   -- [adminSrc] = { target = src, prevBucket = n, mode = 'spectate'|'ride' }

local function vehicleNet(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil end
    return NetworkGetNetworkIdFromEntity(veh)
end

Admin.Callback('view', function(src, target, mode)
    target = tonumber(target)
    if not Admin.Online(target) or target == src then return false end
    mode = mode == 'ride' and 'ride' or 'spectate'

    local rec  = Viewing[src]
    local prev = rec and rec.prevBucket or GetPlayerRoutingBucket(src)
    local bucket = GetPlayerRoutingBucket(target)

    Admin.SetBucket(src, bucket)
    Viewing[src] = { target = target, prevBucket = prev, mode = mode }

    if not rec or rec.target ~= target or rec.mode ~= mode then
        Admin.Log(src, mode == 'ride' and 'Ride along' or 'Spectate',
            ('%s → %s (bucket %d)'):format(GetPlayerName(src), Admin.NameOf(target), bucket))
    end

    return {
        name   = Admin.NameOf(target),
        bucket = bucket,
        coords = Admin.Coords(target),
        veh    = vehicleNet(target),
    }
end)

-- Where the target is right now (client polls this while riding so it can
-- re-enter after the target swaps cars, e.g. a race respawn).
Admin.Callback('viewTarget', function(src)
    local rec = Viewing[src]
    if not rec or not Admin.Online(rec.target) then return nil end
    return { coords = Admin.Coords(rec.target), veh = vehicleNet(rec.target) }
end)

local function restore(src)
    local rec = Viewing[src]
    if not rec then return end
    Viewing[src] = nil
    if Admin.Online(src) then Admin.SetBucket(src, rec.prevBucket or 0) end
end

Admin.Callback('viewStop', function(src)
    restore(src)
    return true
end)

-- Follow the target across buckets.
CreateThread(function()
    while true do
        Wait(1000)
        for admin, rec in pairs(Viewing) do
            if not Admin.Online(admin) then
                Viewing[admin] = nil
            elseif Admin.Online(rec.target) then
                local want = GetPlayerRoutingBucket(rec.target)
                if GetPlayerRoutingBucket(admin) ~= want then
                    Admin.SetBucket(admin, want)
                    TriggerClientEvent('spz-admin:view:moved', admin, Admin.Coords(rec.target))
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local dropped = source
    Viewing[dropped] = nil
    for admin, rec in pairs(Viewing) do
        if rec.target == dropped then
            TriggerClientEvent('spz-admin:view:gone', admin)
        end
    end
end)
