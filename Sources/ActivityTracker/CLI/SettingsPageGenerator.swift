import Foundation

enum SettingsPageGenerator {
    static func generate(apiPort: Int) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Settings</title>
        <style>
        \(css())
        </style>
        </head>
        <body>
        <div class="tabs">
            <div class="tabs-inner">
                <button class="tab active" onclick="switchTab('brands', this)">Brands &amp; Projects</button>
                <button class="tab" onclick="switchTab('rules', this)">Rules</button>
                <button class="tab" onclick="switchTab('general', this)">General</button>
            </div>
        </div>

        <div id="tab-brands" class="tab-content active">
            <div class="toolbar">
                <button class="btn btn-primary" onclick="showAddBrand()">+ Brand</button>
                <button class="btn btn-primary" onclick="showAddProject()">+ Project</button>
            </div>
            <div id="brand-tree"></div>
        </div>

        <div id="tab-rules" class="tab-content">
            <div class="toolbar">
                <button class="btn btn-primary" onclick="showAddRule()">+ Rule</button>
            </div>
            <div id="rules-list"></div>
        </div>

        <div id="tab-general" class="tab-content">
            <div class="info-card">
                <div class="info-row"><span class="info-label">Tracking Interval</span><span class="info-value">2 seconds</span></div>
                <div class="info-row"><span class="info-label">Idle Threshold</span><span class="info-value">600 seconds (10 min)</span></div>
                <div class="info-row"><span class="info-label">API Port</span><span class="info-value">\(apiPort)</span></div>
                <div class="info-row"><span class="info-label">Database</span><span class="info-value">~/Library/Application Support/ActivityTracker/activity.db</span></div>
                <div class="info-row"><span class="info-label">Reports</span><span class="info-value">~/Library/Application Support/ActivityTracker/reports/</span></div>
            </div>
        </div>

        <div id="modal-overlay" class="modal-overlay" onclick="closeModal()"></div>
        <div id="modal" class="modal">
            <div class="modal-header"><span id="modal-title"></span><button class="modal-close" onclick="closeModal()">&times;</button></div>
            <div id="modal-body" class="modal-body"></div>
            <div id="modal-footer" class="modal-footer"></div>
        </div>

        <script>
        \(js(apiPort: apiPort))
        </script>
        </body>
        </html>
        """
    }

    private static func css() -> String {
        return """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif;
            background: #f5f5f7;
            color: #1d1d1f;
            font-size: 13px;
            -webkit-user-select: none;
            overflow: hidden;
        }

        /* Segmented control tabs (macOS style) */
        .tabs {
            display: flex;
            justify-content: center;
            padding: 14px 16px 10px;
            background: #f5f5f7;
        }
        .tabs-inner {
            display: inline-flex;
            background: #e8e8ed;
            border-radius: 7px;
            padding: 2px;
        }
        .tab {
            background: none;
            border: none;
            color: #555;
            padding: 5px 16px;
            font-size: 12px;
            font-weight: 500;
            cursor: pointer;
            border-radius: 5px;
            transition: all 0.15s;
        }
        .tab:hover { color: #1d1d1f; }
        .tab.active {
            background: #fff;
            color: #1d1d1f;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1), 0 0.5px 1px rgba(0,0,0,0.06);
            font-weight: 600;
        }

        .tab-content { display: none; padding: 0 20px 20px; height: calc(100vh - 52px); overflow-y: auto; }
        .tab-content.active { display: block; }

        .toolbar { display: flex; gap: 8px; margin-bottom: 12px; }

        /* Buttons */
        .btn {
            padding: 5px 12px;
            border-radius: 6px;
            border: 1px solid #d2d2d7;
            background: #fff;
            color: #1d1d1f;
            font-size: 12px;
            cursor: pointer;
            transition: all 0.12s;
            font-weight: 400;
        }
        .btn:hover { background: #f0f0f5; }
        .btn:active { background: #e5e5ea; }
        .btn-primary {
            background: #007aff;
            border-color: #007aff;
            color: #fff;
        }
        .btn-primary:hover { background: #0066d6; border-color: #0066d6; }
        .btn-primary:active { background: #004ea2; }
        .btn-danger {
            background: #fff;
            border-color: #d2d2d7;
            color: #ff3b30;
        }
        .btn-danger:hover { background: #fff5f5; border-color: #ff3b30; }
        .btn-sm { padding: 2px 8px; font-size: 11px; }

        /* Card container (grouped settings style) */
        .card {
            background: #fff;
            border-radius: 10px;
            border: 0.5px solid #d2d2d7;
            overflow: hidden;
            margin-bottom: 12px;
        }

        /* Brand tree */
        .brand-group { margin-bottom: 10px; }
        .brand-row {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 9px 12px;
            background: #fff;
            border-radius: 10px;
            border: 0.5px solid #d2d2d7;
        }
        .brand-row:hover { background: #f9f9fb; }
        .brand-dot {
            width: 10px; height: 10px;
            border-radius: 50%;
            flex-shrink: 0;
        }
        .brand-name { font-weight: 600; flex: 1; color: #1d1d1f; }
        .brand-actions { display: flex; gap: 4px; opacity: 0; transition: opacity 0.12s; }
        .brand-row:hover .brand-actions,
        .project-row:hover .project-actions { opacity: 1; }

        .projects-container {
            background: #fff;
            border-radius: 0 0 10px 10px;
            margin-top: -1px;
            border: 0.5px solid #d2d2d7;
            border-top: none;
            overflow: hidden;
        }
        .project-row {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 7px 12px 7px 30px;
            border-top: 0.5px solid #e8e8ed;
        }
        .project-row:first-child { border-top: 0.5px solid #d2d2d7; }
        .project-row:hover { background: #f5f5f7; }
        .project-dot {
            width: 8px; height: 8px;
            border-radius: 50%;
            flex-shrink: 0;
        }
        .project-name { flex: 1; color: #1d1d1f; }
        .project-actions { display: flex; gap: 4px; opacity: 0; transition: opacity 0.12s; }
        .rule-count { color: #86868b; font-size: 11px; }

        /* Rules list */
        .rules-group { margin-bottom: 14px; }
        .rules-group-title {
            font-weight: 600;
            color: #86868b;
            margin-bottom: 4px;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.3px;
            padding-left: 2px;
        }
        .rules-card {
            background: #fff;
            border-radius: 10px;
            border: 0.5px solid #d2d2d7;
            overflow: hidden;
        }
        .rule-row {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 7px 12px;
            border-top: 0.5px solid #e8e8ed;
        }
        .rule-row:first-child { border-top: none; }
        .rule-row:hover { background: #f5f5f7; }
        .rule-badge {
            padding: 2px 7px;
            border-radius: 4px;
            background: #e8e8ed;
            font-size: 10px;
            color: #555;
            font-weight: 600;
            white-space: nowrap;
        }
        .rule-pattern {
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 12px;
            color: #1d1d1f;
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .rule-regex {
            font-size: 10px;
            color: #bf5a00;
            background: #fff3e0;
            padding: 1px 5px;
            border-radius: 3px;
            font-weight: 500;
        }
        .rule-actions { opacity: 0; transition: opacity 0.12s; }
        .rule-row:hover .rule-actions { opacity: 1; }

        /* Info grid */
        .info-card {
            background: #fff;
            border-radius: 10px;
            border: 0.5px solid #d2d2d7;
            overflow: hidden;
            max-width: 520px;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 14px;
            border-top: 0.5px solid #e8e8ed;
        }
        .info-row:first-child { border-top: none; }
        .info-label { color: #1d1d1f; }
        .info-value { color: #86868b; font-family: 'SF Mono', Menlo, monospace; font-size: 11px; text-align: right; }

        /* Modal */
        .modal-overlay {
            display: none;
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.25);
            z-index: 100;
            backdrop-filter: blur(2px);
        }
        .modal {
            display: none;
            position: fixed;
            top: 50%; left: 50%;
            transform: translate(-50%, -50%);
            background: #f5f5f7;
            border: 0.5px solid #c7c7cc;
            border-radius: 12px;
            min-width: 380px;
            max-width: 440px;
            z-index: 101;
            box-shadow: 0 24px 48px rgba(0,0,0,0.18), 0 0 1px rgba(0,0,0,0.1);
        }
        .modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 14px 18px 10px;
            font-weight: 600;
            font-size: 14px;
            color: #1d1d1f;
        }
        .modal-close {
            background: #e8e8ed;
            border: none;
            color: #86868b;
            font-size: 14px;
            cursor: pointer;
            width: 22px; height: 22px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            line-height: 1;
        }
        .modal-close:hover { background: #d2d2d7; color: #555; }
        .modal-body { padding: 4px 18px 12px; }
        .modal-footer {
            display: flex;
            justify-content: flex-end;
            gap: 8px;
            padding: 10px 18px 14px;
        }

        .form-group { margin-bottom: 14px; }
        .form-label {
            display: block;
            color: #86868b;
            font-size: 11px;
            margin-bottom: 4px;
            font-weight: 500;
        }
        .form-input {
            width: 100%;
            padding: 6px 10px;
            background: #fff;
            border: 0.5px solid #c7c7cc;
            border-radius: 6px;
            color: #1d1d1f;
            font-size: 13px;
            outline: none;
            font-family: inherit;
        }
        .form-input:focus { border-color: #007aff; box-shadow: 0 0 0 3px rgba(0,122,255,0.15); }
        .form-select {
            width: 100%;
            padding: 6px 10px;
            background: #fff;
            border: 0.5px solid #c7c7cc;
            border-radius: 6px;
            color: #1d1d1f;
            font-size: 13px;
            outline: none;
            font-family: inherit;
        }
        .form-select:focus { border-color: #007aff; box-shadow: 0 0 0 3px rgba(0,122,255,0.15); }

        .color-picker { display: flex; gap: 6px; flex-wrap: wrap; }
        .color-swatch {
            width: 24px; height: 24px;
            border-radius: 50%;
            cursor: pointer;
            border: 2.5px solid transparent;
            transition: all 0.12s;
        }
        .color-swatch:hover { transform: scale(1.12); }
        .color-swatch.selected {
            border-color: #1d1d1f;
            box-shadow: 0 0 0 2px #fff, 0 0 0 3.5px rgba(0,0,0,0.2);
        }

        .checkbox-row { display: flex; align-items: center; gap: 6px; }
        .checkbox-row input[type="checkbox"] { accent-color: #007aff; }

        .empty-state { text-align: center; color: #86868b; padding: 40px 0; }
        .confirm-msg { color: #1d1d1f; line-height: 1.6; }
        .confirm-msg strong { color: #ff3b30; }
        """
    }

    private static func js(apiPort: Int) -> String {
        return """
        const API = 'http://127.0.0.1:\(apiPort)';
        const COLORS = [
            {name:'Indigo',hex:'#6366f1'},{name:'Amber',hex:'#f59e0b'},{name:'Emerald',hex:'#10b981'},
            {name:'Red',hex:'#ef4444'},{name:'Purple',hex:'#8b5cf6'},{name:'Pink',hex:'#ec4899'},
            {name:'Teal',hex:'#14b8a6'},{name:'Orange',hex:'#f97316'},{name:'Cyan',hex:'#06b6d4'},
            {name:'Lime',hex:'#84cc16'}
        ];
        const RULE_TYPES = [
            {value:'terminalFolder',label:'Terminal Folder'},
            {value:'urlDomain',label:'URL Domain'},
            {value:'urlPath',label:'URL Path'},
            {value:'pageTitle',label:'Page Title'},
            {value:'figmaFile',label:'Figma File'},
            {value:'bundleId',label:'Bundle ID'},
            {value:'windowTitle',label:'Window Title'}
        ];

        let brandsData = [];
        let projectsData = [];
        let rulesData = [];

        // --- API helper ---
        async function api(path, body) {
            const opts = body !== undefined
                ? { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body) }
                : { method: 'GET' };
            const res = await fetch(API + path, opts);
            return res.json();
        }

        // --- Tab switching ---
        function switchTab(name, btn) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            btn.classList.add('active');
            document.getElementById('tab-' + name).classList.add('active');
            if (name === 'rules') loadRules();
        }

        // --- Load data ---
        async function loadBrandsAndProjects() {
            const data = await api('/api/projects');
            brandsData = data.brands || [];
            projectsData = data.projects || [];
            renderBrandTree();
        }

        async function loadRules() {
            const data = await api('/api/rules');
            rulesData = data.rules || [];
            renderRules();
        }

        // --- Render brand/project tree ---
        function renderBrandTree() {
            const el = document.getElementById('brand-tree');
            if (brandsData.length === 0) {
                el.innerHTML = '<div class="empty-state">No brands yet. Click "+ Brand" to create one.</div>';
                return;
            }
            let html = '';
            for (const brand of brandsData) {
                const projs = projectsData.filter(p => p.brandId === brand.id);
                html += '<div class="brand-group">';
                html += '<div class="brand-row">';
                html += '  <div class="brand-dot" style="background:' + brand.color + '"></div>';
                html += '  <span class="brand-name">' + esc(brand.name) + '</span>';
                html += '  <span class="rule-count">' + projs.length + ' project' + (projs.length !== 1 ? 's' : '') + '</span>';
                html += '  <div class="brand-actions">';
                html += '    <button class="btn btn-sm" onclick="showEditBrand(' + brand.id + ')">Edit</button>';
                html += '    <button class="btn btn-sm btn-danger" onclick="confirmDeleteBrand(' + brand.id + ',\\'' + escAttr(brand.name) + '\\')">Delete</button>';
                html += '  </div>';
                html += '</div>';
                if (projs.length > 0) {
                    html += '<div class="projects-container">';
                    for (const p of projs) {
                        html += '<div class="project-row">';
                        html += '  <div class="project-dot" style="background:' + p.color + '"></div>';
                        html += '  <span class="project-name">' + esc(p.name) + '</span>';
                        html += '  <div class="project-actions">';
                        html += '    <button class="btn btn-sm" onclick="showEditProject(' + p.id + ')">Edit</button>';
                        html += '    <button class="btn btn-sm btn-danger" onclick="confirmDeleteProject(' + p.id + ',\\'' + escAttr(p.name) + '\\')">Delete</button>';
                        html += '  </div>';
                        html += '</div>';
                    }
                    html += '</div>';
                }
                html += '</div>';
            }
            el.innerHTML = html;
        }

        // --- Render rules ---
        function renderRules() {
            const el = document.getElementById('rules-list');
            if (rulesData.length === 0) {
                el.innerHTML = '<div class="empty-state">No rules yet. Click "+ Rule" to create one.</div>';
                return;
            }
            // Group by projectLabel
            const groups = {};
            for (const r of rulesData) {
                if (!groups[r.projectLabel]) groups[r.projectLabel] = [];
                groups[r.projectLabel].push(r);
            }
            let html = '';
            for (const [label, rules] of Object.entries(groups)) {
                html += '<div class="rules-group">';
                html += '<div class="rules-group-title">' + esc(label) + '</div>';
                html += '<div class="rules-card">';
                for (const r of rules) {
                    html += '<div class="rule-row">';
                    html += '  <span class="rule-badge">' + esc(r.ruleType) + '</span>';
                    html += '  <span class="rule-pattern">' + esc(r.pattern) + '</span>';
                    if (r.isRegex) html += '  <span class="rule-regex">regex</span>';
                    html += '  <div class="rule-actions">';
                    html += '    <button class="btn btn-sm btn-danger" onclick="confirmDeleteRule(' + r.id + ')">Delete</button>';
                    html += '  </div>';
                    html += '</div>';
                }
                html += '</div>';
                html += '</div>';
            }
            el.innerHTML = html;
        }

        // --- Modal helpers ---
        function openModal(title) {
            document.getElementById('modal-title').textContent = title;
            document.getElementById('modal-overlay').style.display = 'block';
            document.getElementById('modal').style.display = 'block';
        }
        function closeModal() {
            document.getElementById('modal-overlay').style.display = 'none';
            document.getElementById('modal').style.display = 'none';
            document.getElementById('modal-body').innerHTML = '';
            document.getElementById('modal-footer').innerHTML = '';
        }

        function colorPickerHTML(selectedHex) {
            return '<div class="color-picker">' + COLORS.map(c =>
                '<div class="color-swatch' + (c.hex === selectedHex ? ' selected' : '') +
                '" style="background:' + c.hex + '" data-hex="' + c.hex +
                '" onclick="selectColor(this)"></div>'
            ).join('') + '</div>';
        }

        function selectColor(el) {
            el.parentElement.querySelectorAll('.color-swatch').forEach(s => s.classList.remove('selected'));
            el.classList.add('selected');
        }

        function getSelectedColor() {
            const sel = document.querySelector('.color-swatch.selected');
            return sel ? sel.dataset.hex : '#6366f1';
        }

        // --- Brand CRUD ---
        function showAddBrand() {
            openModal('Add Brand');
            document.getElementById('modal-body').innerHTML =
                '<div class="form-group"><label class="form-label">Name</label><input class="form-input" id="m-name" placeholder="Brand name" autofocus></div>' +
                '<div class="form-group"><label class="form-label">Color</label>' + colorPickerHTML('#6366f1') + '</div>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-primary" onclick="doAddBrand()">Add</button>';
            setTimeout(() => document.getElementById('m-name').focus(), 50);
        }

        async function doAddBrand() {
            const name = document.getElementById('m-name').value.trim();
            if (!name) return;
            await api('/api/brand', { name, color: getSelectedColor() });
            closeModal();
            await loadBrandsAndProjects();
        }

        function showEditBrand(id) {
            const brand = brandsData.find(b => b.id === id);
            if (!brand) return;
            openModal('Edit Brand');
            document.getElementById('modal-body').innerHTML =
                '<div class="form-group"><label class="form-label">Name</label><input class="form-input" id="m-name" value="' + escAttr(brand.name) + '"></div>' +
                '<div class="form-group"><label class="form-label">Color</label>' + colorPickerHTML(brand.color) + '</div>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-primary" onclick="doEditBrand(' + id + ')">Save</button>';
            setTimeout(() => document.getElementById('m-name').focus(), 50);
        }

        async function doEditBrand(id) {
            const name = document.getElementById('m-name').value.trim();
            if (!name) return;
            await api('/api/brand/update', { id, name, color: getSelectedColor() });
            closeModal();
            await loadBrandsAndProjects();
        }

        function confirmDeleteBrand(id, name) {
            openModal('Delete Brand');
            document.getElementById('modal-body').innerHTML =
                '<p class="confirm-msg">Delete brand <strong>' + esc(name) + '</strong>?<br>All projects and rules under this brand will also be deleted. Activities will become unassigned.</p>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-danger" onclick="doDeleteBrand(' + id + ')">Delete</button>';
        }

        async function doDeleteBrand(id) {
            await api('/api/brand/delete', { id });
            closeModal();
            await loadBrandsAndProjects();
        }

        // --- Project CRUD ---
        function showAddProject() {
            if (brandsData.length === 0) {
                openModal('No Brands');
                document.getElementById('modal-body').innerHTML = '<p class="confirm-msg">Create a brand first before adding projects.</p>';
                document.getElementById('modal-footer').innerHTML = '<button class="btn btn-primary" onclick="closeModal();showAddBrand()">Add Brand</button>';
                return;
            }
            openModal('Add Project');
            let brandOpts = brandsData.map(b => '<option value="' + b.id + '">' + esc(b.name) + '</option>').join('');
            document.getElementById('modal-body').innerHTML =
                '<div class="form-group"><label class="form-label">Brand</label><select class="form-select" id="m-brand">' + brandOpts + '</select></div>' +
                '<div class="form-group"><label class="form-label">Name</label><input class="form-input" id="m-name" placeholder="Project name"></div>' +
                '<div class="form-group"><label class="form-label">Color</label>' + colorPickerHTML('#6366f1') + '</div>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-primary" onclick="doAddProject()">Add</button>';
            setTimeout(() => document.getElementById('m-name').focus(), 50);
        }

        async function doAddProject() {
            const name = document.getElementById('m-name').value.trim();
            const brandId = parseInt(document.getElementById('m-brand').value);
            if (!name || !brandId) return;
            await api('/api/project', { brandId, name, color: getSelectedColor() });
            closeModal();
            await loadBrandsAndProjects();
        }

        function showEditProject(id) {
            const proj = projectsData.find(p => p.id === id);
            if (!proj) return;
            openModal('Edit Project');
            let brandOpts = brandsData.map(b =>
                '<option value="' + b.id + '"' + (b.id === proj.brandId ? ' selected' : '') + '>' + esc(b.name) + '</option>'
            ).join('');
            document.getElementById('modal-body').innerHTML =
                '<div class="form-group"><label class="form-label">Brand</label><select class="form-select" id="m-brand">' + brandOpts + '</select></div>' +
                '<div class="form-group"><label class="form-label">Name</label><input class="form-input" id="m-name" value="' + escAttr(proj.name) + '"></div>' +
                '<div class="form-group"><label class="form-label">Color</label>' + colorPickerHTML(proj.color) + '</div>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-primary" onclick="doEditProject(' + id + ')">Save</button>';
            setTimeout(() => document.getElementById('m-name').focus(), 50);
        }

        async function doEditProject(id) {
            const name = document.getElementById('m-name').value.trim();
            const brandId = parseInt(document.getElementById('m-brand').value);
            if (!name) return;
            await api('/api/project/update', { id, name, color: getSelectedColor(), brandId });
            closeModal();
            await loadBrandsAndProjects();
        }

        function confirmDeleteProject(id, name) {
            openModal('Delete Project');
            document.getElementById('modal-body').innerHTML =
                '<p class="confirm-msg">Delete project <strong>' + esc(name) + '</strong>?<br>All rules for this project will be deleted. Activities will become unassigned.</p>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-danger" onclick="doDeleteProject(' + id + ')">Delete</button>';
        }

        async function doDeleteProject(id) {
            await api('/api/project/delete', { id });
            closeModal();
            await loadBrandsAndProjects();
        }

        // --- Rule CRUD ---
        function showAddRule() {
            if (projectsData.length === 0) {
                openModal('No Projects');
                document.getElementById('modal-body').innerHTML = '<p class="confirm-msg">Create a project first before adding rules.</p>';
                document.getElementById('modal-footer').innerHTML = '<button class="btn btn-primary" onclick="closeModal()">OK</button>';
                return;
            }
            openModal('Add Rule');
            let projOpts = projectsData.map(p => {
                const brand = brandsData.find(b => b.id === p.brandId);
                const label = (brand ? brand.name + ' > ' : '') + p.name;
                return '<option value="' + p.id + '">' + esc(label) + '</option>';
            }).join('');
            let typeOpts = RULE_TYPES.map(t => '<option value="' + t.value + '">' + esc(t.label) + '</option>').join('');
            document.getElementById('modal-body').innerHTML =
                '<div class="form-group"><label class="form-label">Project</label><select class="form-select" id="m-project">' + projOpts + '</select></div>' +
                '<div class="form-group"><label class="form-label">Rule Type</label><select class="form-select" id="m-ruletype">' + typeOpts + '</select></div>' +
                '<div class="form-group"><label class="form-label">Pattern</label><input class="form-input" id="m-pattern" placeholder="e.g. saasbridge.io"></div>' +
                '<div class="form-group"><div class="checkbox-row"><input type="checkbox" id="m-regex"><label for="m-regex">Regex</label></div></div>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-primary" onclick="doAddRule()">Add</button>';
            setTimeout(() => document.getElementById('m-pattern').focus(), 50);
        }

        async function doAddRule() {
            const projectId = parseInt(document.getElementById('m-project').value);
            const ruleType = document.getElementById('m-ruletype').value;
            const pattern = document.getElementById('m-pattern').value.trim();
            const isRegex = document.getElementById('m-regex').checked;
            if (!pattern) return;
            await api('/api/rule', { projectId, ruleType, pattern, isRegex });
            closeModal();
            await loadRules();
        }

        function confirmDeleteRule(id) {
            openModal('Delete Rule');
            document.getElementById('modal-body').innerHTML =
                '<p class="confirm-msg">Delete this rule? Activities matched by this rule will not be unassigned, but new activities won\\'t be matched.</p>';
            document.getElementById('modal-footer').innerHTML =
                '<button class="btn" onclick="closeModal()">Cancel</button>' +
                '<button class="btn btn-danger" onclick="doDeleteRule(' + id + ')">Delete</button>';
        }

        async function doDeleteRule(id) {
            await api('/api/rule/delete', { id });
            closeModal();
            await loadRules();
        }

        // --- Escape helpers ---
        function esc(s) { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
        function escAttr(s) { return s.replace(/'/g, "\\\\'").replace(/"/g, '&quot;'); }

        // --- Init ---
        loadBrandsAndProjects();
        """
    }
}
