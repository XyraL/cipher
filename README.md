# Cipher — Gang Ops (v0.1)

A modular encrypted criminal device for **QBox (qbx_core)** and **QBCore (qb-core)**.
The device is a shell that hosts apps; current apps are **Gang Ops**,
**Blackmarket**, and **Boosting**. Ship future apps (Dark Web Market,
Contracts Board, etc.) by registering them in `shared/apps.lua` — no changes
to the shell required.

Visually it leans hard into a cyberpunk/hacker-terminal look: scanlines,
glowing corner brackets, a typed boot sequence on open (the admin tablet
gets its own red-accented variant), and glitch-style transitions between
apps/tabs. The app rail uses real icons + labels, not abbreviations.

## Requirements
- `ox_lib`
- `oxmysql`
- `ox_inventory` (for the vault/armory + the device item)
- `ox_target` (optional) — gives the vault, benches, and the dealer ped a
  proper target interaction. Falls back to an `[E]` proximity prompt if not started.
- Either `qbx_core` **or** `qb-core` — the bridge auto-detects which.

## Install
1. Drop the `cipher` folder into your `resources`.
2. Import `sql/cipher.sql` into your database.
3. Add an item named `cipher_tablet` to your `ox_inventory` items (or change
   `Config.DeviceItem`). Give yourself one, or use the `/gangops` command.
4. Add `ensure cipher` to your `server.cfg` (after ox_lib, oxmysql, your framework,
   and ox_inventory).
5. Tune `config.lua` — ranks, permissions, territory zones, notoriety, dues.

## What's wired
- Framework bridge with one unified API (`bridge/framework.lua`).
- Gangs are admin-defined only — invite/accept, kick, promote/demote happen
  in-game; create/disband/boss changes happen on the admin tablet.
- Rank + permission system (config-driven, per-gang ranks in DB).
- Personal rep per member, feeding a gang-wide notoriety total with tiers.
  No idle decay — the only way rep drops is the friendly-fire penalty
  (`Config.Notoriety.friendlyFirePenalty`, killing your own gang member) or
  an admin adjustment. Exported as
  `exports.cipher:AddNotoriety(gangId, amount, reason)` so other resources
  can feed it.
- Territory: zones are assigned to a gang entirely through the admin tablet —
  there is no in-world capture. Admins can create a zone and set its coords to
  their current position, rename it, set its per-cycle income, and assign or
  clear its holder. Assigned zones pay out on `Config.TerritoryIncomeMinutes`.
  The map blip radius grows with the holding gang's tier
  (`Config.ZoneRadiusGrowthPerTier`) — purely visual.
- Tier unlocks: once a gang's notoriety reaches a tier, the Boss (or anyone
  with `place_objects`) can place that tier's benches anywhere — open the
  tablet's **Unlocks** tab, hit Place, then use scroll to set distance, Q/E to
  rotate, Enter to confirm. Locked entries show the tier/rep still needed.
- Vault: a physical container, not a remote button. Place it from the same
  Unlocks tab; opens via `ox_target` (or an `[E]` prompt without it) when
  standing near it. Backed by a per-gang `ox_inventory` stash.
- Crafting: targeting a placed bench opens a dedicated themed panel (not a
  plain list) with a cinematic camera push-in and a progress-ring "Craft"
  button. There's one bench, but recipes (`Config.Recipes`) each carry a
  `tier` requirement, so higher gang tiers unlock more recipes at that same
  bench instead of needing a separate "Advanced Workbench". Locked recipes
  show grayed out with their tier requirement. Inputs/outputs are validated
  server-side against the player's actual inventory.
- Dealer: on-demand, not placed. The tablet's **Tasks** tab has a "Call Dealer"
  button — one call at a time server-wide on `Config.Dealer.cooldownHours`
  (a global cooldown, not per-player). The ped spawns at a random
  `Config.Dealer.spawnPoints` entry and despawns after `timeoutMinutes` if
  nobody reaches it. Stock rotates independently on `rotateMinutes` with a
  randomized price per `Config.Dealer.pool` entry. Empty by default; add pool
  entries to enable it.
- Drug selling: target any nearby NPC ped (`ox_target`, or `/selldrug` to grab
  the nearest one without it) — works anywhere, not gated to territory. A 5s
  progress bar plays out the deal, then the server validates the actual item
  count and a per-player cooldown before paying cash (+ rep if the seller's in
  a gang). Defaults to a few common drug item names — rename to match your
  `ox_inventory` items.lua.
- Tasks: solo jobs for personal + gang rep, fully server-validated.
  - `type = 'delivery'` (default): target the pickup item, then target a
    delivery ped at the dropoff to hand it off — each step re-checks the
    player's actual position server-side at that moment. Optional `carryProp`
    attaches a prop to the player between the two stages for flavor.
  - `type = 'kill'`: server picks a random `spawnPoints` entry; client spawns
    an armed hostile NPC there and reports back when it's dead. The server
    only trusts that report after `minKillSeconds` — a real trust concession,
    bounded by that minimum plus the normal cooldown/time-limit system.
- Treasury: deposit/withdraw + weekly dues, with offline catch-up billing. Also
  shows the gang's full notoriety/tier, not just the balance.
- NUI tablet: main overview (with a progress bar toward the next tier), roster
  (click a member for kick/promote/demote + personal rep + online status),
  territory, tasks, unlocks (shows rep needed for anything still locked),
  treasury, activity log. The activity log now also covers tasks
  started/completed, drug sales, dealer calls/purchases, and crafting — not
  just membership/bank/placement events.
- Blackmarket app: anonymous world chat + handle-addressed DMs. **Requires
  being in a gang** — the app doesn't even show in the rail otherwise (this
  is enforced server-side too, not just hidden in the UI). Every character
  gets a persistent, custom-editable anonymous handle (e.g. `ShadowFox-A1B2`,
  ✎ to rename) — never tied to gang label, so even affiliation stays hidden.
  A shared world feed (`Config.Chat.worldHistoryLimit` messages kept) plus
  DMs addressed by handle, since that's the only identity anyone has — the
  server is the only thing that ever resolves a handle to a citizenid.
  Live-delivered if you're online, persisted either way.
- Boosting app: car theft, **open to everyone** regardless of gang
  membership — the one app that isn't gated, and fully standalone (no
  gang rep, no gang tie-in of any kind — see `server/boosting.lua`).
  Personal level + XP only this system tracks (`cipher_boost_stats`).
  `Config.Boosting.levels` is a cumulative tier list: at level N you can
  be assigned any vehicle from levels 1..N, each picking a random spot
  from its own `spawns` list. No custom lockpick/hotwire minigame here —
  the vehicle spawns locked with no owner/keys, and qbx_core's own
  vehicle break-in/hotwire system handles the actual theft; we just watch
  for the engine to actually start. Once it does, that fires an optional
  police dispatch hook (`Config.Boosting.dispatch` — disabled by default,
  the event/payload shape is just an example for `cd_dispatch` and needs
  adjusting to whatever dispatch resource you actually run). Bring the
  car to the drop-off, get out, and sell it to the buyer ped — validated
  by the vehicle's actual position, not the player's, so you can't just
  walk up without it. `Config.Boosting.guards` spawns armed hostiles near
  the target vehicle while you steal it — a friend can fight them off
  while you work. `Config.Boosting.wanted` keeps several bonus-paying
  "wanted" vehicles active at once (refreshed on `rotateMinutes`, not a
  rare one-off), available at any level alongside the normal pool. The
  Job tab shows those wanted vehicles, a preview of what you might get at
  your level, and a server-wide recent-sells feed; a Badges tab tracks
  config-defined milestones (`Config.Boosting.achievements`); a
  Leaderboard tab ranks the top 10 by lifetime cars boosted.
  - **Perks**: every level grants perk points (`Config.Boosting.levels[*].perkPoints`),
    spent on permanent, passive upgrades from `Config.Boosting.perks` — cash
    bonus %, fewer guards, a delayed dispatch alert, or a cheaper cooldown.
    No inventory items involved, nothing consumed.
  - **Co-op**: invite a specific nearby player (like a gang invite) to crew up
    on a separate, harder job — a bigger guard count, a shorter clock, and
    dispatch always fires instantly regardless of any Signal Jammer perk.
    Cash gets a bonus (`Config.Boosting.coop.cashBonusPct`) before splitting
    evenly across the crew; XP is **not** split, every member gets the full
    amount. Only the crew leader's client actually spawns the vehicle/guards/
    buyer ped (everyone else just sees it and can help fight) — this matters
    if you ever touch `client/boosting.lua`, since spawning per-member would
    create duplicate entities.

## Admin tablet
Staff manage everything in-game instead of editing config.lua/the DB by hand.
- Grant access in `server.cfg`:
  ```
  add_ace group.admin cipher.admin allow
  add_principal identifier.fivem:1234 group.admin
  ```
  (or add `cipher.admin` to whatever principal/group fits your setup)
- Run `/admintablet` to open the panel — six tabs:
  - **Dashboard**: at-a-glance totals (gang count, zones assigned, total gang
    bank, boosting player/total/active-job counts, chat message/handle
    counts, dealer cooldown status).
  - **Gangs**: create/rename gangs, set boss, disband, kick/promote members,
    adjust a member's personal rep or a gang's notoriety, force-set bank/dues.
  - **Zones**: create a zone at your current position, move/rename it, set
    its per-cycle income, assign or clear its holder.
  - **Boosting**: search any player by name or citizenid, directly edit their
    level/XP/total boosted/total cash/perk points, or reset them to scratch
    (also wipes owned perks).
  - **Blackmarket**: view recent world chat with delete buttons, and a
    handle→citizenid resolver for when you need to break the anonymity for
    moderation.
  - **Dealer**: view current rotating stock, force a reroll, or clear the
    global contact cooldown live.
- Everything here writes straight to the database — `Config.Gangs` is only
  used to seed gangs on first boot, not as an ongoing source of truth.
- Every action across every tab re-checks the ACE permission server-side
  (never just hidden client-side) and logs to the Discord admin webhook.

## Discord logging
Optional — set any of `Config.Discord.adminWebhook` / `gangWebhook` / `economyWebhook`
to a Discord webhook URL to get live embeds for:
- **admin**: every action taken through `/admintablet` (the audit trail)
- **gang**: founded / disbanded / boss changed
- **economy**: deposits, withdrawals, dues charged, dealer purchases

Leave any of them blank to disable that category — nothing is required. Get a
webhook URL from Discord: channel settings → Integrations → Webhooks → New
Webhook → Copy URL.

## Debugging
- `/testmodel <name> [ped]` (admin-only) — checks `IsModelValid` and spawns the
  model in front of you for 6s. Use this before adding any model name to
  `config.lua`; recalled/guessed model names are unreliable and fail silently
  or with confusing errors otherwise.

## Known stubs / next passes
- Money API assumes both frameworks expose `Player.Functions.AddMoney/RemoveMoney`;
  verify against your build and adjust the bridge if needed.
- Placement validates the final spot is within 6m of the placing player (server-side),
  but otherwise trusts the client-reported ghost position — fine for a permissioned
  Boss-only action, not meant to resist a malicious client.

## Architecture note
Nothing in the UI talks to gang logic directly. The NUI calls a single relay
(`call`), which routes to validated `ox_lib` server callbacks. The server is the
sole source of truth for permissions and state.
