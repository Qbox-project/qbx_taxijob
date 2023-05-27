-- Variables

local QBCore = exports['qbx-core']:GetCoreObject()
local meterIsOpen = false
local meterActive = false
local lastLocation = nil
local mouseActive = false

local PlayerJob = {}

-- used for polyzones
local isInsidePickupZone = false
local isInsideDropZone = false
local isPlayerInsideCabZone = false
local isPlayerInsideBossZone = false

local meterData = {
    fareAmount = 6,
    currentFare = 0,
    distanceTraveled = 0,
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
        TaskPlayAnim(taxiPed, 'abigail_mcs_1_concat-0', 'csb_abigail_dual-0', 8.0, 0, -1, 1, false, false, false)
        TaskStartScenarioInPlace(taxiPed, "WORLD_HUMAN_AA_COFFEE", 0, false)
        FreezeEntityPosition(taxiPed, true)
        SetEntityInvincible(taxiPed, true)
        exports.ox_target:addLocalEntity(taxiPed, {
            {
                type = "client",
                event = "qb-taxijob:client:requestcab",
                icon = "fas fa-sign-in-alt",
                label = Lang:t('info.request_taxi'),
                job = "taxi",
            }
        })
    end)
end

local function ResetNpcTask()
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
        NpcDelivered = false,
    }
end

local function resetMeter()
    meterData = {
        fareAmount = 6,
        currentFare = 0,
        distanceTraveled = 0,
    }
end

local function whitelistedVehicle()
    local veh = GetEntityModel(cache.vehicle)
    local retval = false

    for i = 1, #Config.AllowedVehicles, 1 do
        if veh == GetHashKey(Config.AllowedVehicles[i].model) then
            retval = true
        end
    end

    if veh == GetHashKey("dynasty") then
        retval = true
    end

    return retval
end

local function IsDriver()
    return GetPedInVehicleSeat(GetVehiclePedIsIn(cache.ped, false), -1) == cache.ped
end

local function DrawText3D(x, y, z, text)
	SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x,y,z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0+0.0125, 0.017+ factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

local zone
local delieveryZone

local function GetDeliveryLocation()
    NpcData.CurrentDeliver = math.random(1, #Config.NPCLocations.DeliverLocations)
    if NpcData.LastDeliver ~= nil then
        while NpcData.LastDeliver ~= NpcData.CurrentDeliver do
            NpcData.CurrentDeliver = math.random(1, #Config.NPCLocations.DeliverLocations)
        end
    end

    if NpcData.DeliveryBlip ~= nil then
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
                local dist = #(pos - vector3(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z))
                if dist < 20 then
                    DrawMarker(2, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 255, 255, 255, 255, 0, 0, 0, 1, 0, 0, 0)
                    if dist < 5 then
                        DrawText3D(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z, Lang:t("info.drop_off_npc"))
                        if IsControlJustPressed(0, 38) then
                            TaskLeaveVehicle(NpcData.Npc, cache.vehicle, 0)
                            SetEntityAsMissionEntity(NpcData.Npc, false, true)
                            SetEntityAsNoLongerNeeded(NpcData.Npc)
                            local targetCoords = Config.NPCLocations.TakeLocations[NpcData.LastNpc]
                            TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, 0.0, 0.0)
                            SendNUIMessage({
                                action = "toggleMeter"
                            })
                            TriggerServerEvent('qb-taxi:server:NpcPay', meterData.currentFare)
                            meterActive = false
                            SendNUIMessage({
                                action = "resetMeter"
                            })
                            QBCore.Functions.Notify(Lang:t("info.person_was_dropped_off"), 'success')
                            if NpcData.DeliveryBlip ~= nil then
                                RemoveBlip(NpcData.DeliveryBlip)
                            end
                            local RemovePed = function(p)
                                SetTimeout(60000, function()
                                    DeletePed(p)
                                end)
                            end
                            RemovePed(NpcData.Npc)
                            ResetNpcTask()
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
                    exports['qbx-core']:KeyPressed()
                    local veh = GetVehiclePedIsIn(cache.ped, 0)
                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(veh)

                    for i=maxSeats - 1, 0, -1 do
                        if IsVehicleSeatFree(veh, i) then
                            freeSeat = i
                            break
                        end
                    end

                    meterIsOpen = true
                    meterActive = true
                    lastLocation = GetEntityCoords(cache.ped)
                    SendNUIMessage({
                        action = "openMeter",
                        toggle = true,
                        meterData = Config.Meter
                    })
                    SendNUIMessage({
                        action = "toggleMeter"
                    })
                    ClearPedTasksImmediately(NpcData.Npc)
                    FreezeEntityPosition(NpcData.Npc, false)
                    TaskEnterVehicle(NpcData.Npc, veh, -1, freeSeat, 1.0, 0)
                    QBCore.Functions.Notify(Lang:t("info.go_to_location"))
                    if NpcData.NpcBlip ~= nil then
                        RemoveBlip(NpcData.NpcBlip)
                    end
                    GetDeliveryLocation()
                    NpcData.NpcTaken = true
                    createNpcDelieveryLocation()
                    zone:remove()
                end
            end
            Wait(0)
        end
    end)
end

local function onEnterCallZone()
    if whitelistedVehicle() and not isInsidePickupZone and not NpcData.NpcTaken then
        isInsidePickupZone = true
        lib.showTextUI(Lang:t("info.call_npc"), {position = Config.DefaultTextLocation})
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
        --debug = true,
        onEnter = onEnterCallZone,
        onExit = onExitCallZone
    })
end



local function EnumerateEntitiesWithinDistance(entities, isPlayerEntities, coords, maxDistance)
	local nearbyEntities = {}
	if coords then
		coords = vector3(coords.x, coords.y, coords.z)
	else
		coords = GetEntityCoords(cache.ped)
	end
	for k, entity in pairs(entities) do
		local distance = #(coords - GetEntityCoords(entity))
		if distance <= maxDistance then
			nearbyEntities[#nearbyEntities+1] = isPlayerEntities and k or entity
		end
	end
	return nearbyEntities
end

local function GetVehiclesInArea(coords, maxDistance) -- Vehicle inspection in designated area
	return EnumerateEntitiesWithinDistance(GetGamePool('CVehicle'), false, coords, maxDistance)
end

local function IsSpawnPointClear(coords, maxDistance) -- Check the spawn point to see if it's empty or not:
	return #GetVehiclesInArea(coords, maxDistance) == 0
end

local function getVehicleSpawnPoint()
    local near = nil
	local distance = 10000
	for k, v in pairs(Config.CabSpawns) do
        if IsSpawnPointClear(vector3(v.x, v.y, v.z), 2.5) then
            local pos = GetEntityCoords(cache.ped)
            local cur_distance = #(pos - vector3(v.x, v.y, v.z))
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

            meterData['distanceTraveled'] += (newDistance/1609)

            local fareAmount = ((meterData['distanceTraveled'])*Config.Meter["defaultPrice"])+Config.Meter["startingPrice"]
            meterData['currentFare'] = math.floor(fareAmount)

            SendNUIMessage({
                action = "updateMeter",
                meterData = meterData
            })
        end
    end
end

local function onEnterCabBossZone()
    if PlayerJob.name ~= "taxi" and PlayerJob.isboss and Config.UseTarget then return end
    isPlayerInsideBossZone = true
    CreateThread(function()
        while isPlayerInsideBossZone do
            local pos = GetEntityCoords(cache.ped)
            if #(pos - Config.BossMenu) < 2.0 then
                DrawText3D(Config.BossMenu.x, Config.BossMenu.y,Config.BossMenu.z, Lang:t('menu.boss_menu'))
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
        coords = vector3(Config.BossMenu.x, Config.BossMenu.y, Config.BossMenu.z),
        size = vec3(2.5, 2.5, 2.5),
        rotation = 45,
        --debug = true,
        onEnter = onEnterCabBossZone,
        onExit = onExitCabBossZone
    })
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or table.type(QBCore.Functions.GetPlayerData()) == 'empty' or not Config.UseTarget then return end
    if Config.UseTarget then
        DeletePed(taxiPed)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or table.type(QBCore.Functions.GetPlayerData()) == 'empty' or not Config.UseTarget then return end
    if LocalPlayer.state.isLoggedIn then
        PlayerJob = QBCore.Functions.GetPlayerData().job
        if PlayerJob.name == "taxi" then
            setupCabParkingLocation()
            if PlayerJob.isboss then
                setupCabBossLocation()
            end
        end
    end
    if Config.UseTarget then
        setupTarget()
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerJob = QBCore.Functions.GetPlayerData().job
    if Config.UseTarget then
        setupTarget()
    end
    if PlayerJob.name == "taxi" then

        setupCabParkingLocation()
        if PlayerJob.isboss then
            setupCabBossLocation()
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerJob = JobInfo
end)

local function TaxiGarage()
    local registeredMenu = {
        id = 'garages_depotlist',
        title = Lang:t("menu.taxi_menu_header"),
        options = {}
    }
    local options = {}
    for _, v in pairs(Config.AllowedVehicles) do

        options[#options+1] = {
            title = v.label,
            description = "Take our a " .. v.label,
            event = 'qb-taxi:client:TakeVehicle',
            args = {model = v.model}
        }
    end
    if PlayerJob.name == "taxi" and PlayerJob.isboss and Config.UseTarget then

        options[#options+1] = {
            title = Lang:t("menu.boss_menu"),
            description = "Boss Menu",
            event = 'qb-bossmenu:client:forceMenu',
        }
    end

    registeredMenu["options"] = options
    lib.registerContext(registeredMenu)
    lib.showContext('garages_depotlist')
end

local function onEnterDropZone()
    if whitelistedVehicle() and not isInsideDropZone and NpcData.NpcTaken then
        isInsideDropZone = true
        lib.showTextUI(Lang:t("info.drop_off_npc"), {position = Config.DefaultTextLocation})
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
        --debug = true,
        onEnter = onEnterDropZone,
        onExit = onExitDropZone
    })
end

function dropNpcPoly()
    CreateThread(function()
        while NpcData.NpcTaken do
            if isInsideDropZone then
                if IsControlJustPressed(0, 38) then
                    exports['qbx-core']:KeyPressed()
                    local veh = GetVehiclePedIsIn(cache.ped, 0)
                    TaskLeaveVehicle(NpcData.Npc, veh, 0)
                    Wait(1000)
                    SetVehicleDoorShut(veh, 3, false)
                    SetEntityAsMissionEntity(NpcData.Npc, false, true)
                    SetEntityAsNoLongerNeeded(NpcData.Npc)
                    local targetCoords = Config.NPCLocations.TakeLocations[NpcData.LastNpc]
                    TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, 0.0, 0.0)
                    SendNUIMessage({
                        action = "toggleMeter"
                    })
                    TriggerServerEvent('qb-taxi:server:NpcPay', meterData.currentFare)
                    meterActive = false
                    SendNUIMessage({
                        action = "resetMeter"
                    })
                    QBCore.Functions.Notify(Lang:t("info.person_was_dropped_off"), 'success')
                    if NpcData.DeliveryBlip ~= nil then
                        RemoveBlip(NpcData.DeliveryBlip)
                    end
                    local RemovePed = function(p)
                        SetTimeout(60000, function()
                            DeletePed(p)
                        end)
                    end
                    RemovePed(NpcData.Npc)
                    ResetNpcTask()
                    delieveryZone:remove()
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
            DrawMarker(2, Config.Location.x, Config.Location.y, Config.Location.z, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.3, 0.5, 0.2, 200, 0, 0, 222, false, false, false, true, false, false, false)
            if whitelistedVehicle() then
                DrawText3D(Config.Location.x, Config.Location.y, Config.Location.z + 0.3, Lang:t("info.vehicle_parking"))
                if IsControlJustReleased(0, 38) then
                    if IsPedInAnyVehicle(cache.ped, false) then
                        DeleteVehicle(cache.vehicle)
                    end
                end
            else
                DrawText3D(Config.Location.x, Config.Location.y, Config.Location.z + 0.3, Lang:t("info.job_vehicles"))
                if IsControlJustReleased(0, 38) then
                    TaxiGarage()
                end
            end
            Wait(0)
        end
    end)
end

local function onEnterCabZone()
    if PlayerJob.name ~= "taxi" then return end
    isPlayerInsideCabZone = true
    CreateThread(function()
        while isPlayerInsideCabZone do
            if IsControlJustReleased(0, 38) then
                local cab = cache.vehicle
                exports['qbx-core']:KeyPressed()
                if whitelistedVehicle() then
                    if meterIsOpen then
                        TriggerEvent('qb-taxi:client:toggleMeter')
                        meterActive = false
                    end
                    TaskLeaveVehicle(cache.ped, cache.vehicle, 0)
                    Wait(2000) -- 2 second delay just to ensure the player is out of the vehicle
                    DeleteVehicle(cab)
                    QBCore.Functions.Notify(Lang:t("info.taxi_returned"), 'success')
                end
            end
            Wait(0)
        end
    end)

    if Config.UseTarget then
        if whitelistedVehicle() then
            lib.showTextUI(Lang:t("info.vehicle_parking"), {position = Config.DefaultTextLocation})
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
        coords = vector3(Config.Location.x, Config.Location.y, Config.Location.z),
        size = vec3(4.0, 4.0, 4.0),
        rotation = 55,
        --debug = true,
        onEnter = onEnterCabZone,
        onExit = onExitCabZone
    })
end

RegisterNetEvent("qb-taxi:client:TakeVehicle", function(data)
    local SpawnPoint = getVehicleSpawnPoint()
    if SpawnPoint then
        local coords = vector3(Config.CabSpawns[SpawnPoint].x,Config.CabSpawns[SpawnPoint].y,Config.CabSpawns[SpawnPoint].z)
        local CanSpawn = IsSpawnPointClear(coords, 2.0)
        if CanSpawn then
            QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
                local veh = NetToVeh(netId)
                SetVehicleNumberPlateText(veh, "TAXI"..tostring(math.random(1000, 9999)))
                exports['LegacyFuel']:SetFuel(veh, 100.0)
                SetEntityHeading(veh, Config.CabSpawns[SpawnPoint].w)
                TaskWarpPedIntoVehicle(cache.ped, veh, -1)
                TriggerEvent("vehiclekeys:client:SetOwner", QBCore.Functions.GetPlate(veh))
                SetVehicleEngineOn(veh, true, true)
            end, data.model, coords, true)
        else
            QBCore.Functions.Notify(Lang:t("info.no_spawn_point"), "error")
        end
    else
        QBCore.Functions.Notify(Lang:t("info.no_spawn_point"), 'error')
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
            NpcData.Npc = CreatePed(3, model, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z - 0.98, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].w, false, true)
            PlaceObjectOnGroundProperly(NpcData.Npc)
            FreezeEntityPosition(NpcData.Npc, true)
            if NpcData.NpcBlip ~= nil then
                RemoveBlip(NpcData.NpcBlip)
            end
            QBCore.Functions.Notify(Lang:t("info.npc_on_gps"), 'success')

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
                        local dist = #(pos - vector3(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z))

                        if dist < 20 then
                            DrawMarker(2, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 255, 255, 255, 255, 0, 0, 0, 1, 0, 0, 0)

                            if dist < 5 then
                                DrawText3D(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z, Lang:t("info.call_npc"))
                                if IsControlJustPressed(0, 38) then
                                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(cache.vehicle)

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
                                        action = "openMeter",
                                        toggle = true,
                                        meterData = Config.Meter
                                    })
                                    SendNUIMessage({
                                        action = "toggleMeter"
                                    })
                                    ClearPedTasksImmediately(NpcData.Npc)
                                    FreezeEntityPosition(NpcData.Npc, false)
                                    TaskEnterVehicle(NpcData.Npc, cache.vehicle, -1, freeSeat, 1.0, 0)
                                    QBCore.Functions.Notify(Lang:t("info.go_to_location"))
                                    if NpcData.NpcBlip ~= nil then
                                        RemoveBlip(NpcData.NpcBlip)
                                    end
                                    GetDeliveryLocation()
                                    NpcData.NpcTaken = true
                                end
                            end
                        end

                        Wait(0)
                    end
                end)
            end
        else
            QBCore.Functions.Notify(Lang:t("error.already_mission"))
        end
    else
        QBCore.Functions.Notify(Lang:t("error.not_in_taxi"))
    end
end)

RegisterNetEvent('qb-taxi:client:toggleMeter', function()
    if IsPedInAnyVehicle(cache.ped, false) then
        if whitelistedVehicle() then
            if not meterIsOpen and IsDriver() then
                SendNUIMessage({
                    action = "openMeter",
                    toggle = true,
                    meterData = Config.Meter
                })
                meterIsOpen = true
            else
                SendNUIMessage({
                    action = "openMeter",
                    toggle = false
                })
                meterIsOpen = false
            end
        else
            QBCore.Functions.Notify(Lang:t("error.missing_meter"), 'error')
        end
    else
        QBCore.Functions.Notify(Lang:t("error.no_vehicle"), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:enableMeter', function()
    if meterIsOpen then
        SendNUIMessage({
            action = "toggleMeter"
        })
    else
        QBCore.Functions.Notify(Lang:t("error.not_active_meter"), 'error')
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
        QBCore.Functions.Notify(Lang:t("error.no_meter_sight"), 'error')
    end
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
    local TaxiBlip = AddBlipForCoord(Config.Location)
    SetBlipSprite (TaxiBlip, 198)
    SetBlipDisplay(TaxiBlip, 4)
    SetBlipScale  (TaxiBlip, 0.6)
    SetBlipAsShortRange(TaxiBlip, true)
    SetBlipColour(TaxiBlip, 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(Lang:t("info.blip_name"))
    EndTextCommandSetBlipName(TaxiBlip)
end)

CreateThread(function()
    while true do
        Wait(2000)
        calculateFareAmount()
    end
end)

CreateThread(function()
    while true do
        if not IsPedInAnyVehicle(cache.ped, false) then
            if meterIsOpen then
                SendNUIMessage({
                    action = "openMeter",
                    toggle = false
                })
                meterIsOpen = false
            end
        end
        Wait(200)
    end
end)

RegisterNetEvent('qb-taxijob:client:requestcab', function()
    TaxiGarage()
end)

-- POLY & TARGET Conversion code

