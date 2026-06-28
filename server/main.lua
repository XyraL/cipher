-- ─────────────────────────────────────────────────────────────
-- Server entry: device usage + all callbacks the NUI relies on.
-- The UI never talks to gang logic directly — everything routes
-- through these validated callbacks/events.
-- ─────────────────────────────────────────────────────────────

-- Device is opened client-side via the item's client.export — see client/main.lua.

CreateThread(function()
    Gangs.SyncFromConfig()
end)

-- Open via command too (handy for testing without an item).
RegisterCommand(Config.OpenCommand, function(src)
    TriggerClientEvent('cipher:client:openDevice', src)
end, false)

-- ── Snapshot: everything the Gang Ops app needs in one round trip ──
lib.callback.register('cipher:getSnapshot', function(src)
    local cid = Framework.GetCitizenId(src)
    local hasGang = cid and Gangs.GetByCitizen(cid) ~= nil
    return {
        apps = Cipher.GetEnabledApps(hasGang),
        gang = Gangs.Snapshot(src),
        territories = Territory.GetAssigned(),
    }
end)

-- ── Membership ──
lib.callback.register('cipher:invite', function(src, targetId)
    local ok, err = Gangs.Invite(src, tonumber(targetId))
    return { ok = ok, error = err }
end)

lib.callback.register('cipher:kick', function(src, citizenid)
    local ok, err = Gangs.Kick(src, citizenid)
    return { ok = ok, error = err }
end)

lib.callback.register('cipher:setGrade', function(src, citizenid, grade)
    local ok, err = Gangs.SetGrade(src, citizenid, tonumber(grade))
    return { ok = ok, error = err }
end)

RegisterNetEvent('cipher:server:acceptInvite', function()
    local ok, err = Gangs.AcceptInvite(source)
    Framework.Notify(source, ok and 'You joined the gang.' or ('Could not join: ' .. tostring(err)),
        ok and 'success' or 'error')
end)

-- ── Bank ──
lib.callback.register('cipher:bankDeposit', function(src, amount)
    local ok, res = Bank.Deposit(src, amount)
    return { ok = ok, balance = ok and res or nil, error = not ok and res or nil }
end)

lib.callback.register('cipher:bankWithdraw', function(src, amount)
    local ok, res = Bank.Withdraw(src, amount)
    return { ok = ok, balance = ok and res or nil, error = not ok and res or nil }
end)

lib.callback.register('cipher:bankGetLedger', function(src)
    local gang = Gangs.GetBySource(src)
    if not gang then return {} end
    return Bank.GetLedger(gang.id)
end)

