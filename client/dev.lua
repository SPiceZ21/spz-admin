-- client/dev.lua
-- Developer tools: coordinate copy, live coords overlay, entity inspector.

Admin.Dev = { overlay = false, inspector = false }

function Admin.CopyCoords(kind)
    local ent = Admin.PositionEntity()
    local c, h = GetEntityCoords(ent), GetEntityHeading(ent)
    Admin.Copy(Admin.Format(kind, c, h), kind)
end

function Admin.CopyCamera()
    local c, r = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    Admin.Copy(('coords = %s, rot = vec3(%.2f, %.2f, %.2f), fov = %.1f')
        :format(Admin.Format('vec3', c), r.x, r.y, r.z, GetFinalRenderedCamFov()), 'camera')
end

--- Spawn code of the car you are in (what /car, the spawner and the poll use).
--- spz-vehicles tags every car it spawns with its real model name; the game's
--- display name is only a fallback, because it is often not the spawn code
--- (add-ons read "CARNOTFOUND", many vanilla cars differ).
function Admin.CopyVehicle()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return Admin.Notify('Not in a vehicle', 'error') end
    local code = Entity(veh).state.modelName
    if type(code) ~= 'string' or code == '' then
        local name = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
        code = (name and name ~= 'CARNOTFOUND') and name or tostring(GetEntityModel(veh))
    end
    Admin.Copy(code:lower(), 'spawn code')
end

local function draw(text, x, y, scale)
    SetTextFont(4)
    SetTextScale(0.0, scale or 0.38)
    SetTextOutline()
    SetTextColour(255, 255, 255, 235)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

-- ── Coords overlay ───────────────────────────────────────────────────────────

function Admin.ToggleOverlay()
    Admin.Dev.overlay = not Admin.Dev.overlay
    if not Admin.Dev.overlay then return end

    CreateThread(function()
        while Admin.Dev.overlay do
            local ent = Admin.PositionEntity()
            local c, h = GetEntityCoords(ent), GetEntityHeading(ent)
            local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(c.x, c.y, c.z))
            local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
            draw(('~y~X~s~ %.2f  ~y~Y~s~ %.2f  ~y~Z~s~ %.2f  ~y~H~s~ %.2f~n~%s, %s · %d km/h · interior %d')
                :format(c.x, c.y, c.z, h, street, zone,
                    math.floor(GetEntitySpeed(ent) * 3.6), GetInteriorFromEntity(ent)), 0.40, 0.955, 0.36)
            Wait(0)
        end
    end)
end

-- ── Entity inspector ─────────────────────────────────────────────────────────
-- Aim at anything: [E] copy its vec4 · [G] copy model · [DEL] delete it.

local TYPES = { [1] = 'Ped', [2] = 'Vehicle', [3] = 'Object' }

local function modelName(ent)
    local model = GetEntityModel(ent)
    if IsModelAVehicle(model) then return GetDisplayNameFromVehicleModel(model):lower() end
    return tostring(model)
end

local function deleteEntity(ent)
    if IsPedAPlayer(ent) then return Admin.Notify("Can't delete a player", 'error') end
    NetworkRequestControlOfEntity(ent)
    local deadline = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(ent)
        Wait(0)
    end
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)
    Admin.Notify(DoesEntityExist(ent) and 'Could not take control of entity' or 'Entity deleted',
        DoesEntityExist(ent) and 'error' or 'success')
end

function Admin.ToggleInspector()
    Admin.Dev.inspector = not Admin.Dev.inspector
    if not Admin.Dev.inspector then return lib.hideTextUI() end

    lib.showTextUI('Inspector  \n[E] copy vec4  [G] copy model  [DEL] delete', { position = 'right-center', icon = 'magnifying-glass' })

    CreateThread(function()
        while Admin.Dev.inspector do
            local hit, ent, endCoords = lib.raycast.fromCamera(511, 4, 60.0)
            local origin = GetEntityCoords(PlayerPedId())

            if hit then
                DrawLine(origin.x, origin.y, origin.z, endCoords.x, endCoords.y, endCoords.z, 255, 120, 0, 200)
                DrawMarker(28, endCoords.x, endCoords.y, endCoords.z, 0, 0, 0, 0, 0, 0, 0.08, 0.08, 0.08, 255, 120, 0, 200, false, false, 2, false, nil, nil, false)
            end

            local etype = (hit and ent and ent ~= 0 and DoesEntityExist(ent)) and GetEntityType(ent) or 0
            if etype ~= 0 then
                local c, h = GetEntityCoords(ent), GetEntityHeading(ent)
                local model = GetEntityModel(ent)
                local net = NetworkGetEntityIsNetworked(ent) and NetworkGetNetworkIdFromEntity(ent) or 'local'
                local owner = NetworkGetEntityOwner(ent)
                SetEntityDrawOutline(ent, true)
                draw(('~o~%s~s~ %s~n~hash %d · net %s · owner %s~n~%s  h %.2f~n~health %d')
                    :format(TYPES[etype], modelName(ent), model, net,
                        owner ~= -1 and GetPlayerServerId(owner) or '-',
                        Admin.Format('vec3', c), h, GetEntityHealth(ent)), 0.52, 0.52, 0.34)

                if IsControlJustPressed(0, 38) then
                    Admin.Copy(Admin.Format('vec4', c, h), 'entity vec4')
                elseif IsControlJustPressed(0, 47) then
                    Admin.Copy(('%s (%d)'):format(modelName(ent), model), 'model')
                elseif IsControlJustPressed(0, 178) then
                    deleteEntity(ent)
                end
                Wait(0)
                SetEntityDrawOutline(ent, false)
            elseif hit then
                draw(('%s'):format(Admin.Format('vec3', endCoords)), 0.52, 0.52, 0.34)
                if IsControlJustPressed(0, 38) then
                    Admin.Copy(Admin.Format('vec3', endCoords), 'surface vec3')
                end
                Wait(0)
            else
                Wait(0)
            end
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        Admin.Dev.overlay, Admin.Dev.inspector = false, false
    end
end)
