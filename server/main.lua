lib.versionCheck('Qbox-project/qbx_taxijob')

local config = require 'config.server'
local sharedConfig = require 'config.shared'
local ITEMS = exports.ox_inventory:Items()

local lastPayTime = {}
local activeFares = {}

local function getPlayerWithTaxiJob(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    if player.PlayerData.job.name ~= 'taxi' then
        return nil
    end
    return player
end

local function isAllowedVehicleModel(model)
    if type(model) ~= 'string' then return false end
    local lower = model:lower()
    for _, allowed in ipairs(config.allowedVehicleModels) do
        if type(allowed) == 'string' and allowed:lower() == lower then
            return true
        end
    end
    return false
end

local function isAllowedVehicleHash(model)
    for _, allowed in ipairs(config.allowedVehicleModels) do
        if model == joaat(allowed) then return true end
    end
    return false
end

local function getCoordsXYZW(coords)
    if type(coords) == 'table' then
        local x = coords.x or coords[1]
        local y = coords.y or coords[2]
        local z = coords.z or coords[3]
        local w = coords.w or coords[4]
        if x and y and z then
            x, y, z = tonumber(x), tonumber(y), tonumber(z)
            w = w and tonumber(w) or 0
            if x and y and z then return x, y, z, w end
        end
    elseif type(coords) == 'vector3' or type(coords) == 'vector4' or (type(coords) == 'userdata' and coords.x) then
        return coords.x, coords.y, coords.z, coords.w or 0
    end
    return nil, nil, nil, 0
end

local function isNearAllowedSpawnPoint(coords)
    local x, y, z = getCoordsXYZW(coords)
    if not x or not y or not z then return false end
    local pos = vec3(x, y, z)
    for _, spawn in ipairs(config.cabSpawns) do
        local dist = #(pos - spawn.xyz)
        if dist <= config.spawnPointMaxDistance then
            return true
        end
    end
    return false
end

lib.callback.register('qb-taxi:server:spawnTaxi', function(source, model, coords)
    local player = getPlayerWithTaxiJob(source)
    if not player then
        lib.print.warn(('qb_taxijob: spawnTaxi from source %s without taxi job'):format(source))
        return nil
    end

    if not isAllowedVehicleModel(model) then
        lib.print.warn(('qb_taxijob: spawnTaxi from source %s invalid model %s'):format(source, tostring(model)))
        return nil
    end

    if not isNearAllowedSpawnPoint(coords) then
        lib.print.warn(('qb_taxijob: spawnTaxi from source %s coords not near cab spawn'):format(source))
        return nil
    end

    local x, y, z, heading = getCoordsXYZW(coords)
    if not x or not y or not z then return nil end
    local spawnCoords = vec4(x, y, z, heading)
    local netId, veh = qbx.spawnVehicle({
        model = model,
        spawnSource = spawnCoords,
        warp = GetPlayerPed(source --[[@as number]]),
    })

    if not veh or veh == 0 then return nil end

    local plate = 'TAXI' .. math.random(1000, 9999)
    SetVehicleNumberPlateText(veh, plate)
    TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate)
    return netId
end)

RegisterNetEvent('qb-taxi:server:startNpcFare', function(pickupIndex, deliverIndex, netId)
    local src = source
    local player = getPlayerWithTaxiJob(src)
    if not player or math.type(pickupIndex) ~= 'integer' or math.type(deliverIndex) ~= 'integer' or math.type(netId) ~= 'integer' then return end

    local pickup = sharedConfig.npcLocations.takeLocations[pickupIndex]
    local destination = sharedConfig.npcLocations.deliverLocations[deliverIndex]
    if not pickup or not destination then return end

    local ped = GetPlayerPed(src)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end
    if #(GetEntityCoords(ped) - pickup.xyz) > 15.0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    if not isAllowedVehicleHash(GetEntityModel(vehicle)) then return end

    local distance = #(pickup.xyz - destination.xyz)
    activeFares[src] = {
        destination = deliverIndex,
        vehicle = netId,
        payment = math.min(config.maxFare, math.max(1, math.floor(distance / 1609 * config.farePerMile))),
        earliestCompletion = os.time() + math.max(10, math.floor(distance / 60)),
        expiresAt = os.time() + 1800,
    }
end)

RegisterNetEvent('qb-taxi:server:NpcPay', function()
    local src = source
    local player = getPlayerWithTaxiJob(src)
    local fare = activeFares[src]
    if not player or not fare then return end

    local now = os.time()
    if now < fare.earliestCompletion or now > fare.expiresAt then return end

    local ped = GetPlayerPed(src)
    local vehicle = NetworkGetEntityFromNetworkId(fare.vehicle)
    local destination = sharedConfig.npcLocations.deliverLocations[fare.destination]
    if ped == 0 or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    if #(GetEntityCoords(ped) - destination.xyz) > config.deliverLocationMaxDistance then return end

    local last = lastPayTime[src]
    if last and (now - last) < config.payCooldownSeconds then
        lib.print.warn(('qb_taxijob: NpcPay from source %s cooldown'):format(src))
        return
    end

    local paymentAmount = fare.payment
    activeFares[src] = nil
    local randomAmount = math.random(1, 5)
    local r1, r2 = math.random(1, 5), math.random(1, 5)
    if randomAmount == r1 or randomAmount == r2 then
        paymentAmount = paymentAmount + math.random(10, 20)
    end
    paymentAmount = math.min(paymentAmount, config.maxFare + 20)

    player.Functions.AddMoney('cash', paymentAmount)
    lastPayTime[src] = now
    if config.chanceItemEnabled and config.chanceItem and config.chancePercent and config.chancePercent > 0 then
        local chance = math.random(1, 100)
        if chance <= config.chancePercent then
            player.Functions.AddItem(config.chanceItem, 1, false)
            local itemData = ITEMS[config.chanceItem]
            if itemData then
                TriggerClientEvent('inventory:client:ItemBox', src, itemData, 'add')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastPayTime[src] = nil
    activeFares[src] = nil
end)
