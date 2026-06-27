// ─────────────────────────────────────────────────────────────
// Admin tablet controller. Separate root from the player device, but
// reuses the same NUI fetch helper. All real validation happens
// server-side (ACE check) — this is just the panel.
// ─────────────────────────────────────────────────────────────
(() => {
    const RES = 'cipher';
    const $ = (s) => document.querySelector(s);

    async function nui(cb, body = {}) {
        try {
            const r = await fetch(`https://${RES}/${cb}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(body),
            });
            return await r.json().catch(() => ({}));
        } catch (e) { return {}; }
    }
    const call = (name, ...args) => nui('admin:call', { name, args });

    function flash(msg, type = 'info') {
        const stack = $('#adminToastStack');
        if (!stack) return;
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.textContent = msg;
        stack.appendChild(toast);
        setTimeout(() => toast.classList.add('toast-out'), 2600);
        setTimeout(() => toast.remove(), 3000);
    }

    // Wraps a callback result: toasts on failure, returns the result either way.
    async function callChecked(label, name, ...args) {
        const res = await call(name, ...args);
        if (res && res.ok === false) flash(res.error || `${label} failed`, 'error');
        else if (res && res.ok) flash(`${label} done`, 'success');
        return res;
    }

    let overview = { gangs: [], territories: [] };

    window.openAdminUI = async () => {
        $('#root').classList.add('hidden');
        $('#adminRoot').classList.remove('hidden');
        await refresh();
    };

    $('#adminCloseBtn').onclick = () => nui('admin:close');

    async function refresh() {
        overview = await call('cipher:admin:getOverview');
        if (!overview || !overview.gangs) overview = { gangs: [], territories: [] };
        renderGangs();
        renderTerritories();
    }

    function escapeHtml(s) {
        return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    function renderGangs() {
        const list = $('#adminGangList');
        list.innerHTML = '';
        if (!overview.gangs.length) { list.innerHTML = '<div class="log-empty">No gangs yet.</div>'; return; }

        overview.gangs.forEach((g) => {
            const card = document.createElement('div');
            card.className = 'admin-gang-card';
            card.innerHTML = `
                <div class="row-between">
                    <div>
                        <div class="member-name">${escapeHtml(g.label)} <span class="muted">(#${g.id})</span></div>
                        <div class="muted">Boss: ${escapeHtml(g.owner || '—')} · ${g.memberCount} members · ${escapeHtml(g.tier)}</div>
                    </div>
                    <button class="icon-btn danger" data-act="disband" data-id="${g.id}" title="Disband">✕</button>
                </div>
                <div class="admin-form">
                    <input class="a-label" placeholder="rename label" value="${escapeHtml(g.label)}" />
                    <input class="a-boss" placeholder="new boss citizenid" />
                    <button data-act="updateLabel" data-id="${g.id}">Rename</button>
                    <button data-act="updateBoss" data-id="${g.id}">Set boss</button>
                </div>
                <div class="admin-form">
                    <input class="a-notoriety" type="number" placeholder="+/- notoriety" />
                    <button data-act="notoriety" data-id="${g.id}">Apply</button>
                    <input class="a-bank" type="number" placeholder="set bank $" value="${g.bank}" />
                    <button data-act="bank" data-id="${g.id}">Set</button>
                    <input class="a-dues" type="number" placeholder="set dues $" value="${g.dues_amount}" />
                    <button data-act="dues" data-id="${g.id}">Set</button>
                </div>
                <div class="admin-members" data-members="${g.id}"></div>
                <button class="btn btn-ghost" data-act="toggleMembers" data-id="${g.id}">Members / rep</button>`;
            list.appendChild(card);
        });

        list.querySelectorAll('[data-act]').forEach((btn) => {
            btn.onclick = async () => {
                const { act, id } = btn.dataset;
                const card = btn.closest('.admin-gang-card');
                if (act === 'disband') {
                    if (btn.dataset.confirm !== '1') {
                        btn.dataset.confirm = '1';
                        btn.textContent = '✔';
                        btn.title = 'Click again to confirm disband';
                        setTimeout(() => { btn.dataset.confirm = '0'; btn.textContent = '✕'; }, 3000);
                        return;
                    }
                    await callChecked('Disband', 'cipher:admin:disbandGang', id);
                } else if (act === 'updateLabel') {
                    await callChecked('Rename', 'cipher:admin:updateGang', id, { label: card.querySelector('.a-label').value });
                } else if (act === 'updateBoss') {
                    const boss = card.querySelector('.a-boss').value.trim();
                    if (!boss) return;
                    await callChecked('Set boss', 'cipher:admin:updateGang', id, { boss });
                } else if (act === 'notoriety') {
                    const amt = Number(card.querySelector('.a-notoriety').value) || 0;
                    await callChecked('Notoriety adjust', 'cipher:admin:adjustNotoriety', id, amt);
                } else if (act === 'bank') {
                    await callChecked('Bank set', 'cipher:admin:setBank', id, Number(card.querySelector('.a-bank').value) || 0);
                } else if (act === 'dues') {
                    await callChecked('Dues set', 'cipher:admin:setDues', id, Number(card.querySelector('.a-dues').value) || 0);
                } else if (act === 'toggleMembers') {
                    await renderMembers(id, card.querySelector(`[data-members="${id}"]`));
                    return;
                }
                await refresh();
            };
        });
    }

    async function renderMembers(gangId, container, force = false) {
        if (!force && container.dataset.loaded === '1') { container.innerHTML = ''; container.dataset.loaded = '0'; return; }
        const members = await call('cipher:admin:getMembers', gangId);
        container.innerHTML = '';
        container.dataset.loaded = '1';
        (members || []).forEach((m) => {
            const row = document.createElement('div');
            row.className = 'member';
            row.innerHTML = `
                <span class="member-name">${escapeHtml(m.name)}</span>
                <span class="member-rep">${m.rep} rep</span>
                <div class="member-actions">
                    <input class="rep-delta" type="number" placeholder="+/-" style="width:70px" />
                    <button data-rep-cid="${m.citizenid}">Apply</button>
                    <button data-promote-cid="${m.citizenid}" data-grade="${m.grade + 1}" title="Promote">▲</button>
                    <button data-promote-cid="${m.citizenid}" data-grade="${m.grade - 1}" title="Demote">▼</button>
                    <button class="icon-btn danger" data-kick-cid="${m.citizenid}" title="Kick">✕</button>
                </div>`;
            container.appendChild(row);
        });
        container.querySelectorAll('[data-rep-cid]').forEach((btn) => {
            btn.onclick = async () => {
                const amt = Number(btn.parentElement.querySelector('.rep-delta').value) || 0;
                await callChecked('Rep adjust', 'cipher:admin:adjustRep', btn.dataset.repCid, amt);
                await renderMembers(gangId, container, true);
            };
        });
        container.querySelectorAll('[data-promote-cid]').forEach((btn) => {
            btn.onclick = async () => {
                await callChecked('Grade set', 'cipher:admin:setMemberGrade', gangId, btn.dataset.promoteCid, btn.dataset.grade);
                await renderMembers(gangId, container, true);
            };
        });
        container.querySelectorAll('[data-kick-cid]').forEach((btn) => {
            btn.onclick = async () => {
                if (btn.dataset.confirm !== '1') {
                    btn.dataset.confirm = '1';
                    btn.textContent = '✔';
                    setTimeout(() => { btn.dataset.confirm = '0'; btn.textContent = '✕'; }, 3000);
                    return;
                }
                await callChecked('Kick', 'cipher:admin:kickMember', gangId, btn.dataset.kickCid);
                await renderMembers(gangId, container, true);
            };
        });
    }

    function renderTerritories() {
        const list = $('#adminTerritoryList');
        list.innerHTML = '';
        if (!(overview.territories || []).length) { list.innerHTML = '<div class="log-empty">No zones with coords set yet.</div>'; }

        (overview.territories || []).forEach((t) => {
            const row = document.createElement('div');
            row.className = 'admin-gang-card';
            const options = ['<option value="">Unassigned</option>']
                .concat(overview.gangs.map((g) => `<option value="${g.id}" ${t.holderId === g.id ? 'selected' : ''}>${escapeHtml(g.label)}</option>`));
            row.innerHTML = `
                <div class="row-between">
                    <span class="member-name">${escapeHtml(t.label)} <span class="muted">(${escapeHtml(t.zone)})</span></span>
                    <button class="icon-btn danger" data-del-zone="${t.zone}" title="Delete">✕</button>
                </div>
                <div class="admin-form">
                    <select class="terr-holder">${options.join('')}</select>
                    <button data-set-zone="${t.zone}">Set holder</button>
                    <button data-move-zone="${t.zone}">Move to my position</button>
                </div>
                <div class="admin-form">
                    <input class="terr-label" placeholder="rename label" value="${escapeHtml(t.label)}" />
                    <button data-label-zone="${t.zone}">Rename</button>
                    <input class="terr-income" type="number" placeholder="income/cycle" value="${t.income || 0}" />
                    <button data-income-zone="${t.zone}">Set income</button>
                </div>`;
            list.appendChild(row);
        });

        list.querySelectorAll('[data-set-zone]').forEach((btn) => {
            btn.onclick = async () => {
                const sel = btn.parentElement.querySelector('.terr-holder');
                await callChecked('Territory set', 'cipher:admin:setTerritory', btn.dataset.setZone, sel.value || null);
                await refresh();
            };
        });
        list.querySelectorAll('[data-move-zone]').forEach((btn) => {
            btn.onclick = async () => {
                await callChecked('Zone moved', 'cipher:admin:setZoneCoords', btn.dataset.moveZone);
                await refresh();
            };
        });
        list.querySelectorAll('[data-label-zone]').forEach((btn) => {
            btn.onclick = async () => {
                const card = btn.closest('.admin-gang-card');
                await callChecked('Zone renamed', 'cipher:admin:updateZone', btn.dataset.labelZone, { label: card.querySelector('.terr-label').value });
                await refresh();
            };
        });
        list.querySelectorAll('[data-income-zone]').forEach((btn) => {
            btn.onclick = async () => {
                const card = btn.closest('.admin-gang-card');
                const income = Number(card.querySelector('.terr-income').value) || 0;
                await callChecked('Income set', 'cipher:admin:updateZone', btn.dataset.incomeZone, { income });
                await refresh();
            };
        });
        list.querySelectorAll('[data-del-zone]').forEach((btn) => {
            btn.onclick = async () => {
                if (btn.dataset.confirm !== '1') {
                    btn.dataset.confirm = '1';
                    btn.textContent = '✔';
                    setTimeout(() => { btn.dataset.confirm = '0'; btn.textContent = '✕'; }, 3000);
                    return;
                }
                await callChecked('Zone deleted', 'cipher:admin:deleteZone', btn.dataset.delZone);
                await refresh();
            };
        });
    }

    $('#adminCreateZoneBtn').onclick = async () => {
        const key = $('#newZoneKey').value.trim();
        const label = $('#newZoneLabel').value.trim();
        if (!key) return;
        const res = await call('cipher:admin:createZone', key, label || key, 0);
        if (!res.ok) { flash(res.error || 'Failed to create zone', 'error'); return; }
        await callChecked('Zone placed', 'cipher:admin:setZoneCoords', res.zone);
        $('#newZoneKey').value = '';
        $('#newZoneLabel').value = '';
        await refresh();
    };

    $('#adminCreateBtn').onclick = async () => {
        const name = $('#newGangName').value.trim();
        const label = $('#newGangLabelAdmin').value.trim();
        const boss = $('#newGangBoss').value.trim();
        const res = await call('cipher:admin:createGang', name, label, boss);
        $('#adminCreateError').textContent = '';
        if (res.ok) {
            $('#newGangName').value = '';
            $('#newGangLabelAdmin').value = '';
            $('#newGangBoss').value = '';
            flash('Gang created', 'success');
            await refresh();
        } else {
            $('#adminCreateError').textContent = res.error || 'Failed to create gang';
        }
    };
})();
