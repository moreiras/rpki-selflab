// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The rpki-selflab authors
// ============================================================================
// The lab panel: topology, side panel, the dock (terminals and web
// interfaces in tabs), the tools bar, events and layout. The guide lives in
// guide.js, the checkpoints in checks.js, the strings in i18n.js and the
// per-component texts in nodes.js.
// ============================================================================

let selected = null;
let lastState = null;
let prevState = null;
let labValuesApplied = false;
const events = [];

const $ = id => document.getElementById(id);

// ------------------------------------------------------------------ layout --
// Columns, left to right: guide | topology | side panel, or, with the dock
// open, guide | topology | dock (the dock replaces the side panel). A "wide"
// dock (the default for web interfaces, which need room) hides the topology.
const layout = {
  guide: PREF.get("guide-visible", "1") === "1",
  guideW: +PREF.get("guide-w", 0) || 0,
  dockW: +PREF.get("dock-w", 0) || 0,
  bottomH: +PREF.get("bottom-h", 0) || 0,   // 0 = CSS default (auto, capped)
  dock: null,                 // null | "normal" | "wide"
  mobileView: PREF.get("mobile-view", "guide"),
};
const narrow = () => window.matchMedia("(max-width: 1100px)").matches;

function applyLayout() {
  const main = $("main");
  const vw = window.innerWidth;
  const guideW = Math.round(Math.min(Math.max(layout.guideW || vw * 0.36, 320), vw * 0.6));
  const dockW = Math.round(Math.min(Math.max(layout.dockW || vw * 0.38, 360), vw * 0.7));
  const show = (id, on) => $(id).classList.toggle("hidden", !on);

  if (narrow()) {
    main.style.gridTemplateColumns = "";
    show("guide-pane", layout.mobileView === "guide");
    show("center-pane", layout.mobileView === "topology");
    show("panel", layout.mobileView === "topology");
    show("dock", !!layout.dock);
    show("split-guide", false); show("split-dock", false);
    document.querySelectorAll("#mobile-tabs button").forEach(b => b.classList.toggle("active", b.dataset.view === layout.mobileView));
    return;
  }
  const cols = [];
  show("guide-pane", layout.guide); show("split-guide", layout.guide);
  if (layout.guide) cols.push(`${guideW}px`, "6px");
  if (layout.dock === "wide") {
    show("center-pane", false); show("panel", false); show("dock", true); show("split-dock", false);
    cols.push("minmax(0,1fr)");
  } else if (layout.dock === "normal") {
    show("center-pane", true); show("panel", false); show("dock", true); show("split-dock", true);
    cols.push("minmax(0,1fr)", "6px", `${dockW}px`);
  } else {
    show("center-pane", true); show("panel", true); show("dock", false); show("split-dock", false);
    cols.push("minmax(0,1fr)", "340px");
  }
  main.style.gridTemplateColumns = cols.join(" ");
  applyBottomHeight();
  $("btn-guide-toggle").textContent = layout.guide ? "◧" : "▤";
  $("btn-guide-toggle").title = t(layout.guide ? "hide_guide" : "show_guide");
  $("dock-wide").textContent = layout.dock === "wide" ? "⤡" : "⤢";
  $("dock-wide").title = t(layout.dock === "wide" ? "dock_narrow" : "dock_widen");
}

// Height of the Verdicts/Events box under the topology, set by dragging the
// horizontal splitter; clamped so neither half can be squeezed away.
function applyBottomHeight() {
  const pane = $("center-pane"), box = pane.querySelector(".bottom-box");
  if (!layout.bottomH) { pane.style.gridTemplateRows = ""; box.style.maxHeight = ""; return; }
  if (pane.clientHeight < 300) return;                 // hidden or tiny: leave as is
  const h = Math.round(Math.min(Math.max(layout.bottomH, 90), pane.clientHeight - 160));
  pane.style.gridTemplateRows = `minmax(0, 1fr) 6px ${h}px`;
  box.style.maxHeight = "none";
}

function setGuideVisible(on) {
  layout.guide = on;
  PREF.set("guide-visible", on ? "1" : "0");
  applyLayout();
}

function makeSplitter(el, onDrag, onStart) {
  el.addEventListener("pointerdown", e => {
    e.preventDefault();
    if (onStart) onStart(e.clientX, e.clientY);
    el.classList.add("dragging");
    el.setPointerCapture(e.pointerId);
    // iframes swallow pointer events mid-drag; mute them meanwhile
    document.querySelectorAll("iframe").forEach(f => f.style.pointerEvents = "none");
    const move = ev => onDrag(ev.clientX, ev.clientY);
    const up = () => {
      el.classList.remove("dragging");
      document.querySelectorAll("iframe").forEach(f => f.style.pointerEvents = "");
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
  });
}
makeSplitter($("split-guide"), x => { layout.guideW = x; PREF.set("guide-w", x); applyLayout(); });
makeSplitter($("split-dock"), x => { layout.dockW = window.innerWidth - x; PREF.set("dock-w", layout.dockW); applyLayout(); });
// dragging moves the box's top edge by exactly as much as the pointer moved
let bottomDrag = null;
makeSplitter($("split-bottom"), (x, y) => {
  layout.bottomH = Math.round(bottomDrag.h + bottomDrag.y - y);
  PREF.set("bottom-h", layout.bottomH); applyBottomHeight();
}, (x, y) => {
  bottomDrag = { y, h: $("center-pane").querySelector(".bottom-box").getBoundingClientRect().height };
});
$("split-bottom").addEventListener("dblclick", () => { layout.bottomH = 0; PREF.set("bottom-h", 0); applyBottomHeight(); });
window.addEventListener("resize", applyLayout);
document.querySelectorAll("#mobile-tabs button").forEach(b => b.onclick = () => {
  layout.mobileView = b.dataset.view; PREF.set("mobile-view", layout.mobileView); applyLayout();
});

// -------------------------------------------------------------------- dock --
// Tabs of terminals (ttyd, one per box) and web interfaces. A tab's iframe
// stays alive while you switch to another, so a terminal keeps its session.
const dockTabs = [];          // {key, label, url, kind}
let activeDock = null;
const WEB = {
  krill:       () => ({ label: "Krill", url: KRILL_URL }),
  routinator:  () => ({ label: "Routinator", url: ROUTINATOR_URL }),
  registry:    () => ({ label: t("tool_registry"), url: REGISTRY_URL }),
};
const rirName = () => ((lastState && lastState.config) || {}).RIR_NAME || "LabNIC";
const isLocalMode = () => (((lastState && lastState.config) || {}).MODE || "local") === "local";

function openDock(key, label, url, kind) {
  let tab = dockTabs.find(x => x.key === key);
  if (!tab) {
    tab = { key, label, url, kind };
    dockTabs.push(tab);
    const f = document.createElement("iframe");
    f.dataset.key = key;
    f.title = label;
    f.className = kind === "term" ? "term" : "web";
    // every tab is another origin (krill.localhost, console.localhost...):
    // without this, Krill's "copy XML" and the terminals' copy/paste are
    // silently blocked by the browser's permissions policy
    f.allow = "clipboard-read; clipboard-write";
    f.src = url;
    $("dock-frames").appendChild(f);
    if (key === "web:krill") toast(t("krill_login_toast"), "info", 9000);
  } else if (tab.url !== url) {
    // the same terminal asked to run something else: reload it
    tab.url = url;
    const f = [...$("dock-frames").children].find(x => x.dataset.key === key);
    if (f) f.src = url;
  }
  activeDock = key;
  if (!layout.dock) layout.dock = kind === "web" ? "wide" : "normal";
  else if (kind === "web" && layout.dock === "normal" && window.innerWidth < 1700) layout.dock = "wide";
  paintDock();
  applyLayout();
}

function closeDockTab(key) {
  const i = dockTabs.findIndex(x => x.key === key);
  if (i < 0) return;
  dockTabs.splice(i, 1);
  const f = [...$("dock-frames").children].find(x => x.dataset.key === key);
  if (f) f.remove();
  if (activeDock === key) activeDock = dockTabs.length ? dockTabs[Math.max(0, i - 1)].key : null;
  if (!dockTabs.length) layout.dock = null;
  paintDock();
  applyLayout();
}

function closeDock() {
  while (dockTabs.length) closeDockTab(dockTabs[0].key);
}

function paintDock() {
  $("dock-tabs").innerHTML = dockTabs.map(x =>
    `<span class="dock-tab${x.key === activeDock ? " active" : ""}" data-key="${esc(x.key)}">` +
    `${x.kind === "term" ? "⌨" : "🌐"} ${esc(x.label)}` +
    `<button class="x" data-close="${esc(x.key)}" title="${esc(t("dock_close_tab"))}">×</button></span>`).join("");
  $("dock-tabs").querySelectorAll(".dock-tab").forEach(el => el.onclick = e => {
    if (e.target.dataset.close) return closeDockTab(e.target.dataset.close);
    activeDock = el.dataset.key; paintDock();
  });
  [...$("dock-frames").children].forEach(f => f.classList.toggle("active", f.dataset.key === activeDock));
  document.querySelectorAll(".tool").forEach(b => {
    const key = b.dataset.tool;
    b.classList.toggle("active", activeDock === "web:" + key || activeDock === "term:" + key);
  });
}

$("dock-close").onclick = closeDock;
$("dock-wide").onclick = () => { layout.dock = layout.dock === "wide" ? "normal" : "wide"; applyLayout(); };
$("dock-newtab").onclick = () => {
  const tab = dockTabs.find(x => x.key === activeDock);
  if (tab) window.open(tab.url, "_blank", "noopener");
};

// ttyd's URL arguments become menu.sh's $1 and $2 (images/console/menu.sh)
function terminalUrl(node, mode) {
  return TTYD_URL + "/?" + ["arg=" + encodeURIComponent(node), mode ? "arg=" + encodeURIComponent(mode) : ""].filter(Boolean).join("&");
}

function openTerminal(node, mode, label) {
  openDock(`term:${node}${mode ? ":" + mode : ""}`, label || node, terminalUrl(node, mode), "term");
}

// From the guide's command blocks: the right terminal for a target box.
function openTerminalFor(target) {
  if (target === "lab") return openTerminal("lab", "", t("tool_lab_terminal"));
  if (target === "krill" || target === "rir") return openTerminal(target, "", `${target} · krillc`);
  openTerminal(target, "", `${target} · Shell`);
}

// Runs one ./scripts/lab.sh command in the Lab terminal (menu.sh only
// accepts the lab's own commands there).
function runLabCommand(cmd) {
  openDock("term:lab", t("tool_lab_terminal"), terminalUrl("lab", cmd) + `&_=${Date.now()}`, "term");
}

function openWeb(key) {
  const w = WEB[key]();
  // reached by IP, the apps sit on their own ports with HTTPS/self-signed
  // certificates, which an iframe can't click through: use a tab instead
  if (!VHOST) return window.open(w.url, "_blank", "noopener");
  openDock("web:" + key, w.label, w.url, "web");
}

// ------------------------------------------------------------- tools bar --
document.querySelectorAll(".tool").forEach(b => b.onclick = e => {
  const k = b.dataset.tool;
  if (k === "lab") return openTerminal("lab", "", t("tool_lab_terminal"));
  if (k === "commands") return toggleCommandsPopover(b);
  if (k === "registry" && !isLocalMode()) return window.open(REGISTRO_BR_URL, "_blank", "noopener");
  openWeb(k);
});

function paintTools() {
  const local = isLocalMode();
  $("tool-registry-label").textContent = local ? t("tool_registry") : "beta.registro.br ↗";
  const tips = {
    lab: t("tip_lab_terminal"), commands: t("tip_lab_commands"),
    krill: t("tip_web", { name: "Krill" }), routinator: t("tip_web", { name: "Routinator" }),
    registry: local ? t("tip_web", { name: t("tool_registry") }) : t("tip_external", { name: "beta.registro.br" }),
  };
  document.querySelectorAll(".tool").forEach(b => b.title = tips[b.dataset.tool] || "");
}

const LAB_COMMANDS = ["refresh", "doctor", "status", "clean-objects",
                      "step1-clean", "step2-hijack-simple", "step3-rov-mark",
                      "step4-hijack-posrov", "step5-aspa-mark", "step6-add-provider-b",
                      "step7-leak-on", "step8-drop", "step9-leak-off", "step9-hijack-off"];

function commandsTable() {
  return `<table class="verdicts"><thead><tr><th></th><th>${esc(t("lab_cmds_col_cmd"))}</th><th>${esc(t("lab_cmds_col_desc"))}</th></tr></thead><tbody>` +
    LAB_COMMANDS.map(c => `<tr><td><button class="btn small" data-run="${c}" title="${esc(t("run_here"))}">▶</button></td>` +
                          `<td class="mono">./scripts/lab.sh ${c}</td><td>${t(`lab_cmd_${c}_desc`)}</td></tr>`).join("") +
    `</tbody></table>`;
}

function toggleCommandsPopover(anchor) {
  const pop = $("popover");
  if (!pop.classList.contains("hidden")) { pop.classList.add("hidden"); return; }
  pop.innerHTML = `<h3>${esc(t("lab_cmds_title"))}</h3><p>${esc(t("lab_cmds_intro"))}</p>` +
                  commandsTable() + `<div class="warn-box">${t("lab_cmds_reset_warning")}</div>`;
  const r = anchor.getBoundingClientRect();
  pop.style.top = `${r.bottom + 6}px`;
  pop.style.left = `${Math.max(8, Math.min(r.left, window.innerWidth - 640))}px`;
  pop.classList.remove("hidden");
  pop.querySelectorAll("[data-run]").forEach(b => b.onclick = () => { pop.classList.add("hidden"); runLabCommand(b.dataset.run); });
}
document.addEventListener("click", e => {
  const pop = $("popover");
  if (!pop.classList.contains("hidden") && !pop.contains(e.target) && !e.target.closest('[data-tool="commands"]')) pop.classList.add("hidden");
});

// -------------------------------------------------------------- side panel --
function tag(v) {
  const c = ["Valid", "Invalid", "Unknown", "NotFound"].includes(v) ? v : "off";
  const sym = { Valid: "✓ ", Invalid: "✕ ", Unknown: "? ", NotFound: "? " }[v] || "";
  return `<span class="tag ${c}">${sym}${v === "-" || !v ? "—" : esc(v)}</span>`;
}

// Values written into the side-panel texts (nodes.js) are the defaults;
// when lab.conf has different ones, they're swapped in at render time.
const DEFAULTS = { ASN: "64500", V4: "203.0.113.0/24", V6: "3fff:cafe::/32" };
function substituteDefaults(text) {
  const g = (lastState && lastState.config) || {};
  let r = String(text);
  const swap = (from, to) => { if (to && to !== from) r = r.split(from).join(to); };
  swap(DEFAULTS.V4, g.ORIGIN_V4);
  swap(DEFAULTS.V6, g.ORIGIN_V6);
  swap(DEFAULTS.ASN, g.ORIGIN_ASN);
  return r;
}

function registryNode(g) {
  const language = currentLanguage();
  const local = (g.MODE || "local") === "local";
  const base = local ? NODES[language].registry_local : NODES[language].registry_beta;
  return {
    name: local ? `${rirName()} — ${t("tool_registry")}` : "beta.registro.br",
    role: base.role, info: base.info, hint: base.hint || null,
    web: local ? ["registry", t("tool_registry")] : null,
    links: local ? [] : [["beta.registro.br ↗", REGISTRO_BR_URL]],
    term: local ? [["Terminal (krillc)", "rir"]] : [],
  };
}

function renderWelcome() {
  selected = null;
  document.querySelectorAll(".node").forEach(n => n.classList.remove("sel"));
  const steps = ["step1-clean", "step2-hijack-simple", "step3-rov-mark", "step4-hijack-posrov", "step5-aspa-mark",
                 "step6-add-provider-b", "step7-leak-on", "step8-drop", "step9-leak-off"];
  $("panel").innerHTML =
    `<h2>${esc(t("panel_initial_title"))}</h2><p class="role-large">${esc(t("panel_initial_text"))}</p>` +
    `<ol class="intro-list"><li>${t("intro_1")}</li><li>${t("intro_2")}</li><li>${t("intro_3")}</li><li>${t("intro_4")}</li></ol>` +
    `<div class="section"><h3>${esc(t("explore_title"))}</h3><p>${esc(t("explore_text"))}</p><div class="actions">` +
    steps.map(s => `<button class="btn small" data-run="${s}" title="./scripts/lab.sh ${s}">▶ ${s}</button>`).join("") +
    `</div></div>`;
  $("panel").querySelectorAll("[data-run]").forEach(b => b.onclick = () => runLabCommand(b.dataset.run));
}

function renderPanel(id) {
  if (!id) return renderWelcome();
  selected = id;
  document.querySelectorAll(".node").forEach(n => n.classList.toggle("sel", n.dataset.id === id));
  const language = currentLanguage();
  const state = lastState || {};
  const n = id === "registry" ? registryNode(state.config || {}) : (NODES[language][id] || NODES.en[id]);
  let h = `<h2>${esc(n.name)}</h2><p class="role-large">${esc(n.role)}</p><div class="actions">`;
  if (n.web) h += `<button class="btn pri" data-web="${n.web[0]}">🌐 ${esc(n.web[1])}</button>`;
  for (const [label, url] of (n.links || [])) h += `<a class="btn" href="${url}" target="_blank" rel="noopener">${esc(label)} ↗</a>`;
  for (const [label, node, mode] of (n.term || [])) {
    h += `<button class="btn" data-term="${node}" data-mode="${mode || ""}" data-label="${esc(label)}">⌨ ${esc(label)}</button>`;
  }
  h += `</div><dl class="info">`;
  for (const [k, v] of Object.entries(n.info || {})) h += `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`;
  h += `</dl>`;

  if (id === "krill") {
    const k = state.krill || {};
    if (!k.ca) h += `<div class="warn-box">${esc(t("krill_no_ca"))}</div>`;
    else {
      const r = k.resources || {};
      h += `<div class="section"><h3>${esc(t("krill_resources"))}</h3><dl class="info">` +
           `<dt>CA</dt><dd>${esc(k.ca)}</dd><dt>${esc(t("krill_parent"))}</dt><dd>${esc((k.parents || []).join(", ") || "—")}</dd>` +
           `<dt>ASN</dt><dd>${esc(r.asn || "—")}</dd><dt>IPv4</dt><dd>${esc(r.ipv4 || "—")}</dd><dt>IPv6</dt><dd>${esc(r.ipv6 || "—")}</dd></dl></div>`;
      h += `<div class="section"><h3>${esc(t("krill_roas"))}</h3>` + ((k.roas || []).length
        ? `<table class="verdicts"><tbody>${k.roas.map(x => `<tr><td class="mono">${esc(x.prefix)}-${esc(x.max_length)}</td><td class="mono">AS${esc(x.asn)}</td></tr>`).join("")}</tbody></table>`
        : `<p>${esc(t("krill_none"))}</p>`) + `</div>`;
      h += `<div class="section"><h3>${esc(t("krill_aspas"))}</h3>` + ((k.aspas || []).length
        ? `<table class="verdicts"><tbody>${k.aspas.map(x => `<tr><td class="mono">AS${esc(x.customer)}</td><td class="mono">→ ${esc(x.providers.map(p => "AS" + p).join(", "))}</td></tr>`).join("")}</tbody></table>`
        : `<p>${esc(t("krill_none"))}</p>`) + `</div>`;
      h += `<div class="section"><p>${t("krill_where")}</p></div>`;
    }
  }

  const nodeData = (state.nodes || {})[id];
  if (nodeData && nodeData.protocols && nodeData.protocols.length) {
    h += `<div class="section"><h3>${esc(t("sessions_title"))}</h3><table class="verdicts"><tbody>`;
    for (const p of nodeData.protocols) {
      const up = p.state === "up";
      h += `<tr><td class="mono">${esc(p.name)}</td><td>${esc(p.type)}</td>` +
           `<td><span class="tag ${up ? "Valid" : "Invalid"}">${esc(t(up ? "state_up" : "state_down"))}</span></td>` +
           `<td class="mono" style="color:var(--text-weak)">${esc(p.info)}</td></tr>`;
    }
    h += `</tbody></table></div>`;
  }
  if (id === "observer1" && nodeData && nodeData.tables) {
    const tb = nodeData.tables;
    h += `<div class="section"><h3>${esc(t("rtr_tables"))}</h3><dl class="info">` +
         `<dt>ROA v4</dt><dd>${tb.roa4 ?? "—"}</dd><dt>ROA v6</dt><dd>${tb.roa6 ?? "—"}</dd><dt>ASPA</dt><dd>${tb.aspa ?? "—"}</dd></dl></div>`;
  }
  if (id === "routinator" && state.routinator) {
    const r = state.routinator;
    h += `<div class="section"><h3>${esc(t("validated_set"))}</h3><dl class="info">` +
         `<dt>VRPs</dt><dd>${r.vrps ?? "—"}</dd><dt>ASPAs</dt><dd>${r.aspas ?? "—"}</dd></dl>`;
    if ((r.vrp_list || []).length) {
      h += `<h3>${esc(t("vrp_list"))}</h3><table class="verdicts"><tbody>` +
           r.vrp_list.map(x => `<tr><td class="mono">${esc(x.prefix)}</td><td class="mono">max ${esc(x.maxLength)}</td><td class="mono">${esc(x.asn)}</td></tr>`).join("") +
           `</tbody></table>`;
    }
    if ((r.aspa_list || []).length) h += `<h3>ASPA</h3><pre>${esc(r.aspa_list.map(a => `${a.customer} => ${a.providers.join(", ")}`).join("\n"))}</pre>`;
    h += `</div>`;
  }
  if (id === "fort" && state.fort) {
    const f = state.fort;
    h += `<div class="section"><h3>${esc(t("validated_set"))}</h3><dl class="info">` +
         `<dt>VRPs</dt><dd>${f.roas ?? "—"}</dd><dt>ASPAs</dt><dd>${f.aspas ?? "—"}</dd></dl>`;
    if ((f.aspa_list || []).length) h += `<pre>${esc(f.aspa_list.map(a => `AS${a.customer} => ${a.providers.map(p => "AS" + p).join(", ")}`).join("\n"))}</pre>`;
    h += `</div>`;
  }
  if (n.hint) h += `<div class="section"><h3>${esc(t("useful_commands"))}</h3><pre>${esc(n.hint)}</pre></div>`;
  if (n.edit) {
    h += `<div class="section"><h3>${esc(t("edit_title"))}</h3><p>${t("edit_text")}</p>` +
         `<pre>${esc(`${n.edit.copy}\nnano work/${n.edit.copy.split("work/")[1]}\n${n.edit.load}`)}</pre>` +
         `<p>${esc(t("edit_back"))}</p></div>`;
  }

  $("panel").innerHTML = substituteDefaults(h);
  $("panel").querySelectorAll("[data-term]").forEach(b => {
    b.onclick = () => openTerminal(b.dataset.term, b.dataset.mode, `${id} · ${b.dataset.label}`);
  });
  $("panel").querySelectorAll("[data-web]").forEach(b => b.onclick = () => openWeb(b.dataset.web));
}

document.querySelectorAll(".node").forEach(el => {
  el.addEventListener("click", () => renderPanel(el.dataset.id));
  el.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); renderPanel(el.dataset.id); } });
});

// ---------------------------------------------------------------- topology --
function setStatus(id, text, kind) {
  const el = $("s-" + id);
  if (!el) return;
  el.textContent = text;
  el.setAttribute("fill", kind === "ok" ? "var(--ok)" : kind === "error" ? "var(--error)"
                          : kind === "warn" ? "var(--warn)" : "var(--text-weak)");
}

const norm = p => String(p || "").replace(/_/g, "-");
const routesFor = (state, o) => [...(((state.nodes || {})[o] || {}).routes4 || []), ...(((state.nodes || {})[o] || {}).routes6 || [])];

function fromLabel(proto) {
  const p = norm(proto);
  if (p.startsWith("provider-a")) return t("provider_a");
  if (p.startsWith("provider-b")) return t("provider_b");
  if (p.startsWith("attacker")) return "AS" + ((lastState && lastState.config && lastState.config.ATTACKER_ASN) || "666");
  return proto;
}

function paint(state) {
  lastState = state;
  $("clock").textContent = state.error ? (t("error_prefix") + state.error) : "";
  const nodes = state.nodes || {};

  for (const id of ["origin", "provider-a", "provider-b", "observer1", "observer2"]) {
    const d = nodes[id];
    if (!d) { setStatus(id, "—", ""); continue; }
    const bgp = (d.protocols || []).filter(p => p.type === "BGP");
    const up = bgp.filter(p => p.state === "up").length;
    setStatus(id, d.up ? `BGP ${up}/${bgp.length}` : t("status_stopped"),
              !d.up ? "error" : (bgp.length && up === bgp.length) ? "ok" : "warn");
  }

  // the observers' deployment stage: one badge for both, orange if they disagree
  const stg = state.stage || {};
  const badge = $("stage-badge");
  const a = stg.observer1, b = stg.observer2;
  badge.classList.remove("mark", "drop", "mixed");
  if (!a || !b) badge.textContent = t("stage_unknown");
  else if (a !== b) { badge.textContent = t("stage_mixed", { a, b }); badge.classList.add("mixed"); }
  else {
    badge.textContent = t("stage_" + a.replace("-", "_"));
    if (a.endsWith("mark")) badge.classList.add("mark");
    else if (a.endsWith("drop")) badge.classList.add("drop");
  }

  const atk = nodes.attacker || {};
  if (!atk.up) setStatus("attacker", t("status_stopped"), "error");
  else setStatus("attacker", atk.announcing ? t("status_hijacking") : t("status_silent"), atk.announcing ? "warn" : "");
  const peerNode = nodes.peer || {};
  if (!peerNode.up) setStatus("peer", t("status_stopped"), "error");
  else setStatus("peer", peerNode.leaking ? t("status_leaking") : t("status_peering"), peerNode.leaking ? "warn" : "ok");

  const r = state.routinator || {};
  setStatus("routinator", r.vrps == null ? "—" : `${r.vrps} VRP · ${r.aspas ?? 0} ASPA`, r.vrps ? "ok" : "warn");
  const f = state.fort || {};
  setStatus("fort", !f.up ? t("status_stopped") : (f.roas == null ? "—" : `${f.roas} VRP · ${f.aspas ?? 0} ASPA`),
            !f.up ? "error" : (f.roas ? "ok" : "warn"));
  const k = state.krill || {};
  if (!k.up) setStatus("krill", t("status_stopped"), "error");
  else if (!k.ca) setStatus("krill", t("status_no_ca"), "warn");
  else setStatus("krill", t("status_objects", { roas: (k.roas || []).length, aspas: (k.aspas || []).length }), "ok");

  const g = state.config || {};
  const local = (g.MODE || "local") === "local";
  $("n-registry").textContent = local ? (g.RIR_NAME || "LabNIC") : "beta.registro.br";
  $("n-holder").textContent = g.HOLDER_NAME || "ACME Internet Ltda.";
  if (local) setStatus("registry", (state.rir || {}).up ? t("status_up") : t("status_stopped"), (state.rir || {}).up ? "ok" : "error");
  else setStatus("registry", t("status_external"), "");

  paintVerdicts(state);
  paintLinks(state, atk, peerNode);
  paintTools();
  paintStepChip(state);
  diffEvents(prevState, state);
  prevState = state;

  if (selected) renderPanel(selected);
  updateCheckpoints();

  // the first time lab.conf arrives, its LANGUAGE becomes the default (unless
  // this browser already picked one); re-render everything if that changed it
  if (!labValuesApplied && state.config) {
    labValuesApplied = true;
    const before = currentLanguage();
    if (state.config.LANGUAGE) suggestDefaultLanguage(state.config.LANGUAGE);
    if (currentLanguage() !== before) onLanguageChange();
  }
}

let changedRows = new Map();      // row key -> expiry (ms)
function routeKey(obs, x) { return `${obs}|${x.net}|${norm(x.proto)}`; }

function paintVerdicts(state) {
  const rows = [];
  for (const obs of ["observer1", "observer2"]) for (const x of routesFor(state, obs)) rows.push([obs, x]);
  const tb = document.querySelector("#tab-verdicts tbody");
  const now = Date.now();
  if (!rows.length) {
    tb.innerHTML = `<tr><td colspan="7" style="color:var(--text-weak)">${esc(t("no_routes"))}</td></tr>`;
    return;
  }
  tb.innerHTML = rows.map(([obs, x]) => {
    const changed = (changedRows.get(routeKey(obs, x)) || 0) > now;
    return `<tr${changed ? ' class="changed"' : ""}><td class="mono">${esc(obs)}</td>` +
           `<td class="mono">${esc(x.net)}${x.best ? ` <span class="tag best">${esc(t("best"))}</span>` : ""}</td>` +
           `<td>${esc(fromLabel(x.proto))}</td><td class="mono">${esc(x.path)}</td>` +
           `<td>${tag(x.rov)}</td><td>${tag(x.aspa)}</td><td class="mono">${x.local_pref ?? x.pref ?? ""}</td></tr>`;
  }).join("");
}

function setLink(id, cls) {
  const el = $(id);
  if (!el) return;
  const before = el.dataset.state || "";
  for (const c of ["good", "bad", "warn"]) el.classList.toggle(c, c === cls);
  el.dataset.state = cls || "";
  if (prevState && before !== (cls || "")) pulse(el);
}

function pulse(el) {
  el.classList.remove("pulse"); void el.getBoundingClientRect(); el.classList.add("pulse");
  setTimeout(() => el.classList.remove("pulse"), 1500);
}

function paintLinks(state, atk, peerNode) {
  const flows = [];
  // each provider link is coloured by that path's ASPA verdict at that observer
  for (const [linkId, obs, prov] of [["e-a-obs1", "observer1", "provider-a"], ["e-b-obs1", "observer1", "provider-b"],
                                     ["e-a-obs2", "observer2", "provider-a"], ["e-b-obs2", "observer2", "provider-b"]]) {
    const route = routesFor(state, obs).find(x => norm(x.proto).startsWith(prov));
    const v = route ? route.aspa : null;
    setLink(linkId, v === "Valid" ? "good" : v === "Invalid" ? "bad" : null);
    if (route) flows.push([linkId, v === "Invalid" ? "bad" : ""]);
  }
  for (const id of ["e-org-a", "e-org-b"]) flows.push([id, ""]);

  // AS666's links: red when what it announces is flagged or dropped,
  // orange when an observer is accepting it
  for (const [linkId, obs] of [["e-atk-obs1", "observer1"], ["e-atk-obs2", "observer2"]]) {
    const route = routesFor(state, obs).find(x => norm(x.proto).startsWith("attacker"));
    const flagged = !route || route.rov === "Invalid" || route.aspa === "Invalid";
    setLink(linkId, atk.announcing ? (flagged ? "bad" : "warn") : null);
    if (atk.announcing) flows.push([linkId, flagged ? "bad" : "warn"]);
  }

  // peer: the peering link is healthy when its session is up; the transit
  // link to Provider A shows the leak
  const peeringUp = (peerNode.protocols || []).some(p => p.name === "origin_v4" && p.state === "up");
  setLink("e-peer-org", peeringUp ? "good" : null);
  const peerAsn = String((state.config || {}).PEER_ASN || "64499");
  const leaked = [...routesFor(state, "observer1"), ...routesFor(state, "observer2")]
    .filter(x => String(x.path).split(/\s+/).includes(peerAsn));
  const leakAccepted = leaked.some(x => x.rov !== "Invalid" && x.aspa !== "Invalid");
  setLink("e-peer-a", peerNode.leaking ? (leakAccepted ? "warn" : "bad") : null);
  if (peerNode.leaking) flows.push(["e-peer-a", leakAccepted ? "warn" : "bad"]);

  // RTR links: BIRD reports the session as an RPKI protocol, OpenBGPD as RTR
  const rtr1 = (((state.nodes || {}).observer1 || {}).protocols || []).find(p => p.type === "RPKI");
  const rtr2 = (((state.nodes || {}).observer2 || {}).protocols || []).find(p => p.type === "RTR");
  for (const [linkId, pr] of [["e-rtr1", rtr1], ["e-rtr2", rtr2]]) setLink(linkId, pr ? (pr.state === "up" ? "good" : "bad") : null);

  const layer = $("flow-layer");
  const want = flows.map(([id, c]) => `${id}:${c}`).join(",");
  if (layer.dataset.flows !== want) {
    layer.dataset.flows = want;
    layer.innerHTML = flows.map(([id, c]) => {
      const src = $(id);
      return src ? `<path class="flow ${c}" d="${src.getAttribute("d")}"/>` : "";
    }).join("");
  }
}

function paintStepChip(state) {
  const chip = $("step-chip");
  const n = inferStep(state);
  const idx = n ? stepIndexFor(n) : -1;
  if (idx < 0) { chip.classList.add("hidden"); return; }
  chip.classList.remove("hidden");
  chip.textContent = t("step_chip", { step: steps[idx].title.split(":")[0] });
  chip.onclick = () => { if (narrow()) { layout.mobileView = "guide"; applyLayout(); } else if (!layout.guide) setGuideVisible(true); showStep(idx); };
}

// ------------------------------------------------------------------ events --
function addEvent(text, kind) {
  events.unshift({ ts: new Date().toTimeString().slice(0, 8), text, kind });
  if (events.length > 200) events.pop();
}

function paintEvents() {
  $("events").innerHTML = events.length
    ? events.map(e => `<li><span class="ts">${e.ts}</span><span>${e.text}</span></li>`).join("")
    : `<li class="empty">${esc(t("events_empty"))}</li>`;
}

function toast(html, kind = "info", ms = 5000) {
  const el = document.createElement("div");
  el.className = "toast " + kind;
  el.innerHTML = html;
  $("toasts").appendChild(el);
  while ($("toasts").children.length > 4) $("toasts").firstChild.remove();
  setTimeout(() => { el.classList.add("leaving"); setTimeout(() => el.remove(), 350); }, ms);
}

// What changed between two collector cycles, in words: goes to the Events
// list, and the most important lines also pop up as toasts.
function diffEvents(a, b) {
  if (!a || a.error || b.error) return;
  const out = [];       // [text, kind, important]
  const cfg = b.config || {};
  const atkAsn = cfg.ATTACKER_ASN || "666";

  const sa = a.stage || {}, sb = b.stage || {};
  if (sb.observer1 && sb.observer1 === sb.observer2 && (sa.observer1 !== sb.observer1 || sa.observer2 !== sb.observer2)) {
    out.push([t("ev_stage", { stage: `<b>${esc(t("stage_" + sb.observer1.replace("-", "_")))}</b>` }), "info", true]);
  }
  const aa = (a.nodes || {}).attacker || {}, ab = (b.nodes || {}).attacker || {};
  const atkPath = s => { const r = routesFor(s, "observer1").find(x => norm(x.proto).startsWith("attacker")) || routesFor(s, "observer2").find(x => norm(x.proto).startsWith("attacker")); return r ? String(r.path) : ""; };
  if (!aa.announcing && ab.announcing) {
    const p = atkPath(b);
    const kind = !p ? "" : p.split(/\s+/).length > 1 ? t("kind_forged", { path: p }) : t("kind_simple", { path: p });
    out.push([t("ev_attacker_on", { asn: atkAsn, kind }), "warn", true]);
  } else if (aa.announcing && !ab.announcing) out.push([t("ev_attacker_off", { asn: atkAsn }), "ok", true]);
  else if (aa.announcing && ab.announcing && atkPath(a) && atkPath(b) && atkPath(a) !== atkPath(b)) {
    const p = atkPath(b);
    out.push([t("ev_attacker_on", { asn: atkAsn, kind: p.split(/\s+/).length > 1 ? t("kind_forged", { path: p }) : t("kind_simple", { path: p }) }), "warn", true]);
  }
  const pa = (a.nodes || {}).peer || {}, pb = (b.nodes || {}).peer || {};
  if (!pa.leaking && pb.leaking) out.push([t("ev_peer_on"), "warn", true]);
  if (pa.leaking && !pb.leaking) out.push([t("ev_peer_off"), "ok", true]);

  // A validator that just restarted reports nothing until its first
  // validation run ends; while Krill still holds objects, that's
  // "revalidating", not "the objects are gone".
  const krillHasObjects = ((b.krill || {}).roas || []).length + ((b.krill || {}).aspas || []).length > 0;
  const validatorEvent = (name, va, vb, na, nb) => {
    if (vb == null || (va === vb && na === nb)) return;
    if (!vb && !nb && krillHasObjects) { out.push([t("ev_revalidating", { v: name }), "info", false]); return; }
    out.push([t("ev_validator", { v: name, a: `${va ?? "—"} VRP · ${na ?? 0} ASPA`, b: `${vb} VRP · ${nb ?? 0} ASPA` }), "info", name === "Routinator"]);
  };
  const ra = a.routinator || {}, rb = b.routinator || {};
  validatorEvent("Routinator", ra.vrps, rb.vrps, ra.aspas, rb.aspas);
  const fa = a.fort || {}, fb = b.fort || {};
  validatorEvent("FORT", fa.roas, fb.roas, fa.aspas, fb.aspas);
  const ka = a.krill || {}, kb = b.krill || {};
  if (kb.ca && ka.ca && (ka.roas || []).length !== (kb.roas || []).length) out.push([t("ev_krill_roas", { n: (kb.roas || []).length }), "info", true]);
  const aspaStr = k => (k.aspas || []).map(x => `AS${x.customer} → ${x.providers.map(p => "AS" + p).join(", ")}`).join("; ");
  if (kb.ca && ka.ca && aspaStr(ka) !== aspaStr(kb))
    out.push([aspaStr(kb) ? t("ev_krill_aspa", { list: esc(aspaStr(kb)) }) : t("ev_krill_noaspa"), "info", true]);

  const now = Date.now();
  for (const obs of ["observer1", "observer2"]) {
    const before = new Map(routesFor(a, obs).map(x => [routeKey(obs, x), x]));
    const after = new Map(routesFor(b, obs).map(x => [routeKey(obs, x), x]));
    // a whole table emptied or refilled at once is the router restarting
    // (observer2 restarts on every stage change): one line, not one per route
    if (before.size && !after.size) { out.push([t("ev_table_empty", { obs }), "info", false]); continue; }
    if (!before.size && after.size) {
      out.push([t("ev_table_full", { obs, n: after.size }), "info", false]);
      for (const key of after.keys()) changedRows.set(key, now + 3000);
      continue;
    }
    for (const [key, x] of after) {
      const y = before.get(key);
      const params = { obs, prefix: x.net, from: esc(fromLabel(x.proto)), rov: x.rov, aspa: x.aspa };
      if (!y) { out.push([t("ev_route_new", params), "info", false]); changedRows.set(key, now + 3000); }
      else if (y.rov !== x.rov || y.aspa !== x.aspa) {
        const bad = x.rov === "Invalid" || x.aspa === "Invalid";
        out.push([t("ev_route_verdict", params), bad ? "bad" : "ok", false]); changedRows.set(key, now + 3000);
      } else if (!y.best && x.best) { out.push([t("ev_route_best", params), "info", false]); changedRows.set(key, now + 3000); }
    }
    for (const [key, y] of before) if (!after.has(key)) out.push([t("ev_route_gone", { obs, prefix: y.net, from: esc(fromLabel(y.proto)) }), "info", false]);
  }

  if (!out.length) return;
  for (const [text, kind] of out.slice().reverse()) addEvent(text, kind);
  paintEvents();
  if (changedRows.size) paintVerdicts(b);
  const important = out.filter(x => x[2]);
  const shown = (important.length ? important : out).slice(0, 2);
  for (const [text, kind] of shown) toast(text, kind);
  const rest = out.length - shown.length;
  if (rest > 0) toast(esc(t("ev_more", { n: rest })), "info", 4000);
}

document.querySelectorAll("#bottom-tabs button").forEach(b => b.onclick = () => {
  document.querySelectorAll("#bottom-tabs button").forEach(x => x.classList.toggle("active", x === b));
  $("bottom-verdicts").classList.toggle("hidden", b.dataset.bottom !== "verdicts");
  $("bottom-events").classList.toggle("hidden", b.dataset.bottom !== "events");
});

function paintLegend() {
  $("legend").innerHTML =
    `<span><span class="sw" style="border-color:var(--link-bgp)"></span>${esc(t("leg_bgp"))}</span>` +
    `<span><span class="sw" style="border-color:var(--link-rpki);border-top-style:dashed"></span>${esc(t("leg_rpki"))}</span>` +
    `<span><span class="sw" style="border-color:var(--ok)"></span>${esc(t("leg_good"))}</span>` +
    `<span><span class="sw" style="border-color:var(--warn)"></span>${esc(t("leg_warn"))}</span>` +
    `<span><span class="sw" style="border-color:var(--error)"></span>${esc(t("leg_bad"))}</span>`;
}

// ---------------------------------------------------------------- polling --
async function tick() {
  try {
    const r = await fetch("/api/status.json", { cache: "no-store" });
    paint(await r.json());
  } catch (e) {
    $("clock").textContent = t("no_collector_data");
  }
}

// ------------------------------------------------------------- static text --
function translateStatic() {
  document.querySelectorAll("[data-i18n]").forEach(el => el.textContent = t(el.dataset.i18n));
  document.querySelectorAll("[data-i18n-html]").forEach(el => el.innerHTML = t(el.dataset.i18nHtml));
  document.querySelectorAll("[data-i18n-title]").forEach(el => el.setAttribute("title", t(el.dataset.i18nTitle)));
  document.querySelectorAll("[data-i18n-aria]").forEach(el => el.setAttribute("aria-label", t(el.dataset.i18nAria)));
  $("svg-topology").setAttribute("aria-label", t("h1"));
  for (const id of ["origin", "provider-a", "provider-b", "observer1", "observer2", "attacker", "peer"]) {
    const key = id.replace("-", "_");
    $(`n-${id}-title`).textContent = t(`svg_title_${key}`);
    $(`n-${id}-role`).textContent = t(`svg_role_${key}`);
  }
  for (const id of ["krill", "routinator", "fort", "registry"]) $(`n-${id}-role`).textContent = t(`svg_role_${id}`);
  $("banner").innerHTML = t("banner_ip", { port: PANEL_PORT });
  $("banner").classList.toggle("show", !VHOST);
  document.querySelectorAll("#mode-switch button").forEach(b => b.classList.toggle("active", b.dataset.mode === guideMode()));
  document.querySelectorAll("#run-switch button").forEach(b => b.classList.toggle("active", b.dataset.run === runMode()));
  $("score").textContent = `⭐ ${totalScore()}`;
  paintTools(); paintLegend(); paintEvents(); paintThemeButton(); applyLayout();
}

function onLanguageChange() {
  translateStatic();
  renderPanel(selected);
  if (lastState) paint(lastState);
  loadGuide();
}

// ----------------------------------------------------------- guide options --
$("guide-opts").hidden = !SHOW_GUIDE_OPTS;
document.querySelectorAll("#mode-switch button").forEach(b => b.onclick = () => {
  PREF.set("mode", b.dataset.mode); translateStatic(); showStep(currentStep, true);
});
document.querySelectorAll("#run-switch button").forEach(b => b.onclick = () => {
  PREF.set("run", b.dataset.run); translateStatic(); showStep(currentStep, true);
});
$("guide-prev").onclick = () => showStep(currentStep - 1);
$("guide-next").onclick = () => showStep(currentStep + 1);
$("btn-guide-toggle").onclick = () => setGuideVisible(!layout.guide);

// ------------------------------------------------------------ theme, help --
function currentTheme() { return document.documentElement.dataset.theme === "dark" ? "dark" : "light"; }
function paintThemeButton() {
  const b = $("btn-theme");
  const light = currentTheme() === "light";
  b.textContent = light ? "☾" : "☀";
  b.title = b.ariaLabel = t(light ? "theme_to_dark" : "theme_to_light");
}
$("btn-theme").onclick = () => {
  const next = currentTheme() === "light" ? "dark" : "light";
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem("rpki-selflab-theme", next); } catch (_) {}
  paintThemeButton();
};

const anim = () => PREF.get("anim", "1") === "1";
function applyAnim() { document.body.classList.toggle("no-anim", !anim()); $("opt-anim").checked = anim(); }
$("opt-anim").onchange = e => { PREF.set("anim", e.target.checked ? "1" : "0"); applyAnim(); };
$("btn-help").onclick = () => $("help-dialog").showModal();
$("btn-help-close").onclick = () => $("help-dialog").close();
$("btn-reset-progress").onclick = () => {
  if (!confirm(t("help_reset_confirm"))) return;
  resetStore(); translateStatic(); showStep(currentStep, true);
};

document.addEventListener("keydown", e => {
  if (["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
  if ($("help-dialog").open) return;
  if (e.key === "Escape") { $("popover").classList.add("hidden"); closeDock(); }
  else if (e.key === "ArrowRight" && !e.altKey) showStep(currentStep + 1);
  else if (e.key === "ArrowLeft" && !e.altKey) showStep(currentStep - 1);
  else if (e.key === "g") setGuideVisible(!layout.guide);
  else if (e.key === "?") $("help-dialog").showModal();
});

// ------------------------------------------------------------------ start --
buildLanguageSwitcher($("language-switcher"));
applyAnim();
translateStatic();
renderWelcome();
loadGuide();
tick();
setInterval(tick, 5000);
