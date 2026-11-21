const state = { files: new Map(), steps: [], selected: 0, rootName: '' };
const $ = (id) => document.getElementById(id);

document.addEventListener('DOMContentLoaded', () => {
  ['choose-directory', 'choose-directory-secondary'].forEach(id => $(id).addEventListener('click', pickDirectory));
  $('directory-input').addEventListener('change', e => loadFileList([...e.target.files]));
  loadHostedBundle();
});

async function loadHostedBundle() {
  try {
    const response = await fetch('dashboard-data/manifest.json', { cache: 'no-store' });
    if (!response.ok) return;
    const manifest = await response.json();
    const items = await Promise.all((manifest.files || []).map(async path => {
      const fileResponse = await fetch(`dashboard-data/${path}`);
      if (!fileResponse.ok) return null;
      return { file: new File([await fileResponse.blob()], path.split('/').pop()), path };
    }));
    loadFileList(items.filter(Boolean), manifest.name || 'Hosted project');
  } catch (error) {
    // A missing manifest is expected when the app is being used with a local directory.
  }
}

async function pickDirectory() {
  if ('showDirectoryPicker' in window) {
    try {
      const handle = await window.showDirectoryPicker();
      const files = [];
      async function walk(dir, prefix = '') { for await (const entry of dir.values()) { const path = prefix + entry.name; if (entry.kind === 'file') files.push(await entry.getFile().then(f => ({ file:f, path }))); else await walk(entry, path + '/'); } }
      await walk(handle); loadFileList(files, handle.name); return;
    } catch (error) { if (error.name === 'AbortError') return; }
  }
  $('directory-input').click();
}

function loadFileList(items, rootName) {
  if (!items.length) return;
  state.files.clear();
  const paths = items.map(item => item.path || item.file.webkitRelativePath || item.file.name);
  state.rootName = rootName || paths[0].split('/')[0] || 'Project';
  items.forEach(item => { const path = normalize(item.path || item.file.webkitRelativePath || item.file.name).replace(new RegExp('^' + escapeRegExp(state.rootName) + '/'), ''); state.files.set(path, item.file); });
  state.steps = [...state.files.entries()].filter(([path]) => /^\d+(?:[-_ .]|$).*\.sh$/i.test(path.split('/').pop())).map(([path, file]) => ({ path, file, number: parseInt(path.match(/^(\d+)/)[1], 10), name: niceName(path) })).sort((a,b) => a.number-b.number || a.path.localeCompare(b.path));
  renderDashboard();
}

function renderDashboard() { $('welcome').hidden = true; $('dashboard').hidden = false; $('project-name').textContent = state.rootName; $('step-count').textContent = `${state.steps.length} ${state.steps.length === 1 ? 'step' : 'steps'}`; $('file-count').textContent = `${state.files.size} files`; state.selected = 0; renderTabs(); renderStep(); }
function renderTabs() { const tabs = [{number:'00', name:'Dataset description', config:true}, ...state.steps.map(s => ({number:String(s.number).padStart(2,'0'), name:s.name}))]; $('step-tabs').innerHTML = tabs.map((t,i) => `<button class="tab ${i === state.selected ? 'active' : ''}" data-index="${i}"><span class="tab-number">${t.number}</span><span class="tab-name">${escapeHtml(t.name)}</span></button>`).join(''); document.querySelectorAll('.tab').forEach(t => t.addEventListener('click', () => { state.selected = Number(t.dataset.index); renderTabs(); renderStep(); })); }

async function renderStep() { const content = $('step-content'); if (state.selected === 0) { content.innerHTML = await renderConfig(); return; } const step = state.steps[state.selected - 1]; content.innerHTML = '<div class="card">Reading step…</div>'; const text = await step.file.text(); const parsed = parseScript(text); content.innerHTML = await renderStepHtml(step, text, parsed); }
async function renderConfig() { const entry = [...state.files.entries()].find(([path]) => path.toLowerCase().split('/').pop() === 'config.tsv'); if (!entry) return `<div class="notice">No <code>config.tsv</code> was found in this directory.</div>`; const text = await entry[1].text(); return `<div class="step-header"><div><h3>Dataset description</h3><p>Project-level settings loaded from <code>${escapeHtml(entry[0])}</code>.</p></div></div><div class="step-grid"><div class="card result-card"><h4>Configuration</h4>${renderCsv(text, '\t')}</div><div class="card"><h4>About this project</h4><p class="empty">This dashboard reads your pipeline directory locally. Use the numbered tabs to inspect each analysis step and its outputs.</p></div></div>`; }
async function renderStepHtml(step, text, parsed) { const inputs = parsed.inputs; const outputs = parsed.outputs; const display = [...new Set([...outputs, ...findOutputFiles(step, outputs)])]; return `<div class="step-header"><div><h3>${escapeHtml(step.name)}</h3><p><code>${escapeHtml(step.path)}</code> · ${inputs.length} inputs · ${display.length} outputs detected</p></div></div><div class="step-grid"><div class="card"><h4>Script</h4><pre class="script">${escapeHtml(text)}</pre></div><div class="card"><h4>Files referenced by script</h4>${renderFileList(inputs, 'input')}${display.length ? '<h4 style="margin-top:22px">Outputs</h4>' + renderFileList(display, 'output') : ''}</div>${await renderResults(display)}</div>`; }

function parseScript(text) { const inputs = new Set(), outputs = new Set(); text.split(/\r?\n/).forEach(raw => { const line = raw.replace(/\s+#.*$/, '').trim(); if (!line || line.startsWith('#')) return; const redirs = [...line.matchAll(/(?:>|>>|2>|2>>|<)\s*([^\s;&|]+)/g)]; redirs.forEach(m => { const p=cleanPath(m[1]); if (m[0].includes('<')) inputs.add(p); else outputs.add(p); }); const tokens = line.replace(/\\\s*$/,'').split(/\s+/).slice(1); tokens.forEach((token,i) => { const clean=cleanPath(token); const prev=tokens[i-1] || ''; if (/^(?:-o|--out(?:put)?|--output-dir|--outdir|--outfile|--report|--html)$/i.test(prev)) outputs.add(clean); else if (looksLikeFile(clean) && !clean.startsWith('-') && !/^(?:-o|--)/.test(token)) inputs.add(clean); }); }); outputs.forEach(x => inputs.delete(x)); return {inputs:[...inputs], outputs:[...outputs]}; }
function findOutputFiles(step, outputs) { const base = step.path.split('/').slice(0,-1).join('/'); return [...state.files.keys()].filter(path => /\.(?:html?|png|jpe?g|svg|csv|tsv)$/i.test(path) && !path.endsWith(step.path) && (outputs.some(o => path.endsWith(o.replace(/^\.\//,''))) || (base && path.startsWith(base + '/')))).filter(p => !outputs.includes(p)); }
function renderFileList(paths, type) { if (!paths.length) return '<p class="empty">None detected.</p>'; return `<div class="file-list">${paths.map(path => { const actual=findFile(path); return `<div class="file-row"><span class="file-type">${type}</span><span class="file-name" title="${escapeHtml(path)}">${escapeHtml(path)}</span>${actual ? `<a href="${URL.createObjectURL(actual)}" download="${escapeHtml(path.split('/').pop())}">save</a>` : '<span title="Not found">—</span>'}</div>`; }).join('')}</div>`; }
async function renderResults(paths) { const supported = paths.filter(path => findFile(path) && /\.(html?|png|jpe?g|svg|csv|tsv)$/i.test(path)); if (!supported.length) return ''; const blocks = await Promise.all(supported.map(async path => { const file=findFile(path), ext=path.split('.').pop().toLowerCase(), url=URL.createObjectURL(file); if (['png','jpg','jpeg','svg'].includes(ext)) return `<div class="result"><div class="result-title"><span>${escapeHtml(path)}</span><a href="${url}" target="_blank">open ↗</a></div><img src="${url}" alt="${escapeHtml(path)}" /></div>`; if (ext.startsWith('html')) return `<div class="result"><div class="result-title"><span>${escapeHtml(path)}</span><a href="${url}" target="_blank">open ↗</a></div><iframe sandbox="allow-scripts" src="${url}" title="${escapeHtml(path)}"></iframe></div>`; return `<div class="result"><div class="result-title"><span>${escapeHtml(path)}</span><a href="${url}" target="_blank">download ↗</a></div>${renderCsv(await file.text(), ext === 'tsv' ? '\t' : ',')}</div>`; })); return `<div class="card result-card"><h4>Rendered outputs</h4>${blocks.join('')}</div>`; }
function renderCsv(text, delimiter) { const rows=text.trim().split(/\r?\n/).filter(Boolean).map(row => row.split(delimiter)); if (!rows.length) return '<p class="empty">The file is empty.</p>'; return `<div class="csv-wrap"><table><thead><tr>${rows[0].map(c=>`<th>${escapeHtml(c)}</th>`).join('')}</tr></thead><tbody>${rows.slice(1,501).map(row=>`<tr>${rows[0].map((_,i)=>`<td>${escapeHtml(row[i] || '')}</td>`).join('')}</tr>`).join('')}</tbody></table>${rows.length>501?'<p class="empty" style="padding:12px">Showing first 500 rows.</p>':''}</div>`; }
function findFile(path) { const wanted=normalize(path).replace(/^\.\//,''); return state.files.get(wanted) || [...state.files.entries()].find(([key]) => key.endsWith('/'+wanted) || key === wanted)?.[1]; }
function looksLikeFile(s) { return /\.(fastq(?:\.gz)?|fq(?:\.gz)?|bam|sam|fa(?:sta)?|fna|csv|tsv|txt|json|html?|png|pdf|rds|biom|db)$/i.test(s); }
function cleanPath(s) { return s.replace(/^['"]|['"]$/g,'').replace(/[;,]$/,''); } function normalize(s){return s.replaceAll('\\','/').replace(/^\.\//,'');} function niceName(p){return p.split('/').pop().replace(/\.sh$/i,'').replace(/^\d+[-_ .]*/,'').replace(/[-_]+/g,' ') || p;} function escapeHtml(s){return String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));} function escapeRegExp(s){return s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}
