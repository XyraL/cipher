Config = {}

-- ─────────────────────────────────────────────────────────────
-- Device
-- ─────────────────────────────────────────────────────────────
Config.Debug = false

-- Item that opens the device (register this in ox_inventory items).
Config.DeviceItem = 'cipher_tablet'

-- Command to open the device (useful for testing without the item).
Config.OpenCommand = 'gangops'

-- ─────────────────────────────────────────────────────────────
-- Blackmarket chat
-- Anonymous codename per character (e.g. "ShadowFox-A1B2"), generated once
-- and persisted — never tied to gang label, so even gang affiliation stays
-- hidden. Open to anyone holding the tablet, gang or not: world chat is a
-- shared trading-floor feed, DMs are addressed by handle (never citizenid)
-- since that's the only identity anyone has.
-- ─────────────────────────────────────────────────────────────
Config.Chat = {
    enabled = true,
    worldHistoryLimit = 100,    -- messages kept/shown in the world feed
    dmHistoryLimit = 100,       -- messages kept/shown per DM thread
    maxMessageLength = 280,
    handleAdjectives = {
        'Shadow', 'Silent', 'Crimson', 'Iron', 'Ghost', 'Night', 'Static',
        'Hollow', 'Rusty', 'Velvet', 'Phantom', 'Cold',
    },
    handleNouns = {
        'Fox', 'Viper', 'Crow', 'Wolf', 'Raven', 'Hound', 'Cobra', 'Hawk',
        'Jackal', 'Lynx', 'Reaper', 'Wraith',
    },
}

-- ─────────────────────────────────────────────────────────────
-- Discord webhooks
-- Three separate channels by audience — leave any blank to disable it.
--   admin:    every action taken through /admintablet (the audit trail)
--   gang:     structural lifecycle — founded, disbanded, boss changed
--   economy:  player-driven money movement — deposits, withdrawals,
--             dues charged, dealer purchases (NOT admin overrides,
--             those already show in the admin log)
-- Get a webhook URL from a Discord channel: Edit Channel > Integrations
-- > Webhooks > New Webhook > Copy URL.
-- ─────────────────────────────────────────────────────────────
Config.Discord = {
    adminWebhook = '',
    gangWebhook = '',
    economyWebhook = '',
    botName = 'Cipher',
}

-- ─────────────────────────────────────────────────────────────
-- Admin tablet
-- A separate NUI view for staff: gang CRUD, rep/notoriety/bank/dues
-- overrides, territory reassignment. No physical item — just a command,
-- gated by an ACE permission. Grant it in server.cfg, e.g.:
--   add_ace group.admin cipher.admin allow
--   add_principal identifier.fivem:1234 group.admin
-- ─────────────────────────────────────────────────────────────
Config.AdminCommand = 'admintablet'
Config.AdminAce = 'cipher.admin'

-- ─────────────────────────────────────────────────────────────
-- Ranks & permissions
-- Higher grade = more authority. Grade 0 is the entry rank.
-- Permissions are checked by key throughout the server code.
-- ─────────────────────────────────────────────────────────────
Config.Permissions = {
    'invite',       -- invite new members
    'kick',         -- remove members
    'promote',      -- change member grades
    'manage_bank',  -- deposit/withdraw gang funds
    'manage_vault', -- access shared vault/armory
    'set_dues',     -- change weekly dues
    'place_objects', -- place/move crafting benches, peds, and the vault container
    -- Disbanding and territory assignment are admin-only — no in-game permission for either.
}

-- Default rank ladder applied when a gang is created.
-- Owners can rename ranks per-gang later; this is just the template.
Config.DefaultRanks = {
    [0] = { name = 'Prospect',    permissions = {} },
    [1] = { name = 'Soldier',     permissions = { 'manage_vault' } },
    [2] = { name = 'Lieutenant',  permissions = { 'invite', 'manage_vault' } },
    [3] = { name = 'Underboss',   permissions = { 'invite', 'kick', 'promote', 'manage_vault', 'manage_bank', 'set_dues' } },
    [4] = { name = 'Boss',        permissions = '*' }, -- '*' = all permissions, including place_objects
}

Config.MaxMembers = 30

-- ─────────────────────────────────────────────────────────────
-- Gangs (admin-defined only — there is no in-game "create gang" flow).
-- To add a gang: add an entry here, set `ensure cipher` to restart (or
-- run the server's `cipher` resource restart), and the gang is created/
-- updated automatically. `boss` is the citizenid who starts as Boss.
-- Renaming the label or changing `boss` here updates the DB on the next
-- restart; removing an entry does NOT delete the gang (do that manually
-- if you really mean to).
-- ─────────────────────────────────────────────────────────────
Config.Gangs = {
    -- ['ballas'] = {
    --     label = 'Ballas',
    --     boss = 'ABC12345',       -- citizenid
    --     territory = 'grove',     -- optional: starting zone, must exist in Config.Territories
    -- },
}

-- ─────────────────────────────────────────────────────────────
-- Notoriety
-- A gang-wide reputation meter. No idle decay — rep only ever drops from
-- the friendly-fire penalty below (or an admin adjustment). Tiers gate
-- bench unlocks, recipe unlocks, and zone size.
-- ─────────────────────────────────────────────────────────────
Config.Notoriety = {
    max = 10000,
    tiers = {
        { name = 'Unknown',   min = 0 },
        { name = 'Local',     min = 1000 },
        { name = 'Feared',    min = 3500 },
        { name = 'Notorious', min = 7000 },
    },
    -- Rep lost by a member who kills a fellow gang member. Detected via the
    -- victim's own client reporting their death + killer — see
    -- server/notoriety.lua's 'cipher:server:reportGangKill'.
    friendlyFirePenalty = 100,
    -- How much notoriety various actions grant. Other resources can add to
    -- this via the exported AddNotoriety(gangId, amount, reason). Task,
    -- drug-sale, and admin-adjustment rewards live with their own configs
    -- (Config.Tasks, Config.DrugSelling) — this is for anything else.
    rewards = {
        member_recruited = 50,
    },
}

-- ─────────────────────────────────────────────────────────────
-- Territory
-- There is no in-world capture. Zones are assigned to a gang entirely
-- through the admin tablet — including setting a zone's coords to the
-- admin's current position. This table is just an optional seed for
-- zones you want to exist on first boot; admins can also create zones
-- live without ever touching this file.
-- ─────────────────────────────────────────────────────────────
Config.ZoneRadius = 60.0  -- base radius of the map blip circle, in meters (at Unknown tier)
Config.ZoneRadiusGrowthPerTier = 20.0  -- added per tier the HOLDING gang has climbed — purely visual
Config.ZoneRadiusMaxTier = 'Feared'  -- zone size stops growing past this tier (Notorious is capped at the same size)

Config.Territories = {
    grove = {
        label = 'Grove Street',
        coords = vec3(-100.0, -1900.0, 25.0),
        color = 2,                  -- blip color
        income = 1500,              -- payout per cycle to the assigned gang
    },
    docks = {
        label = 'Elysian Docks',
        coords = vec3(110.0, -3000.0, 6.0),
        color = 38,
        income = 2200,
    },
    vinewood = {
        label = 'Vinewood Hills',
        coords = vec3(120.0, 560.0, 184.0),
        color = 5,
        income = 2000,
    },
}

Config.TerritoryIncomeMinutes = 60  -- how often assigned gangs are paid

-- ─────────────────────────────────────────────────────────────
-- Tier unlocks
-- When a gang's notoriety reaches a tier, the listed benches become
-- placeable by the Boss (or anyone with 'place_objects') — nothing spawns
-- automatically. There's only one bench overall now: it unlocks at Local,
-- and higher gang tiers unlock more recipes at that SAME bench rather than
-- needing a separate "Advanced Workbench" (see Config.Recipes' `tier`
-- field below). Each entry needs a stable `id`: it's how the gang's chosen
-- position for that specific bench is remembered in the DB.
-- ─────────────────────────────────────────────────────────────
-- Model names are plain strings, not backtick hash literals — placements
-- round-trip through a VARCHAR column in the DB, and a backtick literal
-- compiles to a number that gets silently stringified into garbage once
-- it hits that column. Natives accept model name strings directly, so
-- there's no need to hash them ourselves.
-- Peds are no longer placeable here — the dealer (Config.Dealer below) is
-- now an on-demand contact instead of a boss-placed fixture.
Config.TierUnlocks = {
    Local = {
        benches = {
            -- prop_tool_bench02 confirmed valid via /testmodel. Keeping the
            -- original id (local_crafting_bench) so anything already placed
            -- under it doesn't get orphaned.
            { id = 'local_crafting_bench', model = 'prop_tool_bench02', label = 'Crafting Bench' },
        },
    },
}

-- ─────────────────────────────────────────────────────────────
-- Tasks
-- Personal jobs any member can run solo for rep. Add as many as you want
-- here — no other file needs touching.
--
-- type = 'delivery' (default): target the pickup item (ox_target sphere
--   zone, or an [E] prompt without ox_target), then target a delivery ped
--   at the dropoff to hand it off. Each step is a server callback that
--   re-checks the player's actual position at that moment.
--   carryProp (optional) attaches a prop to the player between the two
--   stages — pure visual flavor, doesn't change validation at all.
--   dropoffPedModel — the ped spawned at the dropoff to deliver to.
-- type = 'kill': server picks a random spawnPoints entry, client spawns an
--   armed hostile NPC there and reports back when it's dead. The server
--   only trusts that report after minKillSeconds.
-- (Car boosting is NOT a task type — it's a fully separate system with its
-- own levels/XP/leaderboard, independent of gangs. See Config.Boosting.)
-- ─────────────────────────────────────────────────────────────
Config.Tasks = {
    {
        id = 'package_run',
        type = 'delivery',
        label = 'Package Run',
        pickup = vec3(-48.4, -1757.6, 29.4),
        dropoff = vec3(1196.5, -1287.6, 35.1),
        radius = 3.0,             -- meters to count as "close enough to target"
        reward = 25,              -- personal + gang rep on completion
        cooldownMinutes = 20,     -- per player, per task
        timeLimitSeconds = 420,   -- fail if not delivered within this window (0 = no limit)
        -- g_m_y_lost_01 confirmed valid via /testmodel — the ped you hand the package to.
        dropoffPedModel = 'g_m_y_lost_01',
    },
    {
        id = 'briefcase_run',
        type = 'delivery',
        label = 'Briefcase Run',
        pickup = vec3(-48.4, -1757.6, 29.4),
        dropoff = vec3(1196.5, -1287.6, 35.1),
        radius = 3.0,
        reward = 35,
        cooldownMinutes = 25,
        timeLimitSeconds = 420,
        -- prop_box_ammo04a confirmed valid via /testmodel.
        carryProp = 'prop_box_ammo04a',
        dropoffPedModel = 'g_m_y_lost_01',
    },
    {
        id = 'hit_contract',
        type = 'kill',
        label = 'Hit Contract',
        -- Placeholders — pick your own spots; these are not verified for
        -- this purpose. The dealer's vec4 list below is separate.
        spawnPoints = {
            vec3(425.1, -979.5, 30.7),
            vec3(-1037.2, -2737.8, 20.2),
            vec3(1698.9, 3242.2, 41.2),
        },
        pedModel = 'g_m_y_lost_01',
        weapon = 'WEAPON_PISTOL',
        reward = 40,
        cooldownMinutes = 30,
        timeLimitSeconds = 600,
        minKillSeconds = 5, -- reject a "target down" report faster than this — clearly not legit
    },
}

-- ─────────────────────────────────────────────────────────────
-- Car boosting
-- Fully standalone: no gang, no gang rep, open to everyone. Personal XP
-- and a level only this system cares about. Each level has its own
-- `vehicles` pool; at level N you can be assigned any vehicle from levels
-- 1..N (cumulative — higher levels don't lose access to earlier cars).
-- Completing a boost always pays `cash` for that specific vehicle and
-- grants `xp` toward the next level. The leaderboard ranks by lifetime
-- cars boosted, not level or cash.
--
-- Each vehicle's `spawns` is a list — one is picked at random each time,
-- so the same car doesn't always show up in the same spot. Add as many
-- as you want per vehicle; one is fine to start.
--
-- Placeholders — pick real model names (verify with /testmodel) and real
-- spots on your map before relying on any of this.
-- ─────────────────────────────────────────────────────────────
Config.Boosting = {
    enabled = true,
    -- One is picked at random per job — confirmed ground-level by user testing.
    dropoffs = {
        vec4(718.0250, -1084.7808, 22.3153, 93.0969),
        vec4(-733.6343, -286.6304, 36.9487, 266.3384),
        vec4(-1223.1425, -704.7170, 22.5838, 326.9461),
    },
    dropoffRadius = 15.0,    -- bring the stolen vehicle within this range of the buyer ped
    -- No custom lockpick/hotwire minigame here — the vehicle just spawns
    -- locked with no owner/keys, and qbx_core's own vehicle break-in/hotwire
    -- system handles the actual theft. We just watch for the engine to
    -- actually start (however it gets there) and move on to the drop-off.
    --
    -- No exact waypoint to the car — the tablet shows a search-zone circle
    -- plus the model + plate as a BOLO-style clue, and you have to actually
    -- drive around and spot it. Guards don't spawn until you get close, so
    -- the search phase itself is guard-free.
    searchRadius = 150.0,
    guardTriggerRadius = 20.0,
    cooldownMinutes = 10,
    timeLimitSeconds = 480,
    cashAccount = 'cash',
    -- g_m_y_lost_01 confirmed valid via /testmodel — the buyer you hand the car to at drop-off.
    buyerPedModel = 'g_m_y_lost_01',
    recentActivityLimit = 10,

    -- Extra confirmed-ground-level spots, shared across every vehicle below
    -- for spawn variety — which specific car lands at which spot doesn't
    -- matter mechanically, so they're just pooled rather than tied 1:1.
    extraSpawns = {
        vec4(-1173.4260, -1387.2906, 4.2710, 124.7875),
        vec4(-810.3212, -1290.9629, 4.3935, 350.7089),
        vec4(-423.9217, -30.6549, 45.6205, 356.8702),
        vec4(-101.1543, -57.3651, 55.7671, 256.1645),
        vec4(195.9602, -250.7542, 65.1311, 70.3728),
        vec4(872.9670, -46.2850, 78.1578, 236.3890),
    },

    -- cooldownMinutes per level overrides the global one above — leave it
    -- off a level to just inherit the global default. perkPoints is
    -- awarded once, the moment you cross into that level.
    levels = {
        {
            level = 1, label = 'Joyrider', xpNeeded = 0, perkPoints = 1,
            vehicles = {
                { model = 'blista', label = 'Blista', spawns = { vec4(-44.0, -1752.0, 29.4, 230.0) }, cash = 600, xp = 15 },
                -- confirmed ground-level by user testing.
                { model = 'asea', label = 'Asea', spawns = { vec4(1188.0234, -1287.5217, 34.5036, 264.1924) }, cash = 500, xp = 12 },
            },
        },
        {
            level = 2, label = 'Wheelman', xpNeeded = 100, cooldownMinutes = 8, perkPoints = 1,
            vehicles = {
                { model = 'sultan', label = 'Sultan', spawns = { vec4(425.0, -979.0, 30.7, 0.0) }, cash = 1200, xp = 22 },
            },
        },
        {
            level = 3, label = 'Pro', xpNeeded = 300, cooldownMinutes = 6, perkPoints = 2,
            vehicles = {
                { model = 'sultanrs', label = 'Sultan RS', spawns = { vec4(-1037.0, -2737.0, 20.2, 0.0) }, cash = 2200, xp = 35 },
            },
        },
    },

    -- Perks: passive, permanent unlocks bought with perk_points (never
    -- consumed/used-up, no inventory items involved). Each `type` is a
    -- modifier the server applies at the relevant moment:
    --   cash_bonus_pct        — +value% on every sale's cash payout
    --   guard_reduction       — -value guards spawned per job (floor 0)
    --   dispatch_delay        — dispatch fires `value` seconds after the
    --                           theft instead of instantly (more time to flee)
    --   cooldown_reduction_pct — -value% off your current cooldown (stacks
    --                           with the level-based cooldown above)
    perks = {
        { id = 'fence_connections', label = 'Fence Connections', description = '+10% cash on every sale',
          cost = 1, type = 'cash_bonus_pct', value = 10 },
        { id = 'fence_connections_2', label = 'Better Fence Connections', description = 'Another +15% cash on every sale',
          cost = 2, type = 'cash_bonus_pct', value = 15 },
        { id = 'thin_the_crowd', label = 'Thin the Crowd', description = '-1 guard near every target vehicle',
          cost = 1, type = 'guard_reduction', value = 1 },
        { id = 'ghost_protocol', label = 'Ghost Protocol', description = 'Removes guards near target vehicles entirely',
          cost = 2, type = 'guard_reduction', value = 99 },
        { id = 'signal_jammer', label = 'Signal Jammer', description = 'Delays the police dispatch alert by 20s after a theft',
          cost = 2, type = 'dispatch_delay', value = 20 },
        { id = 'quick_fingers', label = 'Quick Fingers', description = '-20% cooldown between jobs',
          cost = 1, type = 'cooldown_reduction_pct', value = 20 },
    },

    -- Police dispatch hook: fires the moment a hotwire succeeds (the theft
    -- itself), client-side, since most dispatch resources expect to be
    -- triggered with the calling player's own context. The event
    -- name/payload below is just an example shaped for cd_dispatch —
    -- change both to match whatever dispatch resource your server
    -- actually runs. Set enabled = false to skip this entirely.
    dispatch = {
        enabled = false,
        event = 'cd_dispatch:AddNotification',
        buildPayload = function(coords)
            return {
                job_name = 'cipher_boost',
                job_label = 'Stolen Vehicle',
                coords = coords,
                icon = 'fa-solid fa-car-side',
                offset = false,
                length = 4,
                scanLine = { sCode = '10-46', message = 'Vehicle theft reported' },
                flashes = 1,
                sound = 'one',
                alert_color = 22,
                blip = { sprite = 526, scale = 1.2, colour = 1 },
                jobs = { 'police' },
                time = 5,
            }
        end,
    },

    -- Guards: armed hostile peds spawn near the target vehicle while
    -- you're stealing it — a friend can come fight them off while you
    -- work, or you can try to outrun/lose them. Despawn once the engine
    -- starts (or the job ends any other way). Set enabled = false to skip.
    guards = {
        enabled = true,
        count = 2,
        radius = 6.0,           -- how far from the vehicle they spawn
        model = 'g_m_y_lost_01',
        weapon = 'WEAPON_PISTOL',
    },

    -- Achievements: computed live from cipher_boost_stats — no separate
    -- "earned" tracking needed, just a threshold check every time status
    -- is fetched. type = 'total_boosted' or 'level'.
    achievements = {
        { id = 'first_boost', label = 'First Blood', description = 'Boost your first vehicle', type = 'total_boosted', value = 1 },
        { id = 'ten_boosts', label = 'Joyride Junkie', description = 'Boost 10 vehicles', type = 'total_boosted', value = 10 },
        { id = 'fifty_boosts', label = 'Professional', description = 'Boost 50 vehicles', type = 'total_boosted', value = 50 },
        { id = 'hundred_boosts', label = 'Legend', description = 'Boost 100 vehicles', type = 'total_boosted', value = 100 },
        { id = 'max_level', label = 'Kingpin', description = 'Reach the max level', type = 'level', value = 3 },
    },

    -- Wanted vehicles: a config-defined pool, several active at once
    -- (`activeCount`), refreshed regularly (`rotateMinutes`) — not a rare
    -- one-off. Available to ANY level, on top of (not instead of) the
    -- normal level-gated pool, for a flat bonus payout.
    wanted = {
        enabled = true,
        activeCount = 2,
        rotateMinutes = 30,
        pool = {
            { model = 'sultanrs', label = 'Wanted: Sultan RS', spawns = { vec4(-1037.0, -2737.0, 20.2, 0.0) }, cash = 3500, xp = 50 },
            { model = 'sultan', label = 'Wanted: Sultan', spawns = { vec4(425.0, -979.0, 30.7, 0.0) }, cash = 2000, xp = 30 },
            { model = 'blista', label = 'Wanted: Blista', spawns = { vec4(-44.0, -1752.0, 29.4, 230.0) }, cash = 1200, xp = 20 },
        },
    },

    -- Co-op: invite a specific player (like a gang invite) to crew up on a
    -- harder job from a separate, higher-value vehicle pool. More guards,
    -- a tighter clock, and dispatch always fires instantly regardless of
    -- anyone's Signal Jammer perk — teamwork doesn't get the stealth bonus.
    -- Cash payout gets a bonus on top, then splits evenly across the crew;
    -- XP is NOT split — every crew member gets the full amount.
    coop = {
        enabled = true,
        maxCrewSize = 3,
        timeLimitSeconds = 300,       -- shorter than solo's timeLimitSeconds
        extraGuards = 2,              -- added on top of Config.Boosting.guards.count
        cashBonusPct = 25,            -- bonus applied before splitting across the crew
        vehicles = {
            { model = 'sultanrs', label = 'Co-op: Sultan RS', spawns = { vec4(-1037.0, -2737.0, 20.2, 0.0) }, cash = 4000, xp = 60 },
        },
    },
}

-- ─────────────────────────────────────────────────────────────
-- Bank & dues
-- ─────────────────────────────────────────────────────────────
Config.Dues = {
    enabled = true,
    defaultAmount = 0,              -- per member, per cycle (0 = off until set)
    intervalHours = 168,            -- weekly
    account = 'bank',               -- which member account dues pull from
}

-- ─────────────────────────────────────────────────────────────
-- Vault / armory
-- Backed by an ox_inventory stash, namespaced per gang. It's a physical
-- container the Boss places in the world (same flow as bench/ped
-- placement) — there is no remote "open from tablet" option.
-- ─────────────────────────────────────────────────────────────
Config.Vault = {
    slots = 50,
    maxWeight = 100000,             -- grams
    -- prop_box_wood05a confirmed valid via /testmodel on this server.
    model = 'prop_box_wood05a',
    label = 'Gang Vault',
}

-- ─────────────────────────────────────────────────────────────
-- Crafting
-- Available at any placed bench — there's only one bench, but higher gang
-- tiers unlock more recipes at it (instead of needing a separate
-- "Advanced Workbench"). `tier` is which Config.Notoriety tier the gang
-- needs; omit it (or use the lowest tier name) for something available
-- the moment the bench itself is unlocked. Simple item conversions:
-- consume `inputs`, produce `output`. Item names must match your
-- ox_inventory items.lua exactly — the ones below assume ox_inventory's
-- stock default items (metalscrap/plastic/rope/lockpick); double check
-- they exist on your server (or just rename) before relying on these as
-- more than a test. `time` is the crafting delay in ms.
-- ─────────────────────────────────────────────────────────────
Config.Recipes = {
    {
        id = 'lockpick',
        label = 'Lockpick',
        tier = 'Local',
        inputs = { { item = 'metalscrap', count = 5 }, { item = 'plastic', count = 2 } },
        output = { item = 'lockpick', count = 1 },
        time = 5000,
    },
    {
        id = 'rope',
        label = 'Rope',
        tier = 'Local',
        inputs = { { item = 'plastic', count = 4 } },
        output = { item = 'rope', count = 1 },
        time = 4000,
    },
    {
        id = 'advanced_lockpick',
        label = 'Advanced Lockpick',
        tier = 'Notorious', -- example of a higher-tier unlock at the same bench
        inputs = { { item = 'metalscrap', count = 8 }, { item = 'plastic', count = 4 } },
        output = { item = 'lockpick', count = 3 },
        time = 7000,
    },
}

-- ─────────────────────────────────────────────────────────────
-- Drug selling
-- /selldrug — works anywhere, not just gang territory. Client checks for
-- a nearby NPC ped (not a real transaction partner, just a "someone's
-- here to sell to" gate); server validates the item count and cooldown
-- and pays out. Rep only applies if the seller is in a gang. Defaults to
-- ox_inventory's stock drug items — change freely, names just need to
-- match your items.lua.
-- ─────────────────────────────────────────────────────────────
Config.DrugSelling = {
    enabled = true,
    command = 'selldrug',
    sellRadius = 4.0,         -- need an NPC ped within this many meters
    cooldownSeconds = 30,     -- per player
    account = 'cash',
    items = {
        { item = 'weed_brick', label = 'Weed Brick', price = 150, rep = 8 },
        { item = 'coke_brick', label = 'Cocaine Brick', price = 280, rep = 12 },
        { item = 'meth_brick', label = 'Meth Brick', price = 220, rep = 10 },
    },
}

-- ─────────────────────────────────────────────────────────────
-- Dealer
-- On-demand, not placed: any gang member hits "Call Dealer" on the
-- tablet. One call at a time, server-wide — a global cooldown, not a
-- per-player one, so the next call is up for grabs to whoever's first
-- after it expires. The ped spawns at a random spot from `spawnPoints`
-- and despawns after `timeoutMinutes` if nobody reaches it. Stock rotates
-- on `rotateMinutes` with a randomized price per pool entry. Item names
-- must match your ox_inventory items.lua exactly.
-- ─────────────────────────────────────────────────────────────
Config.Dealer = {
    cooldownHours = 6,
    timeoutMinutes = 10,
    rotateMinutes = 60,
    stockSize = 4,        -- how many pool entries are in stock at once
    account = 'cash',      -- which money account purchases pull from
    pedModel = 'g_m_y_lost_01',
    spawnPoints = {
        vec4(328.1793, -1582.1826, 32.7972, 139.3918),
        vec4(-174.5912, -726.4565, 30.4540, 343.6068),
        vec4(-1686.6917, -266.8215, 51.8833, 2.8311),
        vec4(-1312.9951, 326.1961, 65.4932, 297.0952),
        vec4(314.5848, 2859.3018, 43.5845, 309.9282),
    },
    pool = {
        -- { item = 'weapon_pistol', label = 'Pistol', priceMin = 2000, priceMax = 3500 },
        -- { item = 'weed_brick', label = 'Weed Brick', priceMin = 200, priceMax = 400 },
    },
}
