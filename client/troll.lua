-- client/troll.lua
-- Trolls, run on the TARGET's client: the driver owns their car and the player
-- owns their ped, so this is the only place either can be changed. Whitelisted
-- and logged server-side (server/main.lua → 'troll'). Timed effects undo
-- themselves.
--
-- Input trolls (invert, stuck throttle, possess …) work by disabling a control
-- and feeding the game a replacement value with SetControlNormal, which only
-- takes effect on a control that was disabled first in the same frame.

local function myVehicle()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return 0 end
    -- Passengers don't own the car; ask for it briefly.
    if not NetworkHasControlOfEntity(veh) then
        NetworkRequestControlOfEntity(veh)
        local deadline = GetGameTimer() + 500
        while not NetworkHasControlOfEntity(veh) and GetGameTimer() < deadline do Wait(0) end
    end
    return veh
end

--- Run `tick(ent)` every frame for `seconds`, then `undo(ent)`.
local function timed(ent, seconds, tick, undo)
    CreateThread(function()
        local untilAt = GetGameTimer() + seconds * 1000
        while GetGameTimer() < untilAt and DoesEntityExist(ent) do
            if tick then tick(ent) end
            Wait(0)
        end
        if undo and DoesEntityExist(ent) then undo(ent) end
    end)
end

-- Vehicle controls: steer L/R (+ its split halves), throttle, brake, handbrake.
local VEH_STEER, VEH_LEFT, VEH_RIGHT = 59, 63, 64
local VEH_ACCEL, VEH_BRAKE, VEH_HANDBRAKE = 71, 72, 76
-- On foot: move L/R, move U/D (up = -1), sprint, jump.
local MOVE_LR, MOVE_UD, SPRINT, JUMP = 30, 31, 21, 22

local function disable(...)
    for _, c in ipairs({ ... }) do DisableControlAction(0, c, true) end
end

-- spz-vehfunc keeps every car invincible (it re-protects every 500 ms), so a
-- troll that has to BREAK the car first asks it to stand down on our car for
-- `seconds`, then strips the protection. Godmode resumes by itself afterwards.
local function unprotect(veh, seconds)
    TriggerEvent("spz-admin:godmodePause", math.floor(seconds * 1000))
    SetEntityInvincible(veh, false)
    SetEntityCanBeDamaged(veh, true)
    SetEntityProofs(veh, false, false, false, false, false, false, false, false)
    SetVehicleTyresCanBurst(veh, true)
    SetVehicleCanBeVisiblyDamaged(veh, true)
    SetVehicleEngineCanDegrade(veh, true)
    SetVehicleStrong(veh, false)
end

-- ── Car trolls (need a vehicle) ─────────────────────────────────────────────

local Car = {}

function Car.launch(veh)
    local v = GetEntityVelocity(veh)
    SetEntityVelocity(veh, v.x, v.y, v.z + 28.0)
end

function Car.boost(veh)
    local f = GetEntityForwardVector(veh)
    local speed = GetEntitySpeed(veh) + 45.0
    SetVehicleForwardSpeed(veh, speed)
    SetEntityVelocity(veh, f.x * speed, f.y * speed, GetEntityVelocity(veh).z)
end

function Car.brake(veh)
    SetEntityVelocity(veh, 0.0, 0.0, 0.0)
    SetVehicleForwardSpeed(veh, 0.0)
end

function Car.spin(veh)
    SetEntityAngularVelocity(veh, 0.0, 0.0, 12.0)
end

function Car.upside(veh)
    local c = GetEntityCoords(veh)
    SetEntityCoords(veh, c.x, c.y, c.z + 2.0, false, false, false, false)
    SetEntityRotation(veh, 180.0, 0.0, GetEntityHeading(veh), 2, true)
end

-- Flat for `seconds`, then fixed (godmode never re-inflates tyres itself).
function Car.tires(veh, seconds)
    unprotect(veh, seconds + 1)
    for wheel = 0, 7 do SetVehicleTyreBurst(veh, wheel, true, 1000.0) end
    timed(veh, seconds, nil, function(v)
        for wheel = 0, 7 do SetVehicleTyreFixed(v, wheel) end
    end)
end

function Car.stall(veh, seconds)
    timed(veh, seconds, function(v)
        SetVehicleEngineOn(v, false, true, true)
        SetVehicleUndriveable(v, true)
    end, function(v)
        SetVehicleUndriveable(v, false)
        SetVehicleEngineOn(v, true, true, false)
    end)
end

function Car.eject(veh)
    local ped = PlayerPedId()
    local c = GetEntityCoords(veh)
    ClearPedTasksImmediately(ped)
    SetEntityCoords(ped, c.x, c.y, c.z + 4.0, false, false, false, false)
    SetPedToRagdoll(ped, 2500, 2500, 0, false, false, false)
end

function Car.lockin(veh, seconds)
    SetVehicleDoorsLocked(veh, 4)
    timed(veh, seconds, function() disable(75) end, function(v) SetVehicleDoorsLocked(v, 1) end)
end

function Car.slippery(veh, seconds)
    SetVehicleReduceGrip(veh, true)
    timed(veh, seconds, nil, function(v) SetVehicleReduceGrip(v, false) end)
end

function Car.limiter(veh, seconds)
    -- re-applied every frame: other scripts touch top speed too
    timed(veh, seconds, function(v) SetVehicleMaxSpeed(v, 8.0) end,   -- ~30 km/h
        function(v) SetVehicleMaxSpeed(v, 999.0) end)                 -- uncapped again
end

-- Heavy smoke for `seconds` (the engine still drives), then repaired.
function Car.smoke(veh, seconds)
    unprotect(veh, seconds + 1)
    timed(veh, seconds, function(v) SetVehicleEngineHealth(v, 120.0) end,
        function(v) SetVehicleEngineHealth(v, 1000.0) end)
end

function Car.paint(veh)
    local r = math.random
    SetVehicleCustomPrimaryColour(veh, r(0, 255), r(0, 255), r(0, 255))
    SetVehicleCustomSecondaryColour(veh, r(0, 255), r(0, 255), r(0, 255))
end

function Car.horn(veh, seconds)
    StartVehicleHorn(veh, seconds * 1000, "HELDDOWN", false)
end

function Car.lights(veh, seconds)
    local on, nextFlip = false, 0
    timed(veh, seconds, function(v)
        if GetGameTimer() >= nextFlip then
            nextFlip = GetGameTimer() + 300
            on = not on
            SetVehicleLights(v, on and 2 or 1)
            SetVehicleIndicatorLights(v, 0, on)
            SetVehicleIndicatorLights(v, 1, not on)
        end
    end, function(v)
        SetVehicleLights(v, 0)
        SetVehicleIndicatorLights(v, 0, false)
        SetVehicleIndicatorLights(v, 1, false)
    end)
end

-- Blows the car up. The driver survives: spz-core keeps players invincible,
-- and the blast throws them out.
function Car.explode(veh)
    unprotect(veh, 6)
    SetVehicleEngineHealth(veh, -4000.0)
    SetVehiclePetrolTankHealth(veh, -4000.0)
    NetworkExplodeVehicle(veh, true, false, false)
    local c = GetEntityCoords(veh)
    AddExplosion(c.x, c.y, c.z, 7, 1.0, true, false, 1.0)   -- visuals + push if the net call is ignored
end

function Car.throttle(veh, seconds)
    timed(veh, seconds, function()
        disable(VEH_ACCEL, VEH_BRAKE)
        SetControlNormal(0, VEH_ACCEL, 1.0)
    end)
end

function Car.nobrakes(veh, seconds)
    timed(veh, seconds, function() disable(VEH_BRAKE, VEH_HANDBRAKE) end)
end

function Car.wobble(veh, seconds)
    timed(veh, seconds, function()
        disable(VEH_STEER)
        local raw = GetDisabledControlNormal(0, VEH_STEER)
        local drift = math.sin(GetGameTimer() / 180.0) * 0.7
        SetControlNormal(0, VEH_STEER, math.max(-1.0, math.min(1.0, raw + drift)))
    end)
end

function Car.moon(veh, seconds)
    SetVehicleGravityAmount(veh, 2.0)
    timed(veh, seconds, nil, function(v) SetVehicleGravityAmount(v, 9.8) end)
end

function Car.ghostcar(veh, seconds)
    SetEntityVisible(veh, false, false)
    timed(veh, seconds, nil, function(v) SetEntityVisible(v, true, false) end)
end

function Car.hop(veh, seconds)
    local nextHop = 0
    timed(veh, seconds, function(v)
        if GetGameTimer() >= nextHop and not IsEntityInAir(v) then
            nextHop = GetGameTimer() + 900
            local vel = GetEntityVelocity(v)
            SetEntityVelocity(v, vel.x, vel.y, vel.z + 7.0)
        end
    end)
end

-- ── Player trolls (on foot or in a car) ─────────────────────────────────────

local Ped = {}

--- W <-> S and A <-> D, in a car and on foot.
---   car:     W reverses / brakes, S accelerates, A steers right, D steers left
---   on foot: W walks back, S walks forward, A goes right, D goes left
--- On foot GTA reads movement from BOTH the axes (30/31) and the single-
--- direction keys (32 up, 33 down, 34 left, 35 right), so all of them are
--- taken over — disabling only the axes left the keys working normally.
function Ped.invert(ped, seconds)
    timed(ped, seconds, function()
        if IsPedInAnyVehicle(PlayerPedId(), false) then
            disable(VEH_STEER, VEH_LEFT, VEH_RIGHT, 60, 61, 62, VEH_ACCEL, VEH_BRAKE)
            local steer = GetDisabledControlNormal(0, VEH_STEER)
            local acc   = GetDisabledControlNormal(0, VEH_ACCEL)   -- W
            local brk   = GetDisabledControlNormal(0, VEH_BRAKE)   -- S
            SetControlNormal(0, VEH_STEER, -steer)                 -- A <-> D
            SetControlNormal(0, VEH_ACCEL, brk)                    -- S drives forward
            SetControlNormal(0, VEH_BRAKE, acc)                    -- W brakes / reverses
        else
            disable(MOVE_LR, MOVE_UD, 32, 33, 34, 35)
            local w = GetDisabledControlNormal(0, 32)
            local s = GetDisabledControlNormal(0, 33)
            local a = GetDisabledControlNormal(0, 34)
            local d = GetDisabledControlNormal(0, 35)
            -- axes too, so a controller's stick is flipped as well
            local lr = -GetDisabledControlNormal(0, MOVE_LR)
            local ud = -GetDisabledControlNormal(0, MOVE_UD)
            if w + s + a + d > 0 then lr, ud = a - d, w - s end    -- keys win: W->back, A->right
            SetControlNormal(0, MOVE_LR, lr)
            SetControlNormal(0, MOVE_UD, ud)                       -- up = -1, so W (ud>0) walks back
        end
    end)
end

function Ped.drunk(ped, seconds)
    ShakeGameplayCam('DRUNK_SHAKE', 2.0)
    SetTimecycleModifier('Drunk')
    SetTimecycleModifierStrength(0.8)
    timed(ped, seconds, function()
        if IsPedInAnyVehicle(PlayerPedId(), false) then
            disable(VEH_STEER)
            local raw = GetDisabledControlNormal(0, VEH_STEER)
            SetControlNormal(0, VEH_STEER, math.max(-1.0, math.min(1.0, raw + math.sin(GetGameTimer() / 400.0) * 0.45)))
        end
    end, function()
        StopGameplayCamShaking(true)
        ClearTimecycleModifier()
    end)
end

function Ped.lookback(ped, seconds)
    timed(ped, seconds, function() SetGameplayCamRelativeHeading(180.0) end)
end

function Ped.blind(_, seconds)
    CreateThread(function()
        DoScreenFadeOut(400)
        Wait(math.min(seconds, 8) * 1000)   -- capped: a blind driver is enough
        DoScreenFadeIn(600)
    end)
end

function Ped.ragdoll(ped)
    if IsPedInAnyVehicle(ped, false) then Car.eject(GetVehiclePedIsIn(ped, false)); return end
    SetPedToRagdoll(ped, 4000, 4000, 0, false, false, false)
end

function Ped.fling(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then Car.eject(veh); ped = PlayerPedId() end
    SetPedToRagdoll(ped, 4000, 4000, 0, false, false, false)
    SetEntityVelocity(ped, math.random(-20, 20) + 0.0, math.random(-20, 20) + 0.0, 25.0)
end

-- On fire for a few seconds. spz-core's invincibility is paused just long
-- enough to ignite; its health top-up keeps running, so they never die.
function Ped.fire(ped, seconds)
    local secs = math.min(seconds, 8)
    TriggerEvent("spz-admin:pedDamagePause", math.floor(secs * 1000))
    SetEntityInvincible(ped, false)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    if IsPedInAnyVehicle(ped, false) then Car.eject(GetVehiclePedIsIn(ped, false)); ped = PlayerPedId() end
    StartEntityFire(ped)
    timed(ped, secs, function(p)
        if not IsEntityOnFire(p) then StartEntityFire(p) end
    end, function(p)
        StopEntityFire(p)
        SetEntityInvincible(p, true)
    end)
end

RegisterNetEvent('spz-admin:troll', function(action, seconds)
    seconds = tonumber(seconds) or Config.Troll.duration
    if Car[action] then
        local veh = myVehicle()
        if veh ~= 0 then Car[action](veh, seconds) end
    elseif Ped[action] then
        Ped[action](PlayerPedId(), seconds)
    end
end)

-- ── Possess: being driven (target side) ─────────────────────────────────────
-- The admin's input arrives ~15 times a second and is replayed every frame in
-- place of our own. If it stops arriving (admin lagged out) the car coasts on
-- neutral input rather than holding the last key down forever.

local possessed = false
local remote = nil          -- { x, fwd, back, hb, jump, sprint }
local remoteAt = 0

RegisterNetEvent('spz-admin:possessInput', function(input)
    if not possessed then return end
    remote, remoteAt = input, GetGameTimer()
end)

RegisterNetEvent('spz-admin:possessed', function(state)
    possessed = state == true
    remote = nil
    if not possessed then return end

    CreateThread(function()
        while possessed do
            local inp = (remote and GetGameTimer() - remoteAt < 1000) and remote or {}
            local x    = tonumber(inp.x) or 0.0
            local fwd  = tonumber(inp.fwd) or 0.0
            local back = tonumber(inp.back) or 0.0

            disable(75)   -- no getting out of it either
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                disable(VEH_STEER, VEH_LEFT, VEH_RIGHT, 60, 61, 62, VEH_ACCEL, VEH_BRAKE, VEH_HANDBRAKE)
                SetControlNormal(0, VEH_STEER, x)
                SetControlNormal(0, VEH_ACCEL, fwd)
                SetControlNormal(0, VEH_BRAKE, back)
                SetControlNormal(0, VEH_HANDBRAKE, inp.hb and 1.0 or 0.0)
            else
                disable(MOVE_LR, MOVE_UD, 32, 33, 34, 35, SPRINT, JUMP)
                SetControlNormal(0, MOVE_LR, x)
                SetControlNormal(0, MOVE_UD, back - fwd)
                if inp.sprint then SetControlNormal(0, SPRINT, 1.0) end
                if inp.jump then SetControlNormal(0, JUMP, 1.0) end
            end
            Wait(0)
        end
    end)
end)

-- ── Possess: driving (admin side) ───────────────────────────────────────────
-- Spectates the target (any bucket) and sends our WASD to them. Stops with the
-- spectate (Backspace), when switching target, or from the menu.

local possessing = nil   -- target server id

function Admin.IsPossessing() return possessing end

function Admin.StopPossess()
    if not possessing then return end
    possessing = nil
    lib.hideTextUI()
    Admin.Call('unpossess')
    Admin.Notify('Possession ended')
end

function Admin.StartPossess(id, list)
    if possessing then Admin.StopPossess() end

    if Admin.ViewTarget() ~= id then Admin.StartView(id, 'spectate', list) end
    if Admin.ViewTarget() ~= id then return end

    local ok, msg = Admin.Call('possess', id)
    if not ok then return Admin.Notify(msg or "Can't possess that player", 'error') end
    possessing = id
    lib.showTextUI('Possessing  \n[WASD] drive  [Space] handbrake / jump  [Shift] sprint  [Backspace] stop',
        { position = 'left-center', icon = 'ghost' })

    CreateThread(function()
        local last, lastSent = nil, 0
        while possessing == id do
            -- Spectate ended or moved to someone else: we're not driving them.
            if Admin.ViewTarget() ~= id then Admin.StopPossess(); break end

            disable(30, 31, 32, 33, 34, 35, 21, 22, 44, 36)
            local l = IsDisabledControlPressed(0, 34) and 1.0 or 0.0
            local r = IsDisabledControlPressed(0, 35) and 1.0 or 0.0
            local input = {
                x      = r - l,
                fwd    = IsDisabledControlPressed(0, 32) and 1.0 or 0.0,
                back   = IsDisabledControlPressed(0, 33) and 1.0 or 0.0,
                hb     = IsDisabledControlPressed(0, 22),
                jump   = IsDisabledControlPressed(0, 22),
                sprint = IsDisabledControlPressed(0, 21),
            }

            -- On change, plus a keep-alive; capped at ~15/s.
            local key = ('%.0f|%.0f|%.0f|%s|%s'):format(input.x, input.fwd, input.back, tostring(input.hb), tostring(input.sprint))
            local now = GetGameTimer()
            if (key ~= last and now - lastSent > 66) or now - lastSent > 400 then
                TriggerServerEvent('spz-admin:possessInput', input)
                last, lastSent = key, now
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('spz-admin:possessEnded', function()
    if possessing then
        possessing = nil
        lib.hideTextUI()
        Admin.Notify('Possessed player left', 'warning')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    possessed = false
    if possessing then possessing = nil; lib.hideTextUI() end
end)
