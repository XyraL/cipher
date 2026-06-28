-- ─────────────────────────────────────────────────────────────
-- Tasks: solo jobs members run for personal + gang rep.
-- 'delivery' (default type): the client targets the pickup item, then
-- targets a delivery ped to hand it off. Each step is a server callback
-- that re-checks the player's actual position at that moment — not a
-- continuous poll, but still never trusts the client's say-so alone.
-- 'kill': server picks a random spawn point and tells the client to spawn
-- an armed NPC there; the client reports back when it's dead, and the
-- server only accepts that report after a sane minimum time has passed.
-- That's a real trust concession (the client could lie about the kill),
-- bounded by minKillSeconds plus the existing cooldown/time-limit system.
-- (Car boosting is its own standalone system — see server/boosting.lua —
-- not a task type, since it has no gang/rep tie-in at all.)
-- ─────────────────────────────────────────────────────────────
Tasks = {}

local active = {}     -- [src] = { id, stage, startedAt, spawn (kill only) }
local byId = {}
for _, t in ipairs(Config.Tasks) do byId[t.id] = t end

local function dist(a, b)
    return #(a - b)
end

local function cooldownRemaining(citizenid, taskId)
    local def = byId[taskId]
    if not def or not def.cooldownMinutes or def.cooldownMinutes <= 0 then return 0 end
    local row = MySQL.single.await(
        'SELECT completed_at FROM cipher_task_cooldowns WHERE citizenid = ? AND task_id = ?',
        { citizenid, taskId })
    if not row then return 0 end
    local readyAt = row.completed_at + (def.cooldownMinutes * 60 * 1000)
    return math.max(0, readyAt - os.time() * 1000)
end

-- ── available list for the UI ──
function Tasks.GetAvailable(src)
    local cid = Framework.GetCitizenId(src)
    local list = {}
    for _, t in ipairs(Config.Tasks) do
        list[#list + 1] = {
            id = t.id,
            label = t.label,
            type = t.type or 'delivery',
            reward = t.reward,
            cooldownMs = cid and cooldownRemaining(cid, t.id) or 0,
        }
    end
    return list, active[src]
end

-- ── accept ──
function Tasks.Accept(src, taskId)
    local def = byId[taskId]
    if not def then return false, 'unknown task' end
    if active[src] then return false, 'already on a task' end

    local cid = Framework.GetCitizenId(src)
    if not cid then return false, 'no character' end
    local gang = Gangs.GetByCitizen(cid)
    if not gang then return false, 'no gang' end
    if cooldownRemaining(cid, taskId) > 0 then return false, 'on cooldown' end

    Gangs.Log(gang.id, ('%s started "%s"'):format(Framework.GetName(src) or cid, def.label))

    if (def.type or 'delivery') == 'kill' then
        local spawn = def.spawnPoints[math.random(#def.spawnPoints)]
        active[src] = { id = taskId, stage = 'kill', startedAt = os.time() * 1000, spawn = spawn }
        TriggerClientEvent('cipher:client:taskUpdate', src,
            { id = taskId, type = 'kill', spawn = spawn, pedModel = def.pedModel, weapon = def.weapon })
    else
        active[src] = { id = taskId, stage = 'pickup', startedAt = os.time() * 1000 }
        TriggerClientEvent('cipher:client:taskUpdate', src,
            { id = taskId, type = 'delivery', stage = 'pickup', pickup = def.pickup, dropoff = def.dropoff, carryProp = def.carryProp })
    end
    return true
end

function Tasks.Cancel(src)
    if not active[src] then return false, 'no active task' end
    active[src] = nil
    TriggerClientEvent('cipher:client:taskUpdate', src, nil)
    return true
end

local function completeTask(src, def)
    local cid = Framework.GetCitizenId(src)
    active[src] = nil
    TriggerClientEvent('cipher:client:taskUpdate', src, nil)
    if not cid then return end
    local gang = Gangs.GetByCitizen(cid)
    Gangs.AddMemberRep(cid, def.reward, 'task:' .. def.id)
    MySQL.insert(
        'INSERT INTO cipher_task_cooldowns (citizenid, task_id, completed_at) VALUES (?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE completed_at = ?',
        { cid, def.id, os.time() * 1000, os.time() * 1000 })
    Framework.Notify(src, ('Job complete — +%d rep.'):format(def.reward), 'success')
    if gang then
        Gangs.Log(gang.id, ('%s completed "%s" (+%d rep)'):format(Framework.GetName(src) or cid, def.label, def.reward))
    end
end

-- Client reports the target's death — only trusted after minKillSeconds
-- and only while that exact job is actually in its 'kill' stage.
function Tasks.ReportKill(src)
    local job = active[src]
    if not job or job.stage ~= 'kill' then return false, 'no active kill task' end
    local def = byId[job.id]
    if not def then return false, 'unknown task' end

    local elapsed = (os.time() * 1000) - job.startedAt
    if elapsed < (def.minKillSeconds or 5) * 1000 then return false, 'too fast' end

    completeTask(src, def)
    return true
end

-- Player targeted the pickup item — re-check they're actually near it
-- right now (not continuously polled, but not just taken on faith either).
function Tasks.DoPickup(src)
    local job = active[src]
    if not job or job.stage ~= 'pickup' then return false, 'no active pickup' end
    local def = byId[job.id]
    if not def then return false, 'unknown task' end

    local ped = GetPlayerPed(src)
    if ped == 0 or dist(GetEntityCoords(ped), def.pickup) > (def.radius or 3.0) then
        return false, 'too far from the pickup'
    end

    job.stage = 'dropoff'
    TriggerClientEvent('cipher:client:taskUpdate', src,
        { id = job.id, type = 'delivery', stage = 'dropoff', pickup = def.pickup, dropoff = def.dropoff,
          carryProp = def.carryProp, dropoffPedModel = def.dropoffPedModel })
    Framework.Notify(src, 'Picked up — deliver it.', 'success')
    return true
end

-- Player targeted the delivery ped at the dropoff.
function Tasks.DoDropoff(src)
    local job = active[src]
    if not job or job.stage ~= 'dropoff' then return false, 'no active dropoff' end
    local def = byId[job.id]
    if not def then return false, 'unknown task' end

    local ped = GetPlayerPed(src)
    if ped == 0 or dist(GetEntityCoords(ped), def.dropoff) > (def.radius or 3.0) then
        return false, 'too far from the dropoff'
    end

    completeTask(src, def)
    return true
end

-- ── time-limit enforcement (still needs a periodic check) ──
CreateThread(function()
    while true do
        Wait(1500)
        for src, job in pairs(active) do
            if GetPlayerName(src) == nil then
                active[src] = nil
            else
                local def = byId[job.id]
                if def.timeLimitSeconds and def.timeLimitSeconds > 0 then
                    if (os.time() * 1000) - job.startedAt > def.timeLimitSeconds * 1000 then
                        active[src] = nil
                        TriggerClientEvent('cipher:client:taskUpdate', src, nil)
                        Framework.Notify(src, 'Job window expired.', 'error')
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    active[source] = nil
end)

lib.callback.register('cipher:tasks:getAvailable', function(src)
    local tasks, activeJob = Tasks.GetAvailable(src)
    return { tasks = tasks, active = activeJob }
end)

lib.callback.register('cipher:tasks:accept', function(src, taskId)
    local ok, err = Tasks.Accept(src, taskId)
    return { ok = ok, error = err }
end)

lib.callback.register('cipher:tasks:cancel', function(src)
    local ok, err = Tasks.Cancel(src)
    return { ok = ok, error = err }
end)

lib.callback.register('cipher:tasks:reportKill', function(src)
    local ok, err = Tasks.ReportKill(src)
    return { ok = ok, error = err }
end)

lib.callback.register('cipher:tasks:doPickup', function(src)
    local ok, err = Tasks.DoPickup(src)
    return { ok = ok, error = err }
end)

lib.callback.register('cipher:tasks:doDropoff', function(src)
    local ok, err = Tasks.DoDropoff(src)
    return { ok = ok, error = err }
end)
