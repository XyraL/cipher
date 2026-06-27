// ─────────────────────────────────────────────────────────────
// Crafting bench panel. Reuses the global `nui()` helper from app.js
// (same resource, same fetch target) — no need to redefine it here.
// ─────────────────────────────────────────────────────────────
(() => {
    const $ = (s) => document.querySelector(s);
    const RING_CIRCUMFERENCE = 2 * Math.PI * 44;

    let recipes = [];
    let selected = null;
    let crafting = false;

    window.addEventListener('message', (ev) => {
        const { action, label, recipes: r } = ev.data || {};
        if (action === 'craftOpen') openCraft(label, r || []);
        else if (action === 'craftClose') closeCraft();
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && !$('#craftRoot').classList.contains('hidden')) {
            nui('craft:escape');
            closeCraft();
        }
    });

    $('#craftCloseBtn').onclick = () => {
        nui('craft:close');
        closeCraft();
    };

    function openCraft(label, list) {
        recipes = list;
        selected = null;
        crafting = false;
        $('#craftBenchLabel').textContent = (label || 'Workbench').toUpperCase();
        $('#craftRoot').classList.remove('hidden');
        renderList();
        renderDetail();
    }

    function closeCraft() {
        $('#craftRoot').classList.add('hidden');
    }

    function renderList() {
        const list = $('#craftRecipeList');
        list.innerHTML = '';
        if (!recipes.length) {
            list.innerHTML = '<div class="craft-empty">No recipes configured for this bench yet.</div>';
            return;
        }
        recipes.forEach((r) => {
            const row = document.createElement('button');
            row.className = 'craft-recipe'
                + (selected && selected.id === r.id ? ' is-active' : '')
                + (r.locked ? ' is-locked' : '');
            row.innerHTML = r.locked
                ? `<span>${escapeHtml(r.label)}</span><span class="craft-locked-tag">${escapeHtml(r.tierName)}</span>`
                : `<span>${escapeHtml(r.label)}</span><span class="craft-arrow">›</span>`;
            if (!r.locked) row.onclick = () => { selected = r; renderList(); renderDetail(); };
            else row.disabled = true;
            list.appendChild(row);
        });
    }

    function renderDetail() {
        const empty = $('#craftEmpty');
        const sel = $('#craftSelected');
        if (!selected) {
            empty.classList.remove('hidden');
            sel.classList.add('hidden');
            return;
        }
        empty.classList.add('hidden');
        sel.classList.remove('hidden');
        $('#craftSelTitle').textContent = selected.label;

        $('#craftInputs').innerHTML = selected.inputs
            .map((i) => `<span class="craft-chip">${i.count}× ${escapeHtml(i.item)}</span>`).join('');
        $('#craftOutput').innerHTML = `<span class="craft-chip craft-chip-output">${selected.output.count}× ${escapeHtml(selected.output.item)}</span>`;

        const fill = $('#craftRingFill');
        fill.style.strokeDasharray = `${RING_CIRCUMFERENCE}`;
        fill.style.strokeDashoffset = `${RING_CIRCUMFERENCE}`;
        fill.style.transition = 'none';
        $('#craftMakeLabel').textContent = 'CRAFT';
        $('#craftMakeBtn').classList.remove('is-crafting');
    }

    $('#craftMakeBtn').onclick = async () => {
        if (!selected || crafting) return;
        crafting = true;
        const duration = selected.time && selected.time > 0 ? selected.time : 3000;

        $('#craftMakeBtn').classList.add('is-crafting');
        $('#craftMakeLabel').textContent = 'WORKING...';
        const fill = $('#craftRingFill');
        fill.style.transition = `stroke-dashoffset ${duration}ms linear`;
        // next frame so the transition actually animates from full to empty
        requestAnimationFrame(() => { fill.style.strokeDashoffset = '0'; });

        await new Promise((resolve) => setTimeout(resolve, duration));

        const res = await nui('craft:make', { id: selected.id });
        crafting = false;
        $('#craftMakeBtn').classList.remove('is-crafting');

        if (res && res.ok) {
            $('#craftMakeLabel').textContent = 'DONE';
        } else {
            $('#craftMakeLabel').textContent = 'FAILED';
        }
        setTimeout(() => { if (selected) renderDetail(); }, 1200);
    };

    function escapeHtml(s) {
        return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }
})();
