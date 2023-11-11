-- Variables

local meterIsOpen = false
local meterActive = false
local lastLocation = nil
local mouseActive = false

-- used for polyzones
local isInsidePickupZone = false
local isInsideDropZone = false
local isPlayerInsideCabZone = false
local isPlayerInsideBossZone = false

local meterData = {
    fareAmount = 6,
    currentFare = 0,
    distanceTraveled = 0
}

local NpcData = {
    Active = false,
    CurrentNpc = nil,
    LastNpc = nil,
    CurrentDeliver = nil,
    LastDeliver = nil,
    Npc = nil,
    NpcBlip = nil,
    DeliveryBlip = nil,
    NpcTaken = false,
    NpcDelivered = false,
    CountDown = 180
}

local taxiPed = nil

local function setupTarget()
    CreateThread(function()
        lib.requestModel(`a_m_m_indian_01`)
        taxiPed = CreatePed(3, `a_m_m_indian_01`, 901.34, -170.06, 74.08 - 1.0, 228.81, false, true)
        SetBlockingOfNonTemporaryEvents(taxiPed, true)
        TaskPlayAnim(taxiPed, 'abigail_mcs_1_concat-0', 'csb_abigail_dual-0', 8.0, 8.0, -1, 1, 0, false, false, false)
        TaskStartScenarioInPlace(taxiPed, 'WORLD_HUMAN_AA_COFFEE', 0, false)
        FreezeEntityPosition(taxiPed, true)
        SetEntityInvincible(taxiPed, true)
        exports.ox_target:addLocalEntity(taxiPed, {
            {
                type = 'client',
                event = 'qb-taxijob:client:requestcab',
                icon = 'fas fa-sign-in-alt',
                label = Lang:t('info.request_taxi'),
                job = 'taxi',
            }
        })
    end)
end

local function resetNpcTask()
    NpcData = {
        Active = false,
        CurrentNpc = nil,
        LastNpc = nil,
        CurrentDeliver = nil,
        LastDeliver = nil,
        Npc = nil,
        NpcBlip = nil,
        DeliveryBlip = nil,
        NpcTaken = false,
        NpcDelivered = false
    }
end

local function resetMeter()
    meterData = {
        fareAmount = 6,
        currentFare = 0,
        distanceTraveled = 0
    }
end

local function whitelistedVehicle()
    local veh = GetEntityModel(cache.vehicle)
    local retval = false

    for i = 1, #Config.AllowedVehicles, 1 do
        if veh == joaat(Config.AllowedVehicles[i].model) then
            retval = true
        end
    end

    if veh == `dynasty` then
        retval = true
    end

    return retval
end

local function isDriver()
    return cache.seat == -1
end

local zone
local delieveryZone

local function getDeliveryLocation()
    NpcData.CurrentDeliver = math.random(1, #Config.NPCLocations.DeliverLocations)
    if NpcData.LastDeliver then
        while NpcData.LastDeliver ~= NpcData.CurrentDeliver do
            NpcData.CurrentDeliver = math.random(1, #Config.NPCLocations.DeliverLocations)
        end
    end

    if NpcData.DeliveryBlip then
        RemoveBlip(NpcData.DeliveryBlip)
    end
    NpcData.DeliveryBlip = AddBlipForCoord(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z)
    SetBlipColour(NpcData.DeliveryBlip, 3)
    SetBlipRoute(NpcData.DeliveryBlip, true)
    SetBlipRouteColour(NpcData.DeliveryBlip, 3)
    NpcData.LastDeliver = NpcData.CurrentDeliver
    if not Config.UseTarget then -- added checks to disable distance checking if polyzone option is used
        CreateThread(function()
            while true do
                local pos = GetEntityCoords(cache.ped)
                local dist = #(pos - vec3(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z))
                if dist < 20 then
                    DrawMarker(2, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 255, 255, 255, 255, false, false, 0, true, nil, nil, false)
                    if dist < 5 then
                        DrawText3D(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z, Lang:t('info.drop_off_npc'))
                        if IsControlJustPressed(0, 38) then
                            TaskLeaveVehicle(NpcData.Npc, cache.vehicle, 0)
                            SetEntityAsMissionEntity(NpcData.Npc, false, true)
                            SetEntityAsNoLongerNeeded(NpcData.Npc)
                            local targetCoords = Config.NPCLocations.TakeLocations[NpcData.LastNpc]
                            TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, 0.0, 0.0)
                            SendNUIMessage({
                                action = 'toggleMeter'
                            })
                            TriggerServerEvent('qb-taxi:server:NpcPay', meterData.currentFare)
                            meterActive = false
                            SendNUIMessage({
                                action = 'resetMeter'
                            })
                            exports.qbx_core:Notify(Lang:t('info.person_was_dropped_off'), 'success')
                            if NpcData.DeliveryBlip then
                                RemoveBlip(NpcData.DeliveryBlip)
                            end
                            local RemovePed = function(p)
                                SetTimeout(60000, function()
                                    DeletePed(p)
                                end)
                            end
                            RemovePed(NpcData.Npc)
                            resetNpcTask()
                            break
                        end
                    end
                end
                Wait(0)
            end
        end)
    end
end

local function callNpcPoly()
    CreateThread(function()
        while not NpcData.NpcTaken do
            if isInsidePickupZone then
                if IsControlJustPressed(0, 38) then
                    lib.hideTextUI()
                    local veh = cache.vehicle
                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(veh), 0

                    for i= maxSeats - 1, 0, -1 do
                        if IsVehicleSeatFree(veh, i) then
                            freeSeat = i
                            break
                        end
                    end

                    meterIsOpen = true
                    meterActive = true
                    lastLocation = GetEntityCoords(cache.ped)
                    SendNUIMessage({
                        action = 'openMeter',
                        toggle = true,
                        meterData = Config.Meter
                    })
                    SendNUIMessage({
                        action = 'toggleMeter'
                    })
                    ClearPedTasksImmediately(NpcData.Npc)
                    FreezeEntityPosition(NpcData.Npc, false)
                    TaskEnterVehicle(NpcData.Npc, veh, -1, freeSeat, 1.0, 0)
                    exports.qbx_core:Notify(Lang:t('info.go_to_location'), 'inform')
                    if NpcData.NpcBlip then
                        RemoveBlip(NpcData.NpcBlip)
                    end
                    getDeliveryLocation()
                    NpcData.NpcTaken = true
                    createNpcDelieveryLocation()
                    zone:remove()
                    lib.hideTextUI()
                end
            end
            Wait(0)
        end
    end)
end

local function onEnterCallZone()
    if whitelistedVehicle() and not isInsidePickupZone and not NpcData.NpcTaken then
        isInsidePickupZone = true
        lib.showTextUI(Lang:t('info.call_npc'), {position = 'left-center'})
        callNpcPoly()
    end
end

local function onExitCallZone()
    lib.hideTextUI()
    isInsidePickupZone = false
end

local function createNpcPickUpLocation()
    zone = lib.zones.box({
        coords = Config.PZLocations.TakeLocations[NpcData.CurrentNpc].coord,
        size = vec3(Config.PZLocations.TakeLocations[NpcData.CurrentNpc].height, Config.PZLocations.TakeLocations[NpcData.CurrentNpc].width, (Config.PZLocations.TakeLocations[NpcData.CurrentNpc].maxZ - Config.PZLocations.TakeLocations[NpcData.CurrentNpc].minZ)),
        rotation = Config.PZLocations.TakeLocations[NpcData.CurrentNpc].heading,
        debug = Config.PolyDebug,
        onEnter = onEnterCallZone,
        onExit = onExitCallZone
    })
end



local function enumerateEntitiesWithinDistance(entities, isPlayerEntities, coords, maxDistance)
	local nearbyEntities = {}
	if coords then
		coords = vec3(coords.x, coords.y, coords.z)
	else
		coords = GetEntityCoords(cache.ped)
	end
	for k, entity in pairs(entities) do
		local distance = #(coords - GetEntityCoords(entity))
		if distance <= maxDistance then
			nearbyEntities[#nearbyEntities + 1] = isPlayerEntities and k or entity
		end
	end
	return nearbyEntities
end

local function getVehiclesInArea(coords, maxDistance) -- Vehicle inspection in designated area
	return enumerateEntitiesWithinDistance(GetGamePool('CVehicle'), false, coords, maxDistance)
end

local function isSpawnPointClear(coords, maxDistance) -- Check the spawn point to see if it's empty or not:
	return #getVehiclesInArea(coords, maxDistance) == 0
end

local function getVehicleSpawnPoint()
    local near = nil
	local distance = 10000
	for k, v in pairs(Config.CabSpawns) do
        if isSpawnPointClear(vec3(v.x, v.y, v.z), 2.5) then
            local pos = GetEntityCoords(cache.ped)
            local cur_distance = #(pos - vec3(v.x, v.y, v.z))
            if cur_distance < distance then
                distance = cur_distance
                near = k
            end
        end
    end
	return near
end

local function calculateFareAmount()
    if meterIsOpen and meterActive then
        local startPos = lastLocation
        local newPos = GetEntityCoords(cache.ped)
        if startPos ~= newPos then
            local newDistance = #(startPos - newPos)
            lastLocation = newPos

            meterData['distanceTraveled'] += (newDistance / 1609)

            local fareAmount = ((meterData['distanceTraveled']) * Config.Meter.defaultPrice) + Config.Meter.startingPrice
            meterData['currentFare'] = math.floor(fareAmount)

            SendNUIMessage({
                action = 'updateMeter',
                meterData = meterData
            })
        end
    end
end

local function onEnterCabBossZone()
    if QBX.PlayerData.job.name ~= 'taxi' and QBX.PlayerData.job.isboss and Config.UseTarget then return end
    isPlayerInsideBossZone = true
    CreateThread(function()
        while isPlayerInsideBossZone do
            local pos = GetEntityCoords(cache.ped)
            if #(pos - Config.BossMenu) < 2.0 then
                DrawText3D(Config.BossMenu.x, Config.BossMenu.y, Config.BossMenu.z, Lang:t('menu.boss_menu'))
                if IsControlJustReleased(0, 38) then
                    TriggerEvent('qb-bossmenu:client:OpenMenu')
                end
            end
            Wait(0)
        end
    end)
end

local function onExitCabBossZone()
    lib.hideTextUI()
    isPlayerInsideBossZone = false
end

local function setupCabBossLocation()
    lib.zones.box({
        coords = vec3(Config.BossMenu.x, Config.BossMenu.y, Config.BossMenu.z),
        size = vec3(2.5, 2.5, 2.5),
        rotation = 45,
        debug = Config.PolyDebug,
        onEnter = onEnterCabBossZone,
        onExit = onExitCabBossZone
    })
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or table.type(QBX.PlayerData) == 'empty' or not Config.UseTarget then return end
    if Config.UseTarget then
        DeletePed(taxiPed)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or table.type(QBX.PlayerData) == 'empty' or not Config.UseTarget then return end
    if LocalPlayer.state.isLoggedIn then
        if QBX.PlayerData.job.name == 'taxi' then
            setupCabParkingLocation()
            if QBX.PlayerData.job.isboss then
                setupCabBossLocation()
            end
        end
    end
    if Config.UseTarget then
        setupTarget()
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if Config.UseTarget then
        setupTarget()
    end
    if QBX.PlayerData.job.name == 'taxi' then

        setupCabParkingLocation()
        if QBX.PlayerData.job.isboss then
            setupCabBossLocation()
        end
    end
end)

local function taxiGarage()
    local registeredMenu = {
        id = 'garages_depotlist',
        title = Lang:t('menu.taxi_menu_header'),
        options = {}
    }
    local options = {}
    for _, v in pairs(Config.AllowedVehicles) do

        options[#options + 1] = {
            title = v.label,
            description = Lang:t('info.take_vehicle', { model = v.label }),
            event = 'qb-taxi:client:TakeVehicle',
            args = {model = v.model}
        }
    end
    if QBX.PlayerData.job.name == 'taxi' and QBX.PlayerData.job.isboss and Config.UseTarget then

        options[#options + 1] = {
            title = Lang:t('menu.boss_menu'),
            description = 'Boss Menu',
            event = 'qb-bossmenu:client:forceMenu'
        }
    end

    registeredMenu['options'] = options
    lib.registerContext(registeredMenu)
    lib.showContext('garages_depotlist')
end

local function onEnterDropZone()
    if whitelistedVehicle() and not isInsideDropZone and NpcData.NpcTaken then
        isInsideDropZone = true
        lib.showTextUI(Lang:t('info.drop_off_npc'), {position = 'left-center'})
        dropNpcPoly()
    end
end

local function onExitDropZone()
    lib.hideTextUI()
    isInsideDropZone = false

end

function createNpcDelieveryLocation()
    delieveryZone = lib.zones.box({
        coords = Config.PZLocations.DropLocations[NpcData.CurrentDeliver].coord,
        size = vec3(Config.PZLocations.DropLocations[NpcData.CurrentDeliver].height, Config.PZLocations.DropLocations[NpcData.CurrentDeliver].width, (Config.PZLocations.DropLocations[NpcData.CurrentDeliver].maxZ - Config.PZLocations.DropLocations[NpcData.CurrentDeliver].minZ)),
        rotation = Config.PZLocations.DropLocations[NpcData.CurrentDeliver].heading,
        debug = Config.PolyDebug,
        onEnter = onEnterDropZone,
        onExit = onExitDropZone
    })
end

function dropNpcPoly()
    CreateThread(function()
        while NpcData.NpcTaken do
            if isInsideDropZone then
                if IsControlJustPressed(0, 38) then
                    lib.hideTextUI()
                    local veh = cache.vehicle
                    TaskLeaveVehicle(NpcData.Npc, veh, 0)
                    Wait(1000)
                    SetVehicleDoorShut(veh, 3, false)
                    SetEntityAsMissionEntity(NpcData.Npc, false, true)
                    SetEntityAsNoLongerNeeded(NpcData.Npc)
                    local targetCoords = Config.NPCLocations.TakeLocations[NpcData.LastNpc]
                    TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, 0.0, 0.0)
                    SendNUIMessage({
                        action = 'toggleMeter'
                    })
                    TriggerServerEvent('qb-taxi:server:NpcPay', meterData.currentFare)
                    meterActive = false
                    SendNUIMessage({
                        action = 'resetMeter'
                    })
                    exports.qbx_core:Notify(Lang:t('info.person_was_dropped_off'), 'success')
                    if NpcData.DeliveryBlip ~= nil then
                        RemoveBlip(NpcData.DeliveryBlip)
                    end
                    local RemovePed = function(p)
                        SetTimeout(60000, function()
                            DeletePed(p)
                        end)
                    end
                    RemovePed(NpcData.Npc)
                    resetNpcTask()
                    delieveryZone:remove()
                    lib.hideTextUI()
                    break
                end
            end
            Wait(0)
        end
    end)
end

local function nonTargetEnter()
    CreateThread(function()
        while isPlayerInsideCabZone do
            DrawMarker(2, Config.Location.x, Config.Location.y, Config.Location.z, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.3, 0.5, 0.2, 200, 0, 0, 222, false, false, 0, true, nil, nil, false)
            if whitelistedVehicle() then
                DrawText3D(Config.Location.x, Config.Location.y, Config.Location.z + 0.3, Lang:t('info.vehicle_parking'))
                if IsControlJustReleased(0, 38) then
                    if cache.vehicle then
                        DeleteVehicle(cache.vehicle)
                    end
                end
            else
                DrawText3D(Config.Location.x, Config.Location.y, Config.Location.z + 0.3, Lang:t('info.job_vehicles'))
                if IsControlJustReleased(0, 38) then
                    taxiGarage()
                end
            end
            Wait(0)
        end
    end)
end

local function onEnterCabZone()
    if QBX.PlayerData.job.name ~= 'taxi' then return end
    isPlayerInsideCabZone = true
    CreateThread(function()
        while isPlayerInsideCabZone do
            if IsControlJustReleased(0, 38) then
                local cab = cache.vehicle
                lib.hideTextUI()
                if whitelistedVehicle() then
                    if meterIsOpen then
                        TriggerEvent('qb-taxi:client:toggleMeter')
                        meterActive = false
                    end
                    TaskLeaveVehicle(cache.ped, cache.vehicle, 0)
                    Wait(2000) -- 2 second delay just to ensure the player is out of the vehicle
                    DeleteVehicle(cab)
                    exports.qbx_core:Notify(Lang:t('info.taxi_returned'), 'success')
                end
            end
            Wait(0)
        end
    end)

    if Config.UseTarget then
        if whitelistedVehicle() then
            lib.showTextUI(Lang:t('info.vehicle_parking'), {position = 'left-center'})
        end
    else
        nonTargetEnter()
    end
end

local function onExitCabZone()
    lib.hideTextUI()
    isPlayerInsideCabZone = false
end

function setupCabParkingLocation()
    lib.zones.box({
        coords = vec3(Config.Location.x, Config.Location.y, Config.Location.z),
        size = vec3(4.0, 4.0, 4.0),
        rotation = 55,
        debug = Config.PolyDebug,
        onEnter = onEnterCabZone,
        onExit = onExitCabZone
    })
end

RegisterNetEvent('qb-taxi:client:TakeVehicle', function(data)
    local SpawnPoint = getVehicleSpawnPoint()
    if SpawnPoint then
        local coords = Config.CabSpawns[SpawnPoint]
        local CanSpawn = isSpawnPointClear(coords, 2.0)
        if CanSpawn then
            local netId = lib.callback.await('qb-taxi:server:spawnTaxi', false, data.model, coords)
            local veh = NetToVeh(netId)
            SetVehicleFuelLevel(veh, 100.0)
            SetVehicleEngineOn(veh, true, true, false)
        else
            exports.qbx_core:Notify(Lang:t('info.no_spawn_point'), 'error')
        end
    else
        exports.qbx_core:Notify(Lang:t('info.no_spawn_point'), 'error')
        return
    end
end)

-- Events
RegisterNetEvent('qb-taxi:client:DoTaxiNpc', function()
    if whitelistedVehicle() then
        if not NpcData.Active then
            NpcData.CurrentNpc = math.random(1, #Config.NPCLocations.TakeLocations)
            if NpcData.LastNpc ~= nil then
                while NpcData.LastNpc ~= NpcData.CurrentNpc do
                    NpcData.CurrentNpc = math.random(1, #Config.NPCLocations.TakeLocations)
                end
            end

            local Gender = math.random(1, #Config.NpcSkins)
            local PedSkin = math.random(1, #Config.NpcSkins[Gender])
            local model = GetHashKey(Config.NpcSkins[Gender][PedSkin])
            lib.requestModel(model)
            NpcData.Npc = CreatePed(3, model, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z - 0.98, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].w, true, true)
            PlaceObjectOnGroundProperly(NpcData.Npc)
            FreezeEntityPosition(NpcData.Npc, true)
            if NpcData.NpcBlip ~= nil then
                RemoveBlip(NpcData.NpcBlip)
            end
            exports.qbx_core:Notify(Lang:t('info.npc_on_gps'), 'success')

            -- added checks to disable distance checking if polyzone option is used
            if Config.UseTarget then
                createNpcPickUpLocation()
            end

            NpcData.NpcBlip = AddBlipForCoord(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z)
            SetBlipColour(NpcData.NpcBlip, 3)
            SetBlipRoute(NpcData.NpcBlip, true)
            SetBlipRouteColour(NpcData.NpcBlip, 3)
            NpcData.LastNpc = NpcData.CurrentNpc
            NpcData.Active = true

            -- added checks to disable distance checking if polyzone option is used
            if not Config.UseTarget then
                CreateThread(function()
                    while not NpcData.NpcTaken do

                        local pos = GetEntityCoords(cache.ped)
                        local dist = #(pos - vec3(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z))

                        if dist < 20 then
                            DrawMarker(2, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 255, 255, 255, 255, false, false, 0, true, nil, nil, false)

                            if dist < 5 then
                                DrawText3D(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z, Lang:t('info.call_npc'))
                                if IsControlJustPressed(0, 38) then
                                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(cache.vehicle), 0

                                    for i=maxSeats - 1, 0, -1 do
                                        if IsVehicleSeatFree(cache.vehicle, i) then
                                            freeSeat = i
                                            break
                                        end
                                    end

                                    meterIsOpen = true
                                    meterActive = true
                                    lastLocation = GetEntityCoords(cache.ped)
                                    SendNUIMessage({
                                        action = 'openMeter',
                                        toggle = true,
                                        meterData = Config.Meter
                                    })
                                    SendNUIMessage({
                                        action = 'toggleMeter'
                                    })
                                    ClearPedTasksImmediately(NpcData.Npc)
                                    FreezeEntityPosition(NpcData.Npc, false)
                                    TaskEnterVehicle(NpcData.Npc, cache.vehicle, -1, freeSeat, 1.0, 0)
                                    exports.qbx_core:Notify(Lang:t('info.go_to_location'), 'inform')
                                    if NpcData.NpcBlip ~= nil then
                                        RemoveBlip(NpcData.NpcBlip)
                                    end
                                    getDeliveryLocation()
                                    NpcData.NpcTaken = true
                                end
                            end
                        end

                        Wait(0)
                    end
                end)
            end
        else
            exports.qbx_core:Notify(Lang:t('error.already_mission'), 'error')
        end
    else
        exports.qbx_core:Notify(Lang:t('error.not_in_taxi'), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:toggleMeter', function()
    if cache.vehicle then
        if whitelistedVehicle() then
            if not meterIsOpen and isDriver() then
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = true,
                    meterData = Config.Meter
                })
                meterIsOpen = true
            else
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = false
                })
                meterIsOpen = false
            end
        else
            exports.qbx_core:Notify(Lang:t('error.missing_meter'), 'error')
        end
    else
        exports.qbx_core:Notify(Lang:t('error.no_vehicle'), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:enableMeter', function()
    if meterIsOpen then
        SendNUIMessage({
            action = 'toggleMeter'
        })
    else
        exports.qbx_core:Notify(Lang:t('error.not_active_meter'), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:toggleMuis', function()
    Wait(400)
    if meterIsOpen then
        if not mouseActive then
            SetNuiFocus(true, true)
            mouseActive = true
        end
    else
        exports.qbx_core:Notify(Lang:t('error.no_meter_sight'), 'error')
    end
end)

RegisterNetEvent('qb-taxijob:client:requestcab', function()
    taxiGarage()
end)

-- NUI Callbacks

RegisterNUICallback('enableMeter', function(data, cb)
    meterActive = data.enabled
    if not meterActive then resetMeter() end
    lastLocation = GetEntityCoords(cache.ped)
    cb('ok')
end)

RegisterNUICallback('hideMouse', function(_, cb)
    SetNuiFocus(false, false)
    mouseActive = false
    cb('ok')
end)

-- Threads
CreateThread(function()
    local taxiBlip = AddBlipForCoord(Config.Location.x, Config.Location.y, Config.Location.z)
    SetBlipSprite (taxiBlip, 198)
    SetBlipDisplay(taxiBlip, 4)
    SetBlipScale  (taxiBlip, 0.6)
    SetBlipAsShortRange(taxiBlip, true)
    SetBlipColour(taxiBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Lang:t('info.blip_name'))
    EndTextCommandSetBlipName(taxiBlip)
end)

CreateThread(function()
    while true do
        Wait(2000)
        calculateFareAmount()
    end
end)

CreateThread(function()
    while true do
        if not cache.vehicle then
            if meterIsOpen then
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = false
                })
                meterIsOpen = false
            end
        end
        Wait(200)
    end
end)
