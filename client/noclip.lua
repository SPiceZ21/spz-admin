-- client/noclip.lua
-- Camera-relative fly mode. Moves the car too when you're driving.
--   W/S forward/back · A/D strafe · Space/Ctrl up/down
--   Shift fast · Alt slow · scroll wheel cycles speed

local active   = false
local speedIdx = Config.Noclip.default

local function setGhost(ent, on)
    SetEntityCollision(ent, not on, not on)
    FreezeEntityPosition(ent, on)
    SetEntityInvincible(ent, on)
    SetEntityVisible(ent, not on, false)
    if ent ~= PlayerPedId() then SetEntityVisible(PlayerPedId(), not on, false) end
end

function Admin.StopNoclip()
    if not active then return end
    active = false
    local ent = Admin.PositionEntity()
    setGhost(ent, false)
    if ent ~= PlayerPedId() then setGhost(PlayerPedId(), false) end
    SetEntityVelocity(ent, 0.0, 0.0, 0.0)
    lib.hideTextUI()
end

function Admin.IsNoclip() return active end

function Admin.ToggleNoclip()
    if active then return Admin.StopNoclip() end
    if Admin.IsViewing and Admin.IsViewing() then return Admin.Notify('Stop spectating first', 'error') end

    active = true
    CreateThread(function()
        local ent = Admin.PositionEntity()
        setGhost(ent, true)

        while active do
            local cur = Admin.PositionEntity()
            if cur ~= ent then setGhost(ent, false); ent = cur; setGhost(ent, true) end

            for _, c in ipairs({ 30, 31, 32, 33, 34, 35, 21, 36, 19, 22, 44, 85, 14, 15, 16, 17, 24, 25, 71, 72 }) do
                DisableControlAction(0, c, true)
            end

            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then
                speedIdx = math.min(speedIdx + 1, #Config.Noclip.speeds)
            elseif IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then
                speedIdx = math.max(speedIdx - 1, 1)
            end

            local speed = Config.Noclip.speeds[speedIdx]
            if IsDisabledControlPressed(0, 21) then speed = speed * Config.Noclip.fast end
            if IsDisabledControlPressed(0, 19) then speed = speed * Config.Noclip.slow end

            local rot = GetGameplayCamRot(2)
            local rz, rx = math.rad(rot.z), math.rad(rot.x)
            local fwd   = vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
            local right = vec3(math.cos(rz), math.sin(rz), 0.0)

            local move = vec3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) then move = move + fwd end
            if IsDisabledControlPressed(0, 33) then move = move - fwd end
            if IsDisabledControlPressed(0, 35) then move = move + right end
            if IsDisabledControlPressed(0, 34) then move = move - right end
            if IsDisabledControlPressed(0, 22) then move = move + vec3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 36) then move = move - vec3(0.0, 0.0, 1.0) end

            local pos = GetEntityCoords(ent) + move * speed
            SetEntityCoordsNoOffset(ent, pos.x, pos.y, pos.z, true, true, true)
            SetEntityHeading(ent, rot.z)

            Wait(0)
        end
    end)

    lib.showTextUI('Noclip  \n[WASD] move  [Space/Ctrl] up/down  [Shift/Alt] speed  [Scroll] gear',
        { position = 'left-center', icon = 'feather' })
end

RegisterCommand('noclip', function()
    if not Admin.Call('isAdmin') then return end
    Admin.ToggleNoclip()
end, false)
RegisterKeyMapping('noclip', 'Admin: toggle noclip', 'keyboard', Config.NoclipKey)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Admin.StopNoclip() end
end)
