-- ─────────────────────────────────────────────────────────────
-- Car boosting client: spawn the target vehicle locked with no owner/keys
-- and step back — qbx_core's own vehicle break-in/hotwire system handles
-- the actual theft, we don't run any custom minigame. We just watch for
-- the engine to actually start, then once it's near the buyer ped (and
-- the player's out of it), sell it. Fully standalone from the gang Tasks
-- system.
-- ─────────────────────────────────────────────────────────────
local hasTarget = GetResourceState('ox_target') == 'started'
local taskBlip = nil
local dropoffMarkerBlip = nil
local boostVehicle = nil
local boostVehicleNetId = nil
local buyerPed = nil
local buyerZoneId = nil
local engineWatchActive = false
local fallbackPrompt = nil
local guardPeds = {}
-- Set on the 'theft' stage update and reused at 'dropoff' — coop jobs only
-- say isLeader once, but both stages need to know whether THIS client is
-- the one responsible for spawning/interacting with anything.
local amJobLeader = true

local function clearTaskBlip()
    if taskBlip then RemoveBlip(taskBlip); taskBlip = nil end
    if dropoffMarkerBlip then RemoveBlip(dropoffMarkerBlip); dropoffMarkerBlip = nil end
end

local function clearFallbackPrompt()
    if fallbackPrompt then lib.hideTextUI(); fallbackPrompt = nil end
end

local function clearGuards()
    for _, ped in ipairs(guardPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    guardPeds = {}
end

local function clearBoostVehicle()
    if boostVehicle and DoesEntityExist(boostVehicle) then DeleteEntity(boostVehicle) end
    boostVehicle = nil
    boostVehicleNetId = nil
    engineWatchActive = false
    clearGuards()
end

-- Armed and hostile to the player — a friend can fight them off while
-- you steal the car, or you can just try to outrun them.
local function spawnGuards(spawn, def)
    if not def or not IsModelValid(def.model) then return end
    lib.requestModel(def.model)

    AddRelationshipGroup('cipher_boostguard')
    local hostileGroup = GetHashKey('cipher_boostguard')
    SetRelationshipBetweenGroups(5, hostileGroup, `PLAYER`)
    SetRelationshipBetweenGroups(5, `PLAYER`, hostileGroup)

    for i = 1, (def.count or 2) do
        local angle = (i / def.count) * 2 * math.pi
        local offset = (def.radius or 6.0)
        local x = spawn.x + math.cos(angle) * offset
        local y = spawn.y + math.sin(angle) * offset
        local ped = CreatePed(4, def.model, x, y, spawn.z, 0.0, true, true)
        SetPedRelationshipGroupHash(ped, hostileGroup)
        GiveWeaponToPed(ped, GetHashKey(def.weapon or 'WEAPON_PISTOL'), 250, false, true)
        SetPedCombatAttributes(ped, 46, true)
        SetPedCombatAttributes(ped, 5, true)
        SetPedFleeAttributes(ped, 0, false)
        SetPedSeeingRange(ped, 60.0)
        SetPedHearingRange(ped, 60.0)
        TaskCombatPed(ped, PlayerPedId(), 0, 16)
        guardPeds[#guardPeds + 1] = ped
    end
end

local function clearBuyerPed()
    if buyerZoneId then
        pcall(function() exports.ox_target:removeZone(buyerZoneId) end)
        buyerZoneId = nil
    end
    if buyerPed and DoesEntityExist(buyerPed) then DeleteEntity(buyerPed) end
    buyerPed = nil
end

-- Proximity+[E] fallback when ox_target isn't handling the sell prompt.
CreateThread(function()
    local shown = false
    while true do
        Wait(300)
        if fallbackPrompt then
            local near = #(GetEntityCoords(PlayerPedId()) - fallbackPrompt.coords) <= 2.0
            if near then
                if not shown then lib.showTextUI('[E] ' .. fallbackPrompt.label); shown = true end
                if IsControlJustReleased(0, 38) then fallbackPrompt.action() end
            elseif shown then
                lib.hideTextUI(); shown = false
            end
        elseif shown then
            lib.hideTextUI(); shown = false
        end
    end
end)

local function fireDispatch(coords)
    local d = Config.Boosting.dispatch
    if not d.enabled then return end
    local ok, payload = pcall(d.buildPayload, coords)
    if ok then TriggerEvent(d.event, payload) end
end

local function spawnTargetVehicle(spawn, model, plate)
    clearBoostVehicle()
    if not IsModelValid(model) then
        lib.notify({ description = ('Bad vehicle model for this job (%s) — tell an admin to fix config.lua'):format(model), type = 'error' })
        return
    end
    lib.requestModel(model)
    boostVehicle = CreateVehicle(model, spawn.x, spawn.y, spawn.z, spawn.w, true, true)
    -- Use the server-issued plate (shown on the tablet as a BOLO clue) so
    -- what you see in-game matches what you were told to look for. Also
    -- set it immediately regardless — other resources that hook vehicle-
    -- spawn events (e.g. mechanic/impound scripts keying off the plate)
    -- can grab a still-blank plate in that first tick and crash on their
    -- own query.
    SetVehicleNumberPlateText(boostVehicle, plate or ('BST%04d'):format(math.random(0, 9999)))
    SetVehicleDoorsLocked(boostVehicle, 2) -- locked, no keys — qbx_core's break-in system takes it from here
    SetVehicleEngineOn(boostVehicle, false, true, true)
    boostVehicleNetId = NetworkGetNetworkIdFromEntity(boostVehicle)
end

-- Guards don't spawn until someone's actually closing in on the real car —
-- keeps the search phase itself guard-free.
local function watchForGuardTrigger(spawn, def, triggerRadius)
    if not def then return end
    CreateThread(function()
        while boostVehicle and DoesEntityExist(boostVehicle) and #guardPeds == 0 do
            Wait(500)
            if #(GetEntityCoords(PlayerPedId()) - vec3(spawn.x, spawn.y, spawn.z)) <= (triggerRadius or 20.0) then
                spawnGuards(spawn, def)
                break
            end
        end
    end)
end

-- No minigame of our own to hook a "success" callback into — just poll
-- until the engine is actually running, then report it.
local function watchForEngineStart(dispatchDelay)
    engineWatchActive = true
    CreateThread(function()
        while engineWatchActive do
            Wait(500)
            if not boostVehicle or not DoesEntityExist(boostVehicle) then break end
            if GetIsVehicleEngineRunning(boostVehicle) then
                engineWatchActive = false
                local res = lib.callback.await('cipher:boosting:doHotwire', false, boostVehicleNetId)
                if res and res.ok then
                    local coords = GetEntityCoords(boostVehicle)
                    if dispatchDelay and dispatchDelay > 0 then
                        SetTimeout(dispatchDelay * 1000, function() fireDispatch(coords) end)
                    else
                        fireDispatch(coords)
                    end
                    lib.notify({ description = 'Stolen — get it to the buyer.', type = 'success' })
                    clearGuards() -- the heist part is over, no need for them to keep fighting
                else
                    lib.notify({ description = (res and res.error) or 'Failed', type = 'error' })
                end
            end
        end
    end)
end

local function doSellVehicle()
    if not boostVehicle then return end
    local res = lib.callback.await('cipher:boosting:doDropoff', false, boostVehicleNetId)
    if res and not res.ok then
        lib.notify({ description = res.error or 'Failed', type = 'error' })
        return
    end
    clearBoostVehicle()
    clearBuyerPed()
    clearTaskBlip()
end

local function setupBuyerPed(coords, model)
    clearBuyerPed()
    clearFallbackPrompt()
    if not IsModelValid(model) then
        lib.notify({ description = ('Bad buyer ped model (%s) — tell an admin to fix config.lua'):format(model), type = 'error' })
        return
    end
    lib.requestModel(model)
    buyerPed = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w or 0.0, true, true)
    SetEntityInvincible(buyerPed, true)
    SetBlockingOfNonTemporaryEvents(buyerPed, true)
    FreezeEntityPosition(buyerPed, true)
    TaskStartScenarioInPlace(buyerPed, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    local zoneOk = false
    if hasTarget then
        local ok, id = pcall(function()
            return exports.ox_target:addLocalEntity(buyerPed, {
                { name = 'cipher_sell_boost', label = 'Sell Vehicle', icon = 'fas fa-money-bill-wave',
                  onSelect = doSellVehicle },
            })
        end)
        if ok then zoneOk = true; buyerZoneId = id end
    end
    if not zoneOk then
        fallbackPrompt = { coords = coords, label = 'Sell Vehicle', action = doSellVehicle }
    end
end

RegisterNetEvent('cipher:client:boostUpdate', function(job)
    if not job then
        clearTaskBlip()
        clearFallbackPrompt()
        clearBoostVehicle()
        clearBuyerPed()
        return
    end

    if job.stage == 'theft' then
        clearTaskBlip()
        clearBuyerPed()
        amJobLeader = job.isLeader ~= false -- absent (solo) counts as leader
        if amJobLeader then
            spawnTargetVehicle(job.spawn, job.model, job.plate)
            if job.guards then watchForGuardTrigger(job.spawn, job.guards, job.guardTriggerRadius) end
            watchForEngineStart(job.dispatchDelay)
        elseif job.coop then
            lib.notify({ description = ('Crew job started — help fight off any guards near %s.'):format(job.spawn and 'the target' or ''), type = 'inform' })
        end

        -- No exact waypoint — just a search-zone circle. The model/plate
        -- BOLO clue shows in the tablet's active-job status instead.
        taskBlip = AddBlipForRadius(job.spawn.x, job.spawn.y, job.spawn.z, job.searchRadius or 150.0)
        SetBlipColour(taskBlip, 5)
        SetBlipAlpha(taskBlip, 130)
    elseif job.stage == 'dropoff' then
        clearTaskBlip()
        if amJobLeader then
            setupBuyerPed(job.dropoff, job.buyerPedModel or 'g_m_y_lost_01')
        end

        taskBlip = AddBlipForRadius(job.dropoff.x, job.dropoff.y, job.dropoff.z, job.dropoffRadius or 15.0)
        SetBlipColour(taskBlip, 2)
        SetBlipAlpha(taskBlip, 130)

        dropoffMarkerBlip = AddBlipForCoord(job.dropoff.x, job.dropoff.y, job.dropoff.z)
        SetBlipSprite(dropoffMarkerBlip, 67)
        SetBlipColour(dropoffMarkerBlip, 2)
        SetBlipRoute(dropoffMarkerBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Sell the Vehicle')
        EndTextCommandSetBlipName(dropoffMarkerBlip)
    end
end)

-- Co-op crew invite — same accept-dialog pattern as gang invites.
RegisterNetEvent('cipher:client:coopInvite', function(info)
    local accepted = lib.alertDialog({
        header = 'Co-op Boosting Invite',
        content = ('**%s** wants you to crew up on a boosting job.\n\nAccept?'):format(info.fromName or 'Someone'),
        centered = true,
        cancel = true,
        labels = { confirm = 'Accept', cancel = 'Decline' },
    })
    if accepted == 'confirm' then
        TriggerServerEvent('cipher:server:acceptCoopInvite')
    end
end)
