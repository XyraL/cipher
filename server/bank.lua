-- ─────────────────────────────────────────────────────────────
-- Gang bank + dues. Bank funds are pooled; dues pull from members
-- on an interval into the pool.
-- ─────────────────────────────────────────────────────────────
Bank = {}

function Bank.Deposit(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid amount' end
    if not Gangs.HasPerm(src, 'manage_bank') then return false, 'no permission' end
    local gang = Gangs.GetBySource(src)
    if not gang then return false, 'no gang' end
    if Framework.GetMoney(src, Config.Dues.account) < amount then return false, 'not enough funds' end

    Framework.RemoveMoney(src, Config.Dues.account, amount, 'gang-deposit')
    gang.bank = gang.bank + amount
    MySQL.update('UPDATE cipher_gangs SET bank = bank + ? WHERE id = ?', { amount, gang.id })
    Gangs.Log(gang.id, ('%s deposited $%d'):format(Framework.GetName(src), amount))
    return true, gang.bank
end

function Bank.Withdraw(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid amount' end
    if not Gangs.HasPerm(src, 'manage_bank') then return false, 'no permission' end
    local gang = Gangs.GetBySource(src)
    if not gang then return false, 'no gang' end
    if gang.bank < amount then return false, 'gang bank too low' end

    gang.bank = gang.bank - amount
    MySQL.update('UPDATE cipher_gangs SET bank = bank - ? WHERE id = ?', { amount, gang.id })
    Framework.AddMoney(src, Config.Dues.account, amount, 'gang-withdraw')
    Gangs.Log(gang.id, ('%s withdrew $%d'):format(Framework.GetName(src), amount))
    return true, gang.bank
end

function Bank.SetDues(src, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if not Gangs.HasPerm(src, 'set_dues') then return false, 'no permission' end
    local gang = Gangs.GetBySource(src)
    if not gang then return false, 'no gang' end
    gang.dues_amount = amount
    MySQL.update('UPDATE cipher_gangs SET dues_amount = ? WHERE id = ?', { amount, gang.id })
    Gangs.Log(gang.id, ('Dues set to $%d'):format(amount))
    return true
end

-- ── dues ─────────────────────────────────────────────────────
-- Charges a single member exactly one cycle's dues and credits the gang
-- bank. Used by both the online sweep and the offline catch-up on login,
-- so a member is never charged twice for the same cycle.
local function chargeDues(src, cid, gang, amount)
    if Framework.GetMoney(src, Config.Dues.account) < amount then return false end
    Framework.RemoveMoney(src, Config.Dues.account, amount, 'gang-dues')
    gang.bank = gang.bank + amount
    MySQL.update('UPDATE cipher_gangs SET bank = bank + ? WHERE id = ?', { amount, gang.id })
    MySQL.update('UPDATE cipher_gang_members SET dues_paid_at = ? WHERE citizenid = ?', { os.time() * 1000, cid })
    if gang.members[cid] then gang.members[cid].dues_paid_at = os.time() * 1000 end
    return true
end

if Config.Dues.enabled then
    local intervalMs = Config.Dues.intervalHours * 60 * 60 * 1000

    -- Sweep: charges whoever's online when a cycle elapses.
    CreateThread(function()
        while true do
            Wait(intervalMs)
            local gangs = MySQL.query.await('SELECT id, dues_amount FROM cipher_gangs WHERE dues_amount > 0') or {}
            for _, g in ipairs(gangs) do
                local gang = Gangs.Get(g.id)
                if gang then
                    for cid in pairs(gang.members) do
                        local src = nil
                        for _, p in ipairs(GetPlayers()) do
                            if Framework.GetCitizenId(tonumber(p)) == cid then src = tonumber(p) break end
                        end
                        if src then chargeDues(src, cid, gang, g.dues_amount) end
                    end
                end
            end
        end
    end)

    -- Catch-up: a member who was offline when the sweep ran owes one
    -- cycle next time they log in. Capped at one cycle regardless of how
    -- long they were gone, so a month-long absence isn't a debt trap.
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        local src = player and player.PlayerData and player.PlayerData.source
        if not src then return end
        local cid = Framework.GetCitizenId(src)
        if not cid then return end
        local gang = Gangs.GetByCitizen(cid)
        if not gang or not gang.dues_amount or gang.dues_amount <= 0 then return end

        local member = gang.members[cid]
        local lastPaid = (member and member.dues_paid_at) or 0
        if (os.time() * 1000) - lastPaid < intervalMs then return end

        SetTimeout(3000, function() -- let money/identifiers finish loading
            if chargeDues(src, cid, gang, gang.dues_amount) then
                Framework.Notify(src, ('Gang dues charged: -$%d'):format(gang.dues_amount), 'inform')
            end
        end)
    end)
end
