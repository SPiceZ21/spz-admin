-- client/view.lua
-- Spectate or ride along with any player, in any routing bucket.
--
--   spectate  engine spectator cam on the target.
--   ride      sit in a free seat of the target's car (your own gameplay cam, so
--             you can look around). Falls back to the spectator cam while the
--             target is on foot or their car is full, and re-enters when they
--             get a new car (race respawn, etc).
--
-- The server moves us into the target's bucket and keeps us following it. Our
-- ped is hidden, collision-less and kept just under the target so they never
-- drop out of scope, however fast they're going.

local view       = nil   -- { id, name, mode, list = {ids}, idx }
local back       = nil   -- { coords, heading } to restore on stop
local specOn     = false
local seatedIn   = 0

local function targetPed(id)
    local p = GetPlayerFromServerId(id)
    if p == -1 then return 0 end
    local ped = GetPlayerPed(p)
    return (ped ~= 0 and DoesEntityExist(ped)) and ped or 0
end

local function setSpectate(on, ped)
    if on then
        if ped ~= 0 then
            NetworkSetInSpectatorMode(true, ped)
            specOn = true
        end
    elseif specOn then
        NetworkSetInSpectatorMode(false, PlayerPedId())
        specOn = false
    end
end

local function leaveSeat()
    local me = PlayerPedId()
    if seatedIn ~= 0 or IsPedInAnyVehicle(me, false) then
        local c = GetEntityCoords(me)
        ClearPedTasksImmediately(me)
        SetEntityCoords(me, c.x, c.y, c.z + 3.0, false, false, false, false)
    end
    seatedIn = 0
end

local function hideSelf(hidden)
    local me = PlayerPedId()
    if Config.HideWhileViewing then SetEntityVisible(me, not hidden, false) end
    SetEntityCollision(me, not hidden, not hidden)
    SetEntityInvincible(me, hidden)
    SetPedConfigFlag(me, 184, hidden)   -- no shuffling into the driver seat
    FreezeEntityPosition(me, hidden)
end

local function textUI()
    if not view then return lib.hideTextUI() end
    lib.showTextUI(('%s [%d] · %s  \n[←/→] switch  [↑] %s  [Backspace] stop')
        :format(view.name, view.id, view.mode == 'ride' and 'Riding' or 'Spectating',
            view.mode == 'ride' and 'spectate' or 'ride along'),
        { position = 'top-center', icon = view.mode == 'ride' and 'car' or 'eye' })
end

-- Try to sit in the target's car. Returns true if seated.
local function trySeat(tped)
    if tped == 0 then return false end
    local veh = GetVehiclePedIsIn(tped, false)
    if veh == 0 then return false end

    local me = PlayerPedId()
    if GetVehiclePedIsIn(me, false) == veh then seatedIn = veh; return true end

    for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        if IsVehicleSeatFree(veh, seat) then
            FreezeEntityPosition(me, false)
            SetPedIntoVehicle(me, veh, seat)
            seatedIn = veh
            return true
        end
    end
    return false
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

local function attach(id, mode)
    if Admin.StopNoclip then Admin.StopNoclip() end

    local res = Admin.Call('view', id, mode)
    if not res then
        Admin.Notify("Can't view that player", 'error')
        return false
    end

    local first = view == nil
    if first then
        local me = PlayerPedId()
        back = { coords = GetEntityCoords(me), heading = GetEntityHeading(me) }
        hideSelf(true)
    end

    leaveSeat()
    setSpectate(false)

    view = view or {}
    view.id, view.name, view.mode = id, res.name, mode

    if res.coords then
        SetEntityCoords(PlayerPedId(), res.coords.x, res.coords.y, res.coords.z - 8.0, false, false, false, false)
    end
    FreezeEntityPosition(PlayerPedId(), true)

    -- Wait for the target to stream in after the bucket move.
    local deadline, tped = GetGameTimer() + 6000, 0
    while GetGameTimer() < deadline do
        tped = targetPed(id)
        if tped ~= 0 then break end
        Wait(50)
    end
    if tped == 0 then Admin.Notify('Target not streamed in yet — waiting', 'warning') end

    if not (mode == 'ride' and trySeat(tped)) then setSpectate(true, tped) end
    textUI()
    return true
end

function Admin.StopView()
    if not view then return end
    if Admin.StopPossess then Admin.StopPossess() end
    view = nil
    lib.hideTextUI()

    setSpectate(false)
    leaveSeat()
    Admin.Call('viewStop')

    hideSelf(false)
    if back then
        Admin.Teleport(back.coords.x, back.coords.y, back.coords.z, back.heading)
        back = nil
    end
end

function Admin.IsViewing() return view ~= nil end
function Admin.ViewTarget() return view and view.id end

--- Start spectating / riding. `list` is the ordered player ids to cycle through.
function Admin.StartView(id, mode, list)
    if not attach(id, mode) then return end
    view.list = list or { id }
    view.idx = 1
    for i, v in ipairs(view.list) do if v == id then view.idx = i end end
end

local function cycle(delta)
    if not view or #view.list < 2 then return end
    local n = #view.list
    for _ = 1, n do
        view.idx = ((view.idx - 1 + delta) % n) + 1
        local id = view.list[view.idx]
        if id ~= GetPlayerServerId(PlayerId()) and attach(id, view.mode) then return end
    end
end

-- ── Loops ────────────────────────────────────────────────────────────────────

-- Input
CreateThread(function()
    while true do
        if view then
            DisableControlAction(0, 75, true)    -- exit vehicle
            DisableControlAction(0, 24, true)    -- attack
            DisableControlAction(0, 25, true)    -- aim
            DisableControlAction(0, 140, true)   -- melee
            if IsControlJustPressed(0, 175) then cycle(1)
            elseif IsControlJustPressed(0, 174) then cycle(-1)
            elseif IsControlJustPressed(0, 172) then
                attach(view.id, view.mode == 'ride' and 'spectate' or 'ride')
            elseif IsControlJustPressed(0, 194) then
                Admin.StopView()
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Keep our ped glued under the target (spectate) / keep us in their car (ride).
CreateThread(function()
    while true do
        if view then
            local tped = targetPed(view.id)
            local me   = PlayerPedId()

            if view.mode == 'ride' then
                local tveh = tped ~= 0 and GetVehiclePedIsIn(tped, false) or 0
                if tveh ~= 0 and GetVehiclePedIsIn(me, false) == tveh then
                    if specOn then setSpectate(false) end
                else
                    if seatedIn ~= 0 then leaveSeat(); FreezeEntityPosition(me, true) end
                    if not trySeat(tped) and not specOn then setSpectate(true, tped) end
                end
            elseif tped ~= 0 and not specOn then
                setSpectate(true, tped)
            end

            if seatedIn == 0 then
                -- Target out of scope: ask the server where they are.
                local c
                if tped ~= 0 then
                    c = GetEntityCoords(tped)
                else
                    local t = Admin.Call('viewTarget')
                    c = t and t.coords
                end
                if c then SetEntityCoordsNoOffset(me, c.x, c.y, c.z - 8.0, false, false, false) end
            end

            Wait(seatedIn == 0 and 200 or 500)
        else
            Wait(500)
        end
    end
end)

-- Target details overlay.
CreateThread(function()
    while true do
        if view then
            local tped = targetPed(view.id)
            local lines = { ('~b~%s~s~ [%d]'):format(view.name, view.id) }
            if tped ~= 0 then
                local veh = GetVehiclePedIsIn(tped, false)
                local ent = veh ~= 0 and veh or tped
                lines[#lines + 1] = ('%d km/h · HP %d'):format(math.floor(GetEntitySpeed(ent) * 3.6), GetEntityHealth(tped))
                if veh ~= 0 then
                    lines[#lines + 1] = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
                end
            else
                lines[#lines + 1] = '~o~out of scope~s~'
            end

            SetTextFont(4)
            SetTextScale(0.0, 0.42)
            SetTextOutline()
            SetTextColour(255, 255, 255, 230)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(table.concat(lines, '~n~'))
            EndTextCommandDisplayText(0.015, 0.70)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('spz-admin:view:moved', function(c)
    if not view or not c then return end
    if seatedIn == 0 then
        SetEntityCoordsNoOffset(PlayerPedId(), c.x, c.y, c.z - 8.0, false, false, false)
    end
    setSpectate(false)   -- re-acquired on the next follow tick
end)

RegisterNetEvent('spz-admin:view:gone', function()
    if not view then return end
    Admin.Notify(('%s left the server'):format(view.name), 'warning')
    local gone = view.id
    for i, v in ipairs(view.list) do
        if v == gone then table.remove(view.list, i); break end
    end
    if #view.list == 0 then return Admin.StopView() end
    view.idx = math.min(view.idx, #view.list)
    if not attach(view.list[view.idx], view.mode) then Admin.StopView() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and view then
        setSpectate(false)
        leaveSeat()
        hideSelf(false)
        lib.hideTextUI()
    end
end)
