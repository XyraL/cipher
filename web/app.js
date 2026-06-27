// ─────────────────────────────────────────────────────────────
// Cipher NUI controller. Talks to client/device.lua via fetch callbacks.
// All gang logic lives server-side; this only renders + relays actions.
// ─────────────────────────────────────────────────────────────
const RES = 'cipher';
const $ = (s) => document.querySelector(s);
const el = (s) => document.querySelectorAll(s);

let state = { snapshot: null, apps: [], activeApp: null };

// POST to a registered NUI callback.
async function nui(cb, body = {}) {
    try {
        const r = await fetch(`https://${RES}/${cb}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body),
        });
        return await r.json().catch(() => ({}));
    } catch (e) {
        return {};
    }
}

// Relay a server callback through the generic 'call' bridge.
const call = (name, ...args) => nui('call', { name, args });

// ── window protocol ──
window.addEventListener('message', (ev) => {
    const { action, data } = ev.data || {};
    if (action === 'open') openUI(data);
    else if (action === 'close') closeUI();
    else if (action === 'openAdmin' && window.openAdminUI) window.openAdminUI();
    else if (action === 'chatWorldMessage') onWorldMessage(data);
    else if (action === 'chatDM') onDMReceived(data);
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!document.getElementById('adminRoot').classList.contains('hidden')) nui('admin:close');
    else nui('escape');
});

function openUI(snapshot) {
    state.snapshot = snapshot;
    $('#root').classList.remove('hidden');
    renderApps(snapshot.apps || []);
    tickClock();
    switchApp(state.activeApp || (state.apps[0] && state.apps[0].id));
}

function closeUI() {
    $('#root').classList.add('hidden');
    $('#adminRoot').classList.add('hidden');
}

$('#powerBtn').onclick = () => nui('close');

// ── clock ──
function tickClock() {
    const c = $('#clock');
    const update = () => {
        const d = new Date();
        c.textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    };
    update();
    clearInterval(window.__clock);
    window.__clock = setInterval(update, 15000);
}

// ── app rail ──
function renderApps(apps) {
    state.apps = apps;
    const rail = $('#appRail');
    rail.innerHTML = '';
    apps.forEach((app) => {
        const b = document.createElement('button');
        b.className = 'app-btn' + (app.id === state.activeApp ? ' is-active' : '');
        b.textContent = app.label.slice(0, 2).toUpperCase();
        b.title = app.label;
        b.onclick = () => switchApp(app.id);
        rail.appendChild(b);
    });
}

// ── app routing ──
function switchApp(appId) {
    state.activeApp = appId;
    el('.app-btn').forEach((b, i) => b.classList.toggle('is-active', state.apps[i] && state.apps[i].id === appId));
    el('.view').forEach((v) => v.classList.add('hidden'));

    if (appId === 'blackmarket') {
        showView('viewBlackmarket');
        renderBlackmarket();
    } else {
        render(); // gangops decides viewFound vs viewGang itself
    }
}

// ── main render (Gang Ops) ──
function render() {
    const g = state.snapshot.gang;
    if (!g) {
        showView('viewFound');
        $('#gangName').textContent = 'No affiliation';
        $('#gangTier').textContent = '—';
        return;
    }
    showView('viewGang');
    $('#gangName').textContent = g.label;
    $('#gangTier').textContent = g.tier;

    renderOverview(g);
    renderRoster(g);
    renderTerritory();
    renderBank(g);
    renderLogs(g.logs || []);
    renderTasks();
    renderUnlocks();
    renderDealer();
}

// ── main overview ──
function renderOverview(g) {
    $('#overviewName').textContent = g.label;
    $('#overviewTier').textContent = g.tier;
    $('#overviewBank').textContent = '$' + Number(g.bank).toLocaleString();
    $('#overviewRep').textContent = Number(g.notoriety).toLocaleString();
    $('#overviewMembers').textContent = g.members.length;
    $('#overviewOnline').textContent = g.members.filter((m) => m.online).length;
    $('#overviewTerritories').textContent = (state.snapshot.territories || []).filter((t) => t.holderId === g.id).length;
    const myRank = g.ranks[g.myGrade] ? g.ranks[g.myGrade].name : '?';
    $('#overviewMyRank').textContent = myRank;
    renderLogList($('#overviewLogs'), (g.logs || []).slice(0, 8));

    if (g.nextTierMin == null) {
        $('#overviewProgressFill').style.width = '100%';
        $('#overviewProgressLabel').textContent = `${Number(g.notoriety).toLocaleString()} rep — max tier`;
    } else {
        const span = g.nextTierMin - g.tierMin;
        const into = Math.max(0, g.notoriety - g.tierMin);
        const pct = span > 0 ? Math.min(100, (into / span) * 100) : 0;
        $('#overviewProgressFill').style.width = pct + '%';
        $('#overviewProgressLabel').textContent =
            `${Number(g.notoriety).toLocaleString()} / ${Number(g.nextTierMin).toLocaleString()} rep to next tier`;
    }
}

function showView(id) {
    el('.view').forEach((v) => v.classList.add('hidden'));
    $('#' + id).classList.remove('hidden');
}

// ── roster ──
function canManage(g) { return g.myGrade >= 2; } // simple UI gate; server is authoritative

function renderRoster(g) {
    $('#memberCount').textContent = g.members.length;
    $('#myRep').textContent = g.myRep || 0;
    const list = $('#memberList');
    list.innerHTML = '';
    g.members.forEach((m) => {
        const wrap = document.createElement('div');
        wrap.className = 'member-wrap';

        const row = document.createElement('div');
        row.className = 'member member-row';
        row.innerHTML = `
            <span class="online-dot ${m.online ? 'online' : ''}" title="${m.online ? 'Online' : 'Offline'}"></span>
            <span class="member-grade">${m.grade}</span>
            <span class="member-name">${escapeHtml(m.name)}</span>
            <span class="member-rank ${m.isOwner ? 'member-boss' : ''}">${escapeHtml(m.rank)}</span>
            <span class="chevron">▾</span>`;

        const detail = document.createElement('div');
        detail.className = 'member-detail hidden';
        const actions = (!m.isOwner && canManage(g)) ? `
            <button class="icon-btn" data-act="promote" data-cid="${m.citizenid}" data-grade="${m.grade + 1}" title="Promote">▲</button>
            <button class="icon-btn" data-act="demote" data-cid="${m.citizenid}" data-grade="${m.grade - 1}" title="Demote">▼</button>
            <button class="icon-btn danger" data-act="kick" data-cid="${m.citizenid}" title="Remove">✕</button>` : '';
        detail.innerHTML = `
            <span class="muted">Personal rep: <strong>${m.rep || 0}</strong></span>
            <div class="member-actions">${actions}</div>`;

        row.onclick = () => detail.classList.toggle('hidden');

        wrap.appendChild(row);
        wrap.appendChild(detail);
        list.appendChild(wrap);
    });

    list.querySelectorAll('[data-act]').forEach((btn) => {
        btn.onclick = async (e) => {
            e.stopPropagation();
            const { act, cid, grade } = btn.dataset;
            if (act === 'kick') await call('cipher:kick', cid);
            else await call('cipher:setGrade', cid, Number(grade));
            await refresh();
        };
    });
}

$('#inviteBtn').onclick = async () => {
    const id = $('#inviteId').value;
    if (!id) return;
    const res = await call('cipher:invite', Number(id));
    $('#inviteId').value = '';
    if (res.ok) flash('Invite sent', 'success');
    else flash(res.error || 'Failed', 'error');
};

// ── territory (signature) ──
function renderTerritory() {
    const grid = $('#turfGrid');
    const terr = state.snapshot.territories || [];
    const myId = state.snapshot.gang ? state.snapshot.gang.id : null;
    grid.innerHTML = '';
    terr.forEach((t) => {
        const mine = t.holderId && t.holderId === myId;
        const held = !!t.holderId;
        const cls = mine ? 'mine' : (held ? 'held' : '');
        const status = mine ? 'Controlled' : (held ? 'Rival turf' : 'Unassigned');
        const holderCls = mine ? 'mine' : (held ? 'held' : 'unclaimed');
        const holderTxt = t.holder || 'Unassigned';
        const card = document.createElement('div');
        card.className = 'turf ' + cls;
        card.innerHTML = `
            <span class="turf-status">${status}</span>
            <div>
                <div class="turf-label">${escapeHtml(t.label)}</div>
                <div class="turf-zone">${escapeHtml(t.zone)}</div>
            </div>
            <div class="turf-holder ${holderCls}">${escapeHtml(holderTxt)}</div>`;
        grid.appendChild(card);
    });
    if (!terr.length) grid.innerHTML = '<div class="log-empty">No territories configured.</div>';
}

// ── treasury ──
function renderBank(g) {
    $('#bankBalance').textContent = '$' + Number(g.bank).toLocaleString();
    $('#duesAmount').value = g.dues || '';
    $('#treasuryTier').textContent = g.tier;
    $('#treasuryRep').textContent = `${Number(g.notoriety).toLocaleString()} rep`;
}

$('#depositBtn').onclick = () => bankAction('cipher:bankDeposit');
$('#withdrawBtn').onclick = () => bankAction('cipher:bankWithdraw');
async function bankAction(name) {
    const amt = Number($('#bankAmount').value);
    if (!amt || amt <= 0) return;
    const res = await call(name, amt);
    $('#bankAmount').value = '';
    if (res.ok) { state.snapshot.gang.bank = res.balance; renderBank(state.snapshot.gang); flash('Done', 'success'); }
    else flash(res.error || 'Failed', 'error');
}
$('#setDuesBtn').onclick = async () => {
    const res = await call('cipher:setDues', Number($('#duesAmount').value) || 0);
    if (res.ok) flash('Dues updated', 'success');
    else flash(res.error || 'Failed', 'error');
};

// ── activity ──
function renderLogList(list, logs) {
    list.innerHTML = '';
    if (!logs.length) { list.innerHTML = '<div class="log-empty">No recent activity.</div>'; return; }
    logs.forEach((l) => {
        const item = document.createElement('div');
        item.className = 'log-item';
        item.innerHTML = `<span class="log-time">${formatTime(l.created_at)}</span><span>${escapeHtml(l.message)}</span>`;
        list.appendChild(item);
    });
}
function renderLogs(logs) { renderLogList($('#logList'), logs); }

// ── unlocks (benches/peds/vault placement) ──
async function renderUnlocks() {
    const items = await call('cipher:placeables:getAvailable');
    const list = $('#unlockList');
    list.innerHTML = '';
    if (!Array.isArray(items) || !items.length) {
        list.innerHTML = '<div class="log-empty">Nothing unlocked yet — raise notoriety.</div>';
        return;
    }
    items.forEach((it) => {
        const row = document.createElement('div');
        row.className = 'member' + (it.locked ? ' is-locked' : '');
        const status = it.locked
            ? `<span class="member-rank locked">Requires ${escapeHtml(it.tierName)} (${Number(it.tierRep).toLocaleString()} rep)</span>`
            : `<span class="member-rank">${it.placed ? 'Placed' : 'Not placed'}</span>`;
        const actions = it.locked ? '' : `
            <button class="btn btn-ghost" data-place-kind="${it.kind}" data-place-id="${it.id}">${it.placed ? 'Move' : 'Place'}</button>
            ${it.placed ? `<button class="icon-btn danger" data-remove-kind="${it.kind}" data-remove-id="${it.id}" title="Remove">✕</button>` : ''}`;
        row.innerHTML = `
            <span class="member-name">${escapeHtml(it.label)}</span>
            ${status}
            <div class="member-actions">${actions}</div>`;
        list.appendChild(row);
    });

    list.querySelectorAll('[data-place-kind]').forEach((btn) => {
        btn.onclick = () => nui('placeObject', { kind: btn.dataset.placeKind, id: btn.dataset.placeId });
    });
    list.querySelectorAll('[data-remove-kind]').forEach((btn) => {
        btn.onclick = async () => {
            const res = await call('cipher:placeables:remove', btn.dataset.removeKind, btn.dataset.removeId);
            if (res.ok) flash('Removed', 'success'); else flash(res.error || 'Failed', 'error');
            await renderUnlocks();
        };
    });
}

// ── tasks ──
async function renderTasks() {
    const res = await call('cipher:tasks:getAvailable');
    const tasks = (res && res.tasks) || [];
    const activeJob = res && res.active;
    const list = $('#taskList');
    list.innerHTML = '';

    $('#cancelTaskBtn').classList.toggle('hidden', !activeJob);

    if (activeJob) {
        const row = document.createElement('div');
        row.className = 'member';
        row.innerHTML = `<span class="member-name">On the job — ${escapeHtml(activeJob.stage)}</span>`;
        list.appendChild(row);
        return;
    }

    if (!tasks.length) { list.innerHTML = '<div class="log-empty">No jobs configured.</div>'; return; }

    tasks.forEach((t) => {
        const onCooldown = t.cooldownMs > 0;
        const row = document.createElement('div');
        row.className = 'member';
        const mins = Math.ceil(t.cooldownMs / 60000);
        row.innerHTML = `
            <span class="member-name">${escapeHtml(t.label)}</span>
            <span class="member-rank">+${t.reward} rep</span>
            <div class="member-actions">
                <button class="btn btn-ghost" data-task="${t.id}" ${onCooldown ? 'disabled' : ''}>
                    ${onCooldown ? `Cooldown ${mins}m` : 'Accept'}
                </button>
            </div>`;
        list.appendChild(row);
    });

    list.querySelectorAll('[data-task]').forEach((btn) => {
        btn.onclick = async () => {
            const res = await call('cipher:tasks:accept', btn.dataset.task);
            if (res.ok) { flash('Job accepted — check your map.', 'success'); nui('close'); }
            else flash(res.error || 'Failed', 'error');
            await renderTasks();
        };
    });
}

$('#cancelTaskBtn').onclick = async () => {
    await call('cipher:tasks:cancel');
    await renderTasks();
};

// ── dealer ──
async function renderDealer() {
    const status = await call('cipher:dealer:getStatus');
    const btn = $('#callDealerBtn');
    if (status && status.cooldownMs > 0) {
        const hrs = (status.cooldownMs / 3600000).toFixed(1);
        $('#dealerStatus').textContent = `On cooldown — ${hrs}h`;
        btn.disabled = true;
    } else {
        $('#dealerStatus').textContent = 'Available';
        btn.disabled = false;
    }
}
$('#callDealerBtn').onclick = async () => {
    const res = await call('cipher:dealer:contact');
    if (res.ok) { flash('Dealer is en route — check your map.', 'success'); nui('close'); }
    else flash(res.error || 'Failed', 'error');
    await renderDealer();
};

// ── tabs ── (scoped to the enclosing .view so two apps' tabs never collide)
el('.tab').forEach((tab) => {
    tab.onclick = () => {
        const scope = tab.closest('.view') || document;
        scope.querySelectorAll('.tab').forEach((t) => t.classList.remove('is-active'));
        scope.querySelectorAll('.tabview').forEach((v) => v.classList.remove('is-active'));
        tab.classList.add('is-active');
        scope.querySelector(`[data-tabview="${tab.dataset.tab}"]`).classList.add('is-active');
    };
});

// ── helpers ──
async function refresh() {
    const snap = await call('cipher:getSnapshot');
    // getSnapshot returns the snapshot object directly (not wrapped)
    state.snapshot = snap.gang !== undefined ? snap : state.snapshot;
    render();
}
function flash(msg, type = 'info') {
    const stack = $('#toastStack');
    if (!stack) return;
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = msg;
    stack.appendChild(toast);
    setTimeout(() => toast.classList.add('toast-out'), 2600);
    setTimeout(() => toast.remove(), 3000);
}
function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function formatTime(ts) {
    if (!ts) return '';
    const d = new Date(ts.replace ? ts.replace(' ', 'T') : ts);
    if (isNaN(d)) return '';
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// ── Blackmarket ──
let blackmarketLoaded = false;
let dmActiveHandle = null;

async function renderBlackmarket() {
    if (!blackmarketLoaded) {
        blackmarketLoaded = true;
        const handle = await call('cipher:chat:getMyHandle');
        $('#myHandle').textContent = handle || '—';
    }
    await renderWorldFeed();
    await renderDMThreads();
}

$('#editHandleBtn').onclick = () => {
    $('#handleInput').value = $('#myHandle').textContent;
    $('#handleEditRow').classList.remove('hidden');
};
$('#cancelHandleBtn').onclick = () => $('#handleEditRow').classList.add('hidden');
$('#saveHandleBtn').onclick = async () => {
    const desired = $('#handleInput').value.trim();
    if (!desired) return;
    const res = await call('cipher:chat:setHandle', desired);
    if (res.ok) {
        $('#myHandle').textContent = res.handle;
        $('#handleEditRow').classList.add('hidden');
        flash('Handle updated', 'success');
    } else {
        flash(res.error || 'Failed to update handle', 'error');
    }
};
$('#handleInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#saveHandleBtn').click(); });

function appendChatBubble(container, handle, message, mine) {
    const row = document.createElement('div');
    row.className = 'chat-bubble' + (mine ? ' mine' : '');
    row.innerHTML = `<span class="chat-handle">${escapeHtml(handle)}</span><span class="chat-text">${escapeHtml(message)}</span>`;
    container.appendChild(row);
    container.scrollTop = container.scrollHeight;
}

async function renderWorldFeed() {
    const history = await call('cipher:chat:getWorldHistory');
    const feed = $('#worldFeed');
    feed.innerHTML = '';
    const myHandle = $('#myHandle').textContent;
    (history || []).forEach((m) => appendChatBubble(feed, m.handle, m.message, m.handle === myHandle));
    if (!history || !history.length) feed.innerHTML = '<div class="log-empty">No chatter yet.</div>';
}

function onWorldMessage(m) {
    if (state.activeApp !== 'blackmarket') return;
    const myHandle = $('#myHandle').textContent;
    appendChatBubble($('#worldFeed'), m.handle, m.message, m.handle === myHandle);
}

$('#worldSendBtn').onclick = async () => {
    const input = $('#worldInput');
    const msg = input.value.trim();
    if (!msg) return;
    input.value = '';
    const res = await call('cipher:chat:postWorld', msg);
    if (!res.ok) flash(res.error || 'Failed to post', 'error');
};
$('#worldInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#worldSendBtn').click(); });

async function renderDMThreads() {
    const threads = await call('cipher:chat:getThreads');
    const list = $('#dmThreadList');
    list.innerHTML = '';
    if (!threads || !threads.length) {
        list.innerHTML = '<div class="log-empty">No conversations yet.</div>';
    } else {
        threads.forEach((t) => {
            const row = document.createElement('div');
            row.className = 'member';
            row.innerHTML = `
                <span class="member-name">${escapeHtml(t.handle)}${t.unread ? ' <span class="unread-dot"></span>' : ''}</span>
                <span class="member-rank">${escapeHtml((t.lastMessage || '').slice(0, 40))}</span>`;
            row.onclick = () => openDMThread(t.handle);
            list.appendChild(row);
        });
    }
    $('#dmConversation').classList.add('hidden');
    list.classList.remove('hidden');
}

async function openDMThread(handle) {
    dmActiveHandle = handle;
    $('#dmThreadList').classList.add('hidden');
    $('#dmConversation').classList.remove('hidden');
    const feed = $('#dmFeed');
    feed.innerHTML = '';
    const myHandle = $('#myHandle').textContent;
    const messages = await call('cipher:chat:getThread', handle);
    (messages || []).forEach((m) => appendChatBubble(feed, m.from_handle, m.message, m.from_handle === myHandle));
    if (!messages || !messages.length) feed.innerHTML = '<div class="log-empty">No messages yet — say hi.</div>';
}

$('#dmBackBtn').onclick = () => { dmActiveHandle = null; renderDMThreads(); };

$('#dmSendBtn').onclick = async () => {
    if (!dmActiveHandle) return;
    const input = $('#dmInput');
    const msg = input.value.trim();
    if (!msg) return;
    input.value = '';
    const res = await call('cipher:chat:sendDM', dmActiveHandle, msg);
    if (res.ok) {
        const myHandle = $('#myHandle').textContent;
        appendChatBubble($('#dmFeed'), myHandle, msg, true);
    } else {
        flash(res.error || 'Failed to send', 'error');
    }
};
$('#dmInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#dmSendBtn').click(); });

$('#dmNewBtn').onclick = () => {
    const handle = $('#dmNewHandle').value.trim();
    if (!handle) return;
    $('#dmNewHandle').value = '';
    openDMThread(handle);
};

function onDMReceived(m) {
    if (state.activeApp === 'blackmarket' && dmActiveHandle === m.handle) {
        appendChatBubble($('#dmFeed'), m.handle, m.message, false);
    } else {
        flash(`New message from ${m.handle}`, 'info');
    }
    if (state.activeApp === 'blackmarket' && !dmActiveHandle) renderDMThreads();
}

// dev preview outside FiveM
if (!window.invokeNative) {
    // no-op: in browser you can call openUI(mockSnapshot) to preview
}
