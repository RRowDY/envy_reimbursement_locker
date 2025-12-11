local ESX = nil

local PROP_SPAWN_TIMEOUT = 10000
local MODEL_LOAD_TIMEOUT = 5000
local MAX_CHECK_DISTANCE_MULTIPLIER = 1.2
local DISTANCE_CHECK_INTERVAL = 50
local NEAR_DISTANCE_CHECK_INTERVAL = 0
local INTERACTION_COOLDOWN = 1000
local PROP_LOD_DISTANCE = 2000
local RESPAWN_CHECK_INTERVAL = 2000

local lockerProps = {}
local lockerData = {}
local lockerBlips = {}
local isNUIReady = false
local lockerUIVisible = false
local adminUIOpen = false
local lastInteractionTime = 0
local propsSpawned = false

local function InitializeESX()
    if ESX then return ESX end
    
    local success, result = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)
    
    if success and result then
        ESX = result
    end
    
    return ESX
end

local function WorldToScreen(coords)
    if not coords then return false, 0, 0 end
    
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if onScreen then
        local w, h = GetActiveScreenResolution()
        return true, screenX * w, screenY * h
    end
    return false, 0, 0
end

local function ShowNUIText(coords, text, distance, maxDistance)
    if not coords or not text then return false end
    
    local onScreen, screenX, screenY = WorldToScreen(coords)
    if onScreen then
        local extendedMaxDistance = maxDistance * 1.2
        local fadeStartDistance = maxDistance * 0.8
        local opacity = 1.0
        
        if distance > fadeStartDistance then
            local fadeRange = extendedMaxDistance - fadeStartDistance
            if fadeRange > 0 then
                local fadeProgress = (distance - fadeStartDistance) / fadeRange
                opacity = 1.0 - (fadeProgress * fadeProgress * (3.0 - 2.0 * fadeProgress))
            end
        end
        
        opacity = math.max(0.0, math.min(1.0, opacity))
        
        SendNUIMessage({
            action = 'show',
            x = screenX,
            y = screenY,
            text = text,
            opacity = opacity
        })
        lockerUIVisible = true
        return true
    else
        if lockerUIVisible then
            SendNUIMessage({ action = 'hide' })
            lockerUIVisible = false
        end
        return false
    end
end

local function CreateProp(propHash, coords, heading)
    RequestModel(propHash)
    
    local timeout = 0
    while not HasModelLoaded(propHash) and timeout < MODEL_LOAD_TIMEOUT do
        Wait(10)
        timeout = timeout + 10
    end
    
    if not HasModelLoaded(propHash) then
        return nil
    end
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local distanceToLocation = #(playerCoords - coords)
    
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    if distanceToLocation < 500.0 then
        local collisionTimeout = 0
        while not HasCollisionLoadedAroundEntity(playerPed) and collisionTimeout < 2000 do
            Wait(10)
            collisionTimeout = collisionTimeout + 10
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        end
    else
        Wait(500)
    end
    
    local prop = CreateObject(propHash, coords.x, coords.y, coords.z, false, true, false)
    Wait(200)
    
    if prop and prop ~= 0 then
        local attempts = 0
        while not DoesEntityExist(prop) and attempts < 10 do
            Wait(50)
            attempts = attempts + 1
            if not DoesEntityExist(prop) then
                prop = CreateObject(propHash, coords.x, coords.y, coords.z, false, true, false)
            end
        end
        
        if DoesEntityExist(prop) then
            SetEntityCoordsNoOffset(prop, coords.x, coords.y, coords.z, false, false, false)
            Wait(50)
            SetEntityHeading(prop, heading)
            Wait(50)
            FreezeEntityPosition(prop, true)
            SetEntityAsMissionEntity(prop, true, true)
            SetEntityCanBeDamaged(prop, false)
            SetEntityInvincible(prop, true)
            SetEntityLodDist(prop, PROP_LOD_DISTANCE)
            SetEntityCollision(prop, true, true)
            SetEntityAlpha(prop, 255, false)
            return prop
        end
    end
    
    SetModelAsNoLongerNeeded(propHash)
    return nil
end

local function SpawnLockerProps()
    if not Config or not Config.LockerLocations then return end
    if propsSpawned then return end
    
    -- Set flag immediately to prevent duplicate calls
    propsSpawned = true
    
    InitializeESX()
    
    local playerPed = PlayerPedId()
    local timeout = 0
    
    while not DoesEntityExist(playerPed) and timeout < PROP_SPAWN_TIMEOUT do
        Wait(100)
        timeout = timeout + 100
        playerPed = PlayerPedId()
    end
    
    if not DoesEntityExist(playerPed) then 
        propsSpawned = false
        return 
    end
    
    -- Clean up any existing blips before creating new ones
    for i, blip in ipairs(lockerBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    lockerBlips = {}
    
    Wait(1000)
    
    for i, location in ipairs(Config.LockerLocations) do
        if not location.coords then goto continue end
        
        local blip = AddBlipForCoord(location.coords.x, location.coords.y, location.coords.z)
        SetBlipSprite(blip, 568)
        SetBlipColour(blip, 2)
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Reimbursement Locker")
        EndTextCommandSetBlipName(blip)
        table.insert(lockerBlips, blip)
        
        if location.virtual or not location.prop then
            local locationKey = "location_" .. i
            
            lockerData[locationKey] = {
                propCoords = location.coords,
                textCoords = vector3(location.coords.x, location.coords.y, location.coords.z + 1.0),
                distance = location.distance or 2.0,
                label = 'Press ~eb~E~s~ to open locker',
                isVirtual = true
            }
            
            table.insert(lockerProps, locationKey)
            goto continue
        end
        
        local propHash = type(location.prop) == 'string' and GetHashKey(location.prop) or location.prop
        
        if not propHash or propHash == 0 then goto continue end
        
        local minCoords = vector3(0.0, 0.0, 0.0)
        local maxCoords = vector3(0.0, 0.0, 0.0)
        GetModelDimensions(propHash, minCoords, maxCoords)
        
        local propBottomOffset = -minCoords.z
        local centerX, centerY, centerZ = location.coords.x, location.coords.y, location.coords.z - propBottomOffset
        local baseHeading = location.heading or 0.0
        local headingOffset = location.headingOffset or 0.0
        local propHeading = (baseHeading + headingOffset) % 360.0
        
        local propCoords = vector3(centerX, centerY, centerZ)
        local prop = CreateProp(propHash, propCoords, propHeading)
        
        if prop then
            local propData = {
                propCoords = propCoords,
                textCoords = vector3(centerX, centerY, centerZ + 1.2),
                distance = location.distance or 2.0,
                label = 'Press ~eb~E~s~ to open locker',
                propHash = propHash,
                heading = propHeading
            }
            
            table.insert(lockerProps, prop)
            lockerData[prop] = propData
        else
            local locationKey = "location_" .. i .. "_failed"
            lockerData[locationKey] = {
                propCoords = propCoords,
                textCoords = vector3(centerX, centerY, centerZ + 1.2),
                distance = location.distance or 2.0,
                label = 'Press ~eb~E~s~ to open locker',
                propHash = propHash,
                heading = propHeading
            }
            table.insert(lockerProps, locationKey)
        end
        
        ::continue::
    end
    
    Wait(500)
    SetNuiFocus(false, false)
    isNUIReady = true
end

local function TrySpawnProps()
    if propsSpawned then return true end
    if not Config or not Config.LockerLocations then return false end
    if not InitializeESX() then return false end
    if not DoesEntityExist(PlayerPedId()) then return false end
    
    Wait(2000)
    SpawnLockerProps()
    return true
end

CreateThread(function()
    if not TrySpawnProps() then
        Wait(3000)
        TrySpawnProps()
    end
end)

RegisterNetEvent('esx:playerLoaded', function()
    TrySpawnProps()
end)

CreateThread(function()
    local lastRespawnCheck = 0
    
    while true do
        local sleep = DISTANCE_CHECK_INTERVAL
        local playerPed = PlayerPedId()
        local currentTime = GetGameTimer()
        local shouldCheckRespawn = (currentTime - lastRespawnCheck) >= RESPAWN_CHECK_INTERVAL
        
        if DoesEntityExist(playerPed) then
            local playerCoords = GetEntityCoords(playerPed)
            
            if playerCoords then
                local nearProp = nil
                local nearestDistance = math.huge
                local propsToRespawn = {}
                
                for prop, data in pairs(lockerData) do
                    local isValid = false
                    if data.isVirtual then
                        isValid = true
                    elseif type(prop) == 'number' then
                        isValid = DoesEntityExist(prop)
                        if not isValid and data.propHash and shouldCheckRespawn then
                            table.insert(propsToRespawn, { prop = prop, data = data })
                        end
                    elseif type(prop) == 'string' and data.propHash then
                        if data.propCoords then
                            local distance = #(playerCoords - data.propCoords)
                            local maxCheckDistance = (data.distance or 2.0) * MAX_CHECK_DISTANCE_MULTIPLIER * 3
                            
                            if distance < maxCheckDistance and shouldCheckRespawn then
                                table.insert(propsToRespawn, { prop = prop, data = data, distance = distance })
                            end
                        end
                    end
                    
                    if (isValid or (type(prop) == 'string' and data.propHash)) and data.propCoords then
                        local distance = #(playerCoords - data.propCoords)
                        local maxCheckDistance = data.distance * MAX_CHECK_DISTANCE_MULTIPLIER
                        
                        if distance < maxCheckDistance then
                            if distance < nearestDistance then
                                nearestDistance = distance
                                nearProp = prop
                            end
                            sleep = NEAR_DISTANCE_CHECK_INTERVAL
                        end
                    elseif not data.isVirtual and not data.propHash then
                        lockerData[prop] = nil
                    end
                end
                
                if #propsToRespawn > 0 then
                    lastRespawnCheck = currentTime
                    
                    for i, respawnInfo in ipairs(propsToRespawn) do
                        if i > 1 then Wait(50) end
                        
                        local oldProp = respawnInfo.prop
                        local data = respawnInfo.data
                        local propHash = data.propHash
                        
                        local newProp = CreateProp(propHash, data.propCoords, data.heading)
                        
                        if newProp then
                            lockerData[newProp] = data
                            
                            for j, p in ipairs(lockerProps) do
                                if p == oldProp then
                                    lockerProps[j] = newProp
                                    break
                                end
                            end
                            
                            if nearProp == oldProp then
                                nearProp = newProp
                            end
                            
                            lockerData[oldProp] = nil
                        end
                    end
                end
                
                if nearProp and lockerData[nearProp] then
                    local data = lockerData[nearProp]
                    if isNUIReady then
                        ShowNUIText(data.textCoords, data.label, nearestDistance, data.distance)
                    end
                    
                    local currentTime = GetGameTimer()
                    if IsControlJustReleased(0, 38) and (currentTime - lastInteractionTime) >= INTERACTION_COOLDOWN then
                        lastInteractionTime = currentTime
                        TriggerServerEvent('envy_reimbursement_locker:openLocker')
                    end
                else
                    if isNUIReady and lockerUIVisible then
                        SendNUIMessage({ action = 'hide' })
                        lockerUIVisible = false
                    end
                end
            end
        end
        
        Wait(sleep)
    end
end)

RegisterNetEvent('envy_reimbursement_locker:playAnimation', function()
    CreateThread(function()
        local animDict = 'mp_common'
        local animName = 'givetake1_a'
        local ped = PlayerPedId()
        
        if not DoesEntityExist(ped) then return end
        
        ClearPedTasksImmediately(ped)
        Wait(100)
        
        if ESX and ESX.Streaming then
            ESX.Streaming.RequestAnimDict(animDict, function()
                if HasAnimDictLoaded(animDict) then
                    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 2000, 50, 0.0, false, false, false)
                    Wait(2000)
                    ClearPedTasks(ped)
                    RemoveAnimDict(animDict)
                end
            end)
        else
            RequestAnimDict(animDict)
            local timeout = 0
            while not HasAnimDictLoaded(animDict) and timeout < 2000 do
                Wait(10)
                timeout = timeout + 10
            end
            
            if HasAnimDictLoaded(animDict) then
                TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, 2000, 50, 0.0, false, false, false)
                Wait(2000)
                ClearPedTasks(ped)
                RemoveAnimDict(animDict)
            end
        end
    end)
end)

RegisterNUICallback('nuiReady', function(data, cb)
    cb('ok')
end)

RegisterNUICallback('uiReady', function(data, cb)
    SetNuiFocus(true, true)
    cb('ok')
end)

RegisterNetEvent('envy_reimbursement_locker:openAdminUI', function()
    CreateThread(function()
        if adminUIOpen then
            adminUIOpen = false
            SendNUIMessage({ action = 'hideAdmin' })
            SetNuiFocus(false, false)
            Wait(100)
        end
        
        adminUIOpen = true
        SendNUIMessage({ action = 'showAdmin' })
        Wait(50)
        SetNuiFocus(true, true)
    end)
end)

RegisterNUICallback('searchLicense', function(data, cb)
    local license = data and data.license
    if not license or type(license) ~= 'string' or license == '' then
        cb('ok')
        return
    end
    
    license = string.gsub(license, '[^%w:]', '')
    
    if #license > 64 then
        cb('ok')
        return
    end
    
    ESX.TriggerServerCallback('envy_reimbursement_locker:getCharactersByLicense', function(result)
        if result then
            SendNUIMessage({
                action = 'characters',
                error = result.error,
                characters = result.characters
            })
        end
    end, license)
    
    cb('ok')
end)

RegisterNUICallback('selectCharacter', function(data, cb)
    local identifier = data and data.identifier
    if not identifier or type(identifier) ~= 'string' or identifier == '' then
        cb('ok')
        return
    end
    
    identifier = string.gsub(identifier, '[^%w:]', '')
    
    if #identifier > 128 then
        cb('ok')
        return
    end
    
    adminUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideAdmin' })
    
    ESX.TriggerServerCallback('envy_reimbursement_locker:openStashForCharacter', function(result)
        if result then
            TriggerEvent('ox_lib:notify', {
                type = result.success and 'success' or 'error',
                description = result.message or result.error or 'Failed to open stash'
            })
        end
    end, identifier)
    
    cb('ok')
end)

RegisterNUICallback('closeAdmin', function(data, cb)
    adminUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideAdmin' })
    cb('ok')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SendNUIMessage({ action = 'hide' })
        
        for i, prop in ipairs(lockerProps) do
            if type(prop) == 'number' and DoesEntityExist(prop) then
                DeleteEntity(prop)
            end
        end
        
        for i, blip in ipairs(lockerBlips) do
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
        
        lockerProps = {}
        lockerData = {}
        lockerBlips = {}
        propsSpawned = false
    end
end)
