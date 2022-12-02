-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local meterIsOpen = false
local meterActive = false
local lastLocation = nil
local mouseActive = false
local PlayerJob = {}

-- used for zones
local isInsidePickupZone = false
local isInsideDropZone = false
local Notified = false
local isPlayerInsideZone = false

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

-- events
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerJob = QBCore.Functions.GetPlayerData().job

    if Config.UseTarget then
        setupTarget()
        setupCabParkingLocation()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerJob = JobInfo
end)

-- Functions
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

    return retval
end

local function IsDriver()
    return GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped
end

local function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 215)
    BeginTextCommandDisplayText("STRING")
    SetTextCentre(true)
    AddTextComponentSubstringPlayerName(text)
    SetDrawOrigin(x,y,z, 0)
    EndTextCommandDisplayText(0.0, 0.0)

    local factor = (string.len(text)) / 370

    DrawRect(0.0, 0.0125, 0.017+ factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

local function GetDeliveryLocation()
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

    if not Config.UseTarget then -- added checks to disable distance checking if zone option is used
        CreateThread(function()
            while true do
                local pos = GetEntityCoords(cache.ped)
                local dist = #(pos - vec3(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z))

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

                            lib.notify({
                                description = Lang:t("info.person_was_dropped_off"),
                                type = 'success'
                            })

                            if NpcData.DeliveryBlip then
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

local function EnumerateEntitiesWithinDistance(entities, isPlayerEntities, coords, maxDistance)
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
        if IsSpawnPointClear(vec3(v.x, v.y, v.z), 2.5) then
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

            meterData['distanceTraveled'] += (newDistance/1609)

            local fareAmount = ((meterData['distanceTraveled']) * Config.Meter.defaultPrice) + Config.Meter.startingPrice

            meterData['currentFare'] = math.floor(fareAmount)

            SendNUIMessage({
                action = "updateMeter",
                meterData = meterData
            })
        end
    end
end

function TaxiGarage()
    local vehicleMenu = {}

    for _, v in pairs(Config.AllowedVehicles) do
        vehicleMenu[#vehicleMenu + 1] = {
            title = v.label,
            event = "qb-taxi:client:TakeVehicle",
            args = {
                model = v.model
            }
        }
    end

    lib.registerContext({
        id = 'open_taxiGarage',
        title = Lang:t("menu.taxi_menu_header"),
        options = vehicleMenu
    })
    lib.showContext('open_taxiGarage')
end

RegisterNetEvent("qb-taxi:client:TakeVehicle", function(data)
    local SpawnPoint = getVehicleSpawnPoint()

    if SpawnPoint then
        local coords = vec3(Config.CabSpawns[SpawnPoint].x,Config.CabSpawns[SpawnPoint].y,Config.CabSpawns[SpawnPoint].z)
        local CanSpawn = IsSpawnPointClear(coords, 2.0)

        if CanSpawn then
            QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
                local veh = NetToVeh(netId)

                SetVehicleNumberPlateText(veh, "TAXI"..tostring(math.random(1000, 9999)))
                SetVehicleFuelLevel(veh, 100.0)

                lib.hideContext()

                SetEntityHeading(veh, Config.CabSpawns[SpawnPoint].w)
                TaskWarpPedIntoVehicle(cache.ped, veh, -1)

                TriggerEvent("vehiclekeys:client:SetOwner", QBCore.Functions.GetPlate(veh))

                SetVehicleEngineOn(veh, true, true)
            end, data.model, coords, true)
        else
            lib.notify({
                description = Lang:t("info.no_spawn_point"),
                type = 'error'
            })
        end
    else
        lib.notify({
            description = Lang:t("info.no_spawn_point"),
            type = 'error'
        })
        return
    end
end)

-- Events
RegisterNetEvent('qb-taxi:client:DoTaxiNpc', function()
    if whitelistedVehicle() then
        if not NpcData.Active then
            NpcData.CurrentNpc = math.random(1, #Config.NPCLocations.TakeLocations)

            if NpcData.LastNpc then
                while NpcData.LastNpc ~= NpcData.CurrentNpc do
                    NpcData.CurrentNpc = math.random(1, #Config.NPCLocations.TakeLocations)
                end
            end

            local Gender = math.random(1, #Config.NpcSkins)
            local PedSkin = math.random(1, #Config.NpcSkins[Gender])
            local model = joaat(Config.NpcSkins[Gender][PedSkin])

            lib.requestModel(model)

            NpcData.Npc = CreatePed(3, model, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z - 0.98, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].w, false, true)

            PlaceObjectOnGroundProperly(NpcData.Npc)
            FreezeEntityPosition(NpcData.Npc, true)

            if NpcData.NpcBlip then
                RemoveBlip(NpcData.NpcBlip)
            end

            lib.notify({
                description = Lang:t("info.npc_on_gps"),
                type = 'success'
            })

            -- added checks to disable distance checking if zone option is used
            if Config.UseTarget then
                createNpcPickUpLocation()
            end

            NpcData.NpcBlip = AddBlipForCoord(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z)

            SetBlipColour(NpcData.NpcBlip, 3)
            SetBlipRoute(NpcData.NpcBlip, true)
            SetBlipRouteColour(NpcData.NpcBlip, 3)

            NpcData.LastNpc = NpcData.CurrentNpc
            NpcData.Active = true

            -- added checks to disable distance checking if zone option is used
            if not Config.UseTarget then
                CreateThread(function()
                    while not NpcData.NpcTaken do
                        local pos = GetEntityCoords(cache.ped)
                        local dist = #(pos - vec3(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z))

                        if dist < 20 then
                            DrawMarker(2, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 255, 255, 255, 255, 0, 0, 0, 1, 0, 0, 0)

                            if dist < 5 then
                                DrawText3D(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z, Lang:t("info.call_npc"))

                                if IsControlJustPressed(0, 38) then
                                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(cache.vehicle)

                                    for i = maxSeats - 1, 0, -1 do
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

                                    lib.notify({
                                        description = Lang:t("info.go_to_location")
                                    })

                                    if NpcData.NpcBlip then
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
            lib.notify({
                description = Lang:t("error.already_mission"),
                type = 'error'
            })
        end
    else
        lib.notify({
            description = Lang:t("error.not_in_taxi"),
            type = 'error'
        })
    end
end)

RegisterNetEvent('qb-taxi:client:toggleMeter', function()
    if cache.vehicle then
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
            lib.notify({
                description = Lang:t("error.missing_meter"),
                type = 'error'
            })
        end
    else
        lib.notify({
            description = Lang:t("error.no_vehicle"),
            type = 'error'
        })
    end
end)

RegisterNetEvent('qb-taxi:client:enableMeter', function()
    if meterIsOpen then
        SendNUIMessage({
            action = "toggleMeter"
        })
    else
        lib.notify({
            description = Lang:t("error.not_active_meter"),
            type = 'error'
        })
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
        lib.notify({
            description = Lang:t("error.no_meter_sight"),
            type = 'error'
        })
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

    SetBlipSprite(TaxiBlip, 198)
    SetBlipDisplay(TaxiBlip, 4)
    SetBlipScale(TaxiBlip, 0.6)
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
        if not cache.vehicle then
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

-- added checks to disable distance checking if zone option is used
CreateThread(function()
    while true do
        if not Config.UseTarget then
            local inRange = false

            if LocalPlayer.state.isLoggedIn then
                local Player = QBCore.Functions.GetPlayerData()

                if Player.job.name == "taxi" then
                    local pos = GetEntityCoords(cache.ped)
                    local vehDist = #(pos - vec3(Config.Location.x, Config.Location.y, Config.Location.z))

                    if vehDist < 30 then
                        inRange = true

                        DrawMarker(2, Config.Location.x, Config.Location.y, Config.Location.z, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.3, 0.5, 0.2, 200, 0, 0, 222, false, false, false, true, false, false, false)

                        if vehDist < 1.5 then
                            if whitelistedVehicle() then
                                DrawText3D(Config.Location.x, Config.Location.y, Config.Location.z + 0.3, Lang:t("info.vehicle_parking"))

                                if IsControlJustReleased(0, 38) then
                                    if cache.vehicle then
                                        DeleteVehicle(cache.vehicle)
                                    end
                                end
                            else
                                DrawText3D(Config.Location.x, Config.Location.y, Config.Location.z + 0.3, Lang:t("info.job_vehicles"))

                                if IsControlJustReleased(0, 38) then
                                    TaxiGarage()
                                end
                            end
                        end
                    end
                end
            end

            if not inRange then
                Wait(3000)
            end
        end

        Wait(0)
    end
end)

-- POLY & TARGET Conversion code

-- setup ox_target
function setupTarget()
    CreateThread(function()
        exports.ox_target:addBoxZone({
            coords = vec4(901.34, -170.06, 74.08, 228.81),
            size = vec3(2, 2, 2),
            rotation = 0.0,
            options = {
                {
                    name = 'qb-taxijob:cab',
                    event = "qb-taxijob:client:requestcab",
                    icon = "fa-solid fa-right-to-bracket",
                    label = '🚕 Request Taxi Cab',
                    distance = 2.5
                }
            }
        })
    end)
end

local zone
local delieveryZone

function createNpcPickUpLocation()
    local locationData = Config.PZLocations.TakeLocations[NpcData.CurrentNpc]

    zone = lib.zones.box({
        coords = locationData.coords,
        size = locationData.size,
        rotation = locationData.rotation,
        onEnter = function(_)
            if whitelistedVehicle() and not isInsidePickupZone and not NpcData.NpcTaken then
                isInsidePickupZone = true

                lib.showTextUI(Lang:t("info.call_npc"))

                callNpcPoly()
            end
        end,
        onExit = function(_)
            isInsidePickupZone = false
        end
    })
end

function createNpcDelieveryLocation()
    local locationData = Config.PZLocations.DropLocations[NpcData.CurrentNpc]

    delieveryZone = lib.zones.box({
        coords = locationData.coords,
        size = locationData.size,
        rotation = locationData.rotation,
        onEnter = function(_)
            if whitelistedVehicle() and not isInsideDropZone and NpcData.NpcTaken then
                isInsideDropZone = true

                lib.showTextUI(Lang:t("info.drop_off_npc"))

                dropNpcPoly()
            end
        end,
        onExit = function(_)
            isInsideDropZone = false
        end
    })
end

function callNpcPoly()
    CreateThread(function()
        while not NpcData.NpcTaken do
            if isInsidePickupZone then
                if IsControlJustPressed(0, 38) then
                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(cache.vehicle)

                    for i = maxSeats - 1, 0, -1 do
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

                    lib.notify({
                        description = Lang:t("info.go_to_location")
                    })

                    if NpcData.NpcBlip then
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

function dropNpcPoly()
    CreateThread(function()
        while NpcData.NpcTaken do
            if isInsideDropZone then
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

                    lib.notify({
                        description = Lang:t("info.person_was_dropped_off"),
                        type = 'success'
                    })

                    if NpcData.DeliveryBlip then
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

function setupCabParkingLocation()
    lib.zones.box({
        coords = vec3(909.0, -176.0, 74.0),
        size = vec3(3.0, 3.0, 2),
        rotation = 327.5,
        onEnter = function(_)
            if not Notified then
                if whitelistedVehicle() then
                    lib.showTextUI(Lang:t("info.vehicle_parking"))

                    Notified = true
                    isPlayerInsideZone = true
                end
            end
        end,
        onExit = function(_)
            if Notified then
                lib.hideTextUI()

                Notified = false
                isPlayerInsideZone = false
            end
        end
    })
end

-- thread to handle vehicle parking
CreateThread(function()
    while true do
        if isPlayerInsideZone then
            if IsControlJustReleased(0, 38) then
                if cache.vehicle then
                    if meterIsOpen then
                        TriggerEvent('qb-taxi:client:toggleMeter')

                        meterActive = false
                    end

                    TaskLeaveVehicle(cache.ped, cache.vehicle, 0)

                    Wait(2000) -- 2 second delay just to ensure the player is out of the vehicle

                    DeleteVehicle(cache.vehicle)

                    lib.notify({
                        description = Lang:t("info.taxi_returned"),
                        type = 'success'
                    })
                end
            end
        end

        Wait(0)
    end
end)

-- switched boss menu from qb-bossmenu to taxijob
CreateThread(function()
    while true do
        local sleep = 1000

        if PlayerJob.name == "taxi" and PlayerJob.isboss and not Config.UseTarget then
            local pos = GetEntityCoords(cache.ped)

            if #(pos - Config.BossMenu) < 2.0 then
                sleep = 7

                DrawText3D(Config.BossMenu.x, Config.BossMenu.y, Config.BossMenu.z, "~g~E~w~ - Boss Menu")

                if IsControlJustReleased(0, 38) then
                    TriggerEvent('qb-bossmenu:client:OpenMenu')
                end
            end
        end

        Wait(sleep)
    end
end)