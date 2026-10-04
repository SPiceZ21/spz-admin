-- client/utils.lua
-- Shared client helpers + the events the server fires at a target player.

Admin = {}

--- Admin callback: `spz-admin:<name>`. The server re-checks the ace on every call.
function Admin.Call(name, ...)
    return lib.callback.await('spz-admin:' .. name, false, ...)
end

function Admin.Notify(description, ntype)
    lib.notify({ title = 'Admin', description = description, type = ntype or 'inform' })
end

-- ── Formatting ───────────────────────────────────────────────────────────────

local function round(n)
    local p = 10 ^ Config.Precision
    return math.floor(n * p + 0.5) / p
end

local function num(n)
    return ('%.' .. Config.Precision .. 'f'):format(round(n))
end

function Admin.Format(kind, c, h)
    if kind == 'vec3'    then return ('vec3(%s, %s, %s)'):format(num(c.x), num(c.y), num(c.z)) end
    if kind == 'vec4'    then return ('vec4(%s, %s, %s, %s)'):format(num(c.x), num(c.y), num(c.z), num(h)) end
    if kind == 'heading' then return num(h) end
    if kind == 'xyz'     then return ('%s, %s, %s'):format(num(c.x), num(c.y), num(c.z)) end
    if kind == 'table'   then return ('{ x = %s, y = %s, z = %s, w = %s }'):format(num(c.x), num(c.y), num(c.z), num(h)) end
    if kind == 'json'    then return json.encode({ x = round(c.x), y = round(c.y), z = round(c.z), w = round(h) }) end
    return ''
end

function Admin.Copy(text, label)
    lib.setClipboard(text)
    Admin.Notify(('Copied %s\n%s'):format(label or '', text), 'success')
end

--- The entity whose position we care about: the car if we're driving it.
function Admin.PositionEntity()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return ped
end

-- ── Teleport ─────────────────────────────────────────────────────────────────

function Admin.Teleport(x, y, z, h)
    local ent = Admin.PositionEntity()
    DoScreenFadeOut(150)
    while not IsScreenFadedOut() do Wait(0) end

    RequestCollisionAtCoord(x, y, z)
    SetEntityCoords(ent, x, y, z, false, false, false, false)
    if h then SetEntityHeading(ent, h) end

    local deadline = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ent) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end

    DoScreenFadeIn(250)
end

function Admin.TeleportWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return Admin.Notify('No waypoint set', 'error') end

    local wp  = GetBlipInfoIdCoord(blip)
    local ent = Admin.PositionEntity()
    DoScreenFadeOut(150)
    while not IsScreenFadedOut() do Wait(0) end

    -- Walk down from the sky until the ground at the waypoint has streamed in.
    for z = 1000.0, 0.0, -25.0 do
        SetEntityCoordsNoOffset(ent, wp.x, wp.y, z, false, false, false)
        RequestCollisionAtCoord(wp.x, wp.y, z)
        Wait(0)
        local found, groundZ = GetGroundZFor_3dCoord(wp.x, wp.y, z, false)
        if found then
            SetEntityCoordsNoOffset(ent, wp.x, wp.y, groundZ + 1.0, false, false, false)
            break
        end
    end

    DoScreenFadeIn(250)
end

-- ── Vehicle helpers ──────────────────────────────────────────────────────────

function Admin.RepairVehicle(veh)
    if veh == 0 then return false end
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleUndriveable(veh, false)
    SetVehicleEngineOn(veh, true, true, false)
    return true
end

function Admin.FlipVehicle(veh)
    if veh == 0 then return false end
    local rot = GetEntityRotation(veh, 2)
    SetEntityRotation(veh, 0.0, 0.0, rot.z, 2, true)
    SetVehicleOnGroundProperly(veh)
    return true
end

--- Heal, and revive if dead.
---
--- Nothing on this server respawns a dead player (spawnmanager is MANUAL and
--- spz-spawn only resurrects inside its own menus), so after death the game is
--- left in its wasted state: screen faded to black, death post-fx running. The
--- old version resurrected the ped but left all of that up, which read as
--- "revive does nothing". Undo it explicitly.
function Admin.Heal()
    local ped = PlayerPedId()
    local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped) or IsPlayerDead(PlayerId())

    if dead then
        local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z + 0.5, h, 0, false)

        -- Resurrect replaces the ped; wait for the new one to be alive.
        local deadline = GetGameTimer() + 2000
        while (IsEntityDead(PlayerPedId()) or IsPlayerDead(PlayerId())) and GetGameTimer() < deadline do
            Wait(0)
        end
        ped = PlayerPedId()
        ClearPedTasksImmediately(ped)
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
    end

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)

    -- The death screen: fade, WASTED post-fx, slow-mo.
    AnimpostfxStopAll()
    StopGameplayCamShaking(true)
    SetTimeScale(1.0)
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(500) end
end

-- ── Events fired at a target by the server ───────────────────────────────────

RegisterNetEvent('spz-admin:teleport', function(c)
    Admin.Teleport(c.x, c.y, c.z, c.w)
end)

RegisterNetEvent('spz-admin:action', function(action)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if action == 'heal' then
        Admin.Heal()
    elseif action == 'kill' then
        SetEntityHealth(ped, 0)
    elseif action == 'repair' then
        Admin.RepairVehicle(veh)
    elseif action == 'flip' then
        Admin.FlipVehicle(veh)
    end
end)

local frozen = false
RegisterNetEvent('spz-admin:freeze', function(state)
    frozen = state
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    FreezeEntityPosition(ped, state)
    if veh ~= 0 then FreezeEntityPosition(veh, state) end
    if state then
        -- Keep them held if they swap vehicles or respawn while frozen.
        CreateThread(function()
            while frozen do
                local p = PlayerPedId()
                FreezeEntityPosition(p, true)
                local v = GetVehiclePedIsIn(p, false)
                if v ~= 0 then FreezeEntityPosition(v, true) end
                DisableControlAction(0, 75, true)   -- exit vehicle
                Wait(0)
            end
        end)
    end
end)
