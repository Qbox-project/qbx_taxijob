local ITEMS = exports.ox_inventory:Items()

local function nearTaxi(src)
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    for _, v in pairs(Config.NPCLocations.DeliverLocations) do
        local dist = #(coords - v.xyz)
        if dist < 20 then
            return true
        end
    end
end

lib.callback.register('qb-taxi:server:spawnTaxi', function(source, model, coords)
    local netId = SpawnVehicle(source, model, coords, true)
    if not netId or netId == 0 then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return end

    local plate = 'TAXI' .. math.random(1000, 9999)
    SetVehicleNumberPlateText(veh, plate)
    TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate)
    return netId
end)

RegisterNetEvent('qb-taxi:server:NpcPay', function(payment)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if player.PlayerData.job.name == 'taxi' then
        if nearTaxi(src) then
            local randomAmount = math.random(1, 5)
            local r1, r2 = math.random(1, 5), math.random(1, 5)
            if randomAmount == r1 or randomAmount == r2 then payment = payment + math.random(10, 20) end
            player.Functions.AddMoney('cash', payment)
            local chance = math.random(1, 100)
            if chance < 26 then
                player.Functions.AddItem('cryptostick', 1, false)
                TriggerClientEvent('inventory:client:ItemBox', src, ITEMS['cryptostick'], 'add')
            end
        else
            DropPlayer(src, 'Attempting To Exploit')
        end
    else
        DropPlayer(src, 'Attempting To Exploit')
    end
end)
