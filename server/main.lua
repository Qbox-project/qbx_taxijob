lib.versionCheck('Qbox-project/qbx_taxijob')

local config = require 'config.server'
local sharedConfig = require 'config.shared'
local ITEMS = exports.ox_inventory:Items()

local lastPayTime = {}

local function getPlayerWithTaxiJob(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    if player.PlayerData.job.name ~= 'taxi' then
        return nil
    end
    return player
end

local function nearDeliverLocation(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for _, v in pairs(sharedConfig.npcLocations.deliverLocations) do
        local dist = #(coords - v.xyz)
        if dist < 20 then
            return true
        end
    end
    return false
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

RegisterNetEvent('qb-taxi:server:NpcPay', function(payment)
    local src = source
    local player = getPlayerWithTaxiJob(src)
    if not player then
        lib.print.warn(('qb_taxijob: NpcPay from source %s without taxi job'):format(src))
        return
    end

    if not nearDeliverLocation(src) then
        lib.print.warn(('qb_taxijob: NpcPay from source %s not near deliver location'):format(src))
        DropPlayer(src, 'Attempting To Exploit')
        return
    end

    local paymentAmount = tonumber(payment)
    if paymentAmount == nil or paymentAmount < 0 or paymentAmount > config.maxFare then
        lib.print.warn(('qb_taxijob: NpcPay from source %s invalid payment %s'):format(src, tostring(payment)))
        return
    end

    local now = os.time()
    local last = lastPayTime[src]
    if last and (now - last) < config.payCooldownSeconds then
        lib.print.warn(('qb_taxijob: NpcPay from source %s cooldown'):format(src))
        return
    end
    lastPayTime[src] = now

    local randomAmount = math.random(1, 5)
    local r1, r2 = math.random(1, 5), math.random(1, 5)
    if randomAmount == r1 or randomAmount == r2 then
        paymentAmount = paymentAmount + math.random(10, 20)
    end
    paymentAmount = math.min(paymentAmount, config.maxFare + 20)

    player.Functions.AddMoney('cash', paymentAmount)
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
end)
