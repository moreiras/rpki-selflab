// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The rpki-selflab authors
// ============================================================================
// The step-by-step guide: a small, dependency-free Markdown renderer (the
// lab has to work with no Internet access) plus the interactive pieces the
// guide's Markdown asks for. Everything below degrades to plain Markdown on
// GitHub, since the extensions are either fence info strings or HTML
// comments:
//
//   ```cmd @observer1       a command, run on that box (or @lab, @host, @krill...)
//   ```output @observer3    what the command prints
//   ```conf @observer1      a configuration excerpt
//   > [!IMPORTANT]          GitHub-style alerts (NOTE, TIP, IMPORTANT, WARNING, CAUTION)
//   <!-- checkpoint: ID -->                       live checklist (checks.js)
//   <!-- challenge id=X check=ID time=SEC: text -->  ... <!-- /challenge -->
//   <!-- hint: text -->                           inside a challenge
//   <!-- predict id=X answer=N: opt 1 | opt 2 -->  ... <!-- /predict -->
//
// The content comes straight from GUIDE.<lang>.md, served by nginx, so the
// printed guide and the on-screen one never drift apart.
// ============================================================================

let steps = [];
let currentStep = 0;
let glossary = [];

// --------------------------------------------------------------- settings --
const PREF = {
  get(key, fallback) { try { return localStorage.getItem("rpki-selflab-" + key) ?? fallback; } catch (_) { return fallback; } },
  set(key, value) { try { localStorage.setItem("rpki-selflab-" + key, value); } catch (_) {} },
};
// The Mode and "Commands in" switches are hidden for now; flip this to bring
// them back (index.html keeps their markup, app.js their handlers). While
// hidden, stored preferences are ignored so nobody gets stuck in a mode they
// can no longer switch out of.
const SHOW_GUIDE_OPTS = false;
const guideMode = () => SHOW_GUIDE_OPTS ? PREF.get("mode", "challenge") : "challenge";  // guided | challenge
const runMode = () => SHOW_GUIDE_OPTS ? PREF.get("run", "panel") : "panel";             // panel | host

// ---------------------------------------------------------- progress store --
// visited/done: per step index; challenges/predictions: per id; manual: the
// checkpoint items a student ticks by hand; badges: earned once.
const STORE_KEY = "rpki-selflab-progress";
function emptyStore() { return { visited: {}, done: {}, challenges: {}, predictions: {}, manual: {}, badges: {} }; }
let store = (() => {
  try { return Object.assign(emptyStore(), JSON.parse(localStorage.getItem(STORE_KEY) || "{}")); }
  catch (_) { return emptyStore(); }
})();
function saveStore() { try { localStorage.setItem(STORE_KEY, JSON.stringify(store)); } catch (_) {} }
function resetStore() { store = emptyStore(); saveStore(); }
function totalScore() {
  let s = 0;
  for (const c of Object.values(store.challenges)) s += c.points || 0;
  for (const p of Object.values(store.predictions)) s += p.points || 0;
  return s;
}

// --------------------------------------------------------------- renderer --
let codeBlocks = [];
let directives = [];

function md(text) {
  codeBlocks = [];
  directives = [];
  return restoreCode(blocks(extractDirectives(extractCode(text))));
}

// Takes the ``` blocks out of the way, leaving a marker at the same
// indentation, so they keep belonging to whichever list item they were in.
function extractCode(text) {
  const lines = text.split("\n");
  const output = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(\s*)```\s*(.*)$/);
    if (!m) { output.push(lines[i]); continue; }
    const indent = m[1];
    const body = [];
    i++;
    while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) body.push(lines[i++]);
    codeBlocks.push({ info: m[2].trim(), body: dedent(body).join("\n") });
    output.push(indent + "@@@BLOCK" + (codeBlocks.length - 1) + "@@@");
  }
  return output.join("\n");
}

// Turns <!-- ... --> lines into markers; anything that isn't one of the
// guide's directives is simply dropped (it's a comment, after all).
function extractDirectives(text) {
  return text.split("\n").map(line => {
    const m = line.match(/^(\s*)<!--\s*([\s\S]*?)\s*-->\s*$/);
    if (!m) return line;
    const d = parseDirective(m[2]);
    if (!d) return "";
    directives.push(d);
    return m[1] + "@@@DIR" + (directives.length - 1) + "@@@";
  }).join("\n");
}

function parseDirective(s) {
  let m = s.match(/^\/(challenge|predict)$/);
  if (m) return { type: "end-" + m[1] };
  m = s.match(/^checkpoint:\s*([\w-]+)$/);
  if (m) return { type: "checkpoint", id: m[1] };
  m = s.match(/^hint:\s*([\s\S]+)$/);
  if (m) return { type: "hint", text: m[1] };
  m = s.match(/^(challenge|predict)((?:\s+[\w-]+=[\w-]+)*)\s*:\s*([\s\S]+)$/);
  if (m) {
    const attrs = {};
    for (const a of m[2].trim().split(/\s+/).filter(Boolean)) {
      const [k, v] = a.split("=");
      attrs[k] = v;
    }
    return { type: m[1], attrs, text: m[3] };
  }
  return null;
}

function dedent(lines) {
  const indents = lines.filter(l => l.trim()).map(l => l.match(/^\s*/)[0].length);
  const min = indents.length ? Math.min(...indents) : 0;
  return lines.map(l => l.slice(min));
}

const ORDERED_ITEM = /^(\d+)\.\s+(.*)$/;
const BULLET_ITEM = /^[-*]\s+(.*)$/;
const DIR_LINE = /^@@@DIR(\d+)@@@$/;
const isListItem = l => ORDERED_ITEM.test(l) || BULLET_ITEM.test(l);
const ALERT_TYPES = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"];
const ALERT_ICON = { NOTE: "ℹ️", TIP: "💡", IMPORTANT: "❗", WARNING: "⚠️", CAUTION: "⛔" };

function blocks(text) {
  const lines = text.split("\n");
  const output = [];
  let i = 0;

  while (i < lines.length) {
    const raw = lines[i];
    const l = raw.trim();

    if (!l) { i++; continue; }

    const dm = l.match(DIR_LINE);
    if (dm) {
      const d = directives[+dm[1]];
      i++;
      if (d.type === "checkpoint") {
        output.push(`<div class="checkpoint" data-checkpoint="${esc(d.id)}"></div>`);
        continue;
      }
      if (d.type === "challenge" || d.type === "predict") {
        // collect everything up to the matching end marker
        const inner = [];
        const hints = [];
        while (i < lines.length) {
          const em = lines[i].trim().match(DIR_LINE);
          if (em && directives[+em[1]].type === "end-" + d.type) { i++; break; }
          if (em && directives[+em[1]].type === "hint") { hints.push(directives[+em[1]].text); i++; continue; }
          inner.push(lines[i]); i++;
        }
        const innerHtml = blocks(dedent(inner).join("\n"));
        output.push(d.type === "challenge" ? challengeHtml(d, hints, innerHtml) : predictHtml(d, innerHtml));
      }
      continue;   // stray end/hint markers are ignored
    }

    if (/^#{1,6}\s/.test(l)) {
      const n = l.match(/^#+/)[0].length;
      output.push(`<h${n}>${inline(l.slice(n).trim())}</h${n}>`);
      i++; continue;
    }

    if (/^-{3,}$/.test(l) || /^\*{3,}$/.test(l)) { output.push("<hr>"); i++; continue; }

    if (/^@@@BLOCK\d+@@@$/.test(l)) { output.push(l); i++; continue; }

    if (l.startsWith(">")) {
      const inner = [];
      while (i < lines.length && lines[i].trim().startsWith(">")) {
        inner.push(lines[i].trim().replace(/^>\s?/, ""));
        i++;
      }
      const am = (inner[0] || "").match(/^\[!(\w+)\]\s*$/);
      if (am && ALERT_TYPES.includes(am[1].toUpperCase())) {
        const type = am[1].toUpperCase();
        output.push(`<div class="alert ${type.toLowerCase()}"><div class="alert-title">${ALERT_ICON[type]} ${esc(t("alert_" + type.toLowerCase()))}</div>` +
                    blocks(inner.slice(1).join("\n")) + `</div>`);
      } else {
        const state = /^\*\*(State|Estado):\*\*/.test(inner[0] || "");
        output.push(`<blockquote${state ? ' class="state-box"' : ""}>` + blocks(inner.join("\n")) + "</blockquote>");
      }
      continue;
    }

    if (l.startsWith("|") && /^\|[\s:|-]+\|$/.test((lines[i + 1] || "").trim())) {
      const head = cells(l);
      i += 2;
      const body = [];
      while (i < lines.length && lines[i].trim().startsWith("|")) {
        body.push(cells(lines[i].trim())); i++;
      }
      output.push("<table><thead><tr>" + head.map(c => `<th>${inline(c)}</th>`).join("") +
                  "</tr></thead><tbody>" +
                  body.map(r => "<tr>" + r.map(c => `<td>${inline(c)}</td>`).join("") + "</tr>").join("") +
                  "</tbody></table>");
      continue;
    }

    if (isListItem(l) && !/^\s/.test(raw)) {
      // a list only ends at a non-blank, non-indented line that isn't an item
      const rawLines = [];
      while (i < lines.length) {
        const b = lines[i];
        if (!b.trim()) {
          const next = lines.slice(i + 1).find(x => x.trim());
          if (next === undefined) break;
          if (!/^\s/.test(next) && !isListItem(next.trim())) break;
          rawLines.push(""); i++; continue;
        }
        if (!/^\s/.test(b) && !isListItem(b.trim())) break;
        rawLines.push(b); i++;
      }
      output.push(listHtml(rawLines));
      continue;
    }

    // paragraph: joins lines up to a blank one or the start of another block
    const parts = [];
    while (i < lines.length) {
      const b = lines[i], s = b.trim();
      if (!s || /^#{1,6}\s/.test(s) || /^-{3,}$/.test(s) || s.startsWith(">") || DIR_LINE.test(s) ||
          s.startsWith("|") || /^@@@BLOCK\d+@@@$/.test(s) || isListItem(s)) break;
      parts.push(s); i++;
    }
    if (parts.length) output.push(`<p>${inline(parts.join(" "))}</p>`);
  }

  return output.join("\n");
}

function listHtml(rawLines) {
  const first = rawLines[0].trim();
  const ordered = ORDERED_ITEM.test(first);
  const start = ordered ? first.match(ORDERED_ITEM)[1] : null;

  // splits the items: a non-indented marker line starts a new item
  const items = [];
  for (const b of rawLines) {
    if (!/^\s/.test(b) && isListItem(b.trim())) {
      const m = b.trim().match(ORDERED_ITEM) || b.trim().match(BULLET_ITEM);
      items.push([m[2] !== undefined ? m[2] : m[1]]);
    } else if (items.length) {
      items[items.length - 1].push(b);
    }
  }

  const body = items.map(itemLines => {
    const [head, ...rest] = itemLines;
    const inner = (head + "\n" + dedent(rest).join("\n")).trim();
    let html = blocks(inner);
    // single-paragraph item: drop the <p> so the list stays compact
    const single = html.match(/^<p>([\s\S]*)<\/p>$/);
    if (single && !single[1].includes("<p>")) html = single[1];
    return `<li>${html}</li>`;
  }).join("\n");

  return ordered ? `<ol start="${start}">${body}</ol>` : `<ul>${body}</ul>`;
}

function cells(line) {
  return line.replace(/^\||\|$/g, "").split("|").map(c => c.trim());
}

function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener" class="img-link"><img src="$2" alt="$1" title="$1" loading="lazy"></a>')
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[\s(])\*([^*\n]+)\*/g, "$1<em>$2</em>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}

function esc(s) {
  return String(s ?? "").replace(/[&<>"]/g,
    c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

// ------------------------------------------------------------ code blocks --
const NODE_TARGETS = ["krill", "rir", "routinator", "fort", "origin", "provider-a", "provider-b",
                      "observer1", "observer2", "observer3", "attacker", "peer"];

// A command rewritten for the student's own terminal: docker exec into the
// box, through sh -c when the line needs a shell (pipes, &&, redirections).
function hostCommand(target, line) {
  if (!NODE_TARGETS.includes(target)) return line;
  if (/[|;<>`$]|&&/.test(line)) return `docker exec lab-${target} sh -c '${line.replace(/'/g, `'\\''`)}'`;
  return `docker exec lab-${target} ${line}`;
}

function restoreCode(html) {
  return html.replace(/(<p>)?@@@BLOCK(\d+)@@@(<\/p>)?/g, (_, a, n) => codeHtml(codeBlocks[+n]));
}

function codeHtml(block) {
  const [lang = "", ...rest] = block.info.split(/\s+/);
  const target = (rest.find(x => x.startsWith("@")) || "").slice(1);
  if (lang === "cmd") return cmdHtml(target || "lab", block.body);
  if (lang === "output") {
    const head = target ? t("output_on", { node: target }) : t("expected_output");
    const pre = `<pre>${esc(block.body)}</pre>`;
    if (guideMode() === "challenge")
      return `<div class="code-block output"><div class="cb-head"><span class="where">${esc(head)}</span></div>` +
             `<div class="reveal-out"><button class="btn small" data-reveal>${esc(t("show_output"))}</button></div>` +
             `<template>${pre}</template></div>`;
    return `<div class="code-block output"><div class="cb-head"><span class="where">${esc(head)}</span></div>${pre}</div>`;
  }
  if (lang === "conf") {
    const head = target ? t("config_of", { node: target }) : t("config_excerpt");
    return `<div class="code-block conf"><div class="cb-head"><span class="where">${esc(head)}</span></div><pre>${esc(block.body)}</pre></div>`;
  }
  return `<div class="code-block"><pre>${esc(block.body)}</pre></div>`;
}

function cmdHtml(target, body) {
  const host = runMode() === "host";
  const lines = body.split("\n");
  const commands = [];
  const shown = lines.map(line => {
    if (!line.trim()) return "";
    if (/^\s*#/.test(line)) return `<span class="cmd-comment">${esc(line)}</span>`;
    const cmd = host ? hostCommand(target, line) : line;
    commands.push(cmd);
    return `<span class="cmd-line">${esc(cmd)}</span>`;
  }).join("\n");

  let where;
  let canOpen = !host && target !== "host";
  if (target === "host") where = t("where_host");
  else if (target === "lab") where = host ? t("where_lab_host") : t("where_lab");
  else if (host) where = t("where_node_host", { node: esc(target) });
  else where = t("where_node", { node: esc(target), kind: t(target === "krill" || target === "rir" ? "kind_krill" : "kind_shell") });

  const cls = target === "host" ? "cmd host" : "cmd";
  return `<div class="code-block ${cls}" data-target="${esc(target)}">` +
         `<div class="cb-head"><span class="where">📍 ${where}</span>` +
         (canOpen ? `<button class="btn small" data-open-term="${esc(target)}">${esc(t("open_terminal"))}</button>` : "") +
         `<button class="btn small" data-copy="${esc(commands.join("\n"))}">${esc(t("copy"))}</button></div>` +
         `<pre>${shown}</pre></div>`;
}

// --------------------------------------------------------------- widgets --
function challengeHtml(d, hints, innerHtml) {
  const id = d.attrs.id || "c" + Math.abs(hashCode(d.text));
  return `<div class="challenge" data-cid="${esc(id)}" data-check="${esc(d.attrs.check || "")}" ` +
         `data-time="${esc(d.attrs.time || "")}" data-hints="${esc(JSON.stringify(hints))}">` +
         `<div class="w-head">🧩 ${esc(t("challenge"))}<span class="timer"></span></div>` +
         `<div class="w-body"><p>${inline(d.text)}</p><div class="lead"></div>` +
         `<div class="w-actions"></div><div class="hints"></div><div class="result"></div></div>` +
         `<div class="solution">${innerHtml}</div></div>`;
}

function predictHtml(d, innerHtml) {
  const id = d.attrs.id || "p" + Math.abs(hashCode(d.text));
  const options = d.text.split("|").map(s => s.trim()).filter(Boolean);
  return `<div class="predict" data-pid="${esc(id)}" data-answer="${esc(d.attrs.answer || "1")}">` +
         `<div class="w-head">🤔 ${esc(t("before_you_look"))}</div><div class="w-body">` +
         `<div class="options">${options.map((o, k) => `<button data-opt="${k + 1}">${inline(o)}</button>`).join("")}</div>` +
         `<div class="result"></div></div></div>` +
         `<div class="predict-rest" data-pid-rest="${esc(id)}">${innerHtml}</div>`;
}

function hashCode(s) { let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) | 0; return h; }

const fmtTime = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

function wireChallenge(el) {
  const id = el.dataset.cid;
  const check = el.dataset.check;
  const target = +el.dataset.time || 0;
  const hints = JSON.parse(el.dataset.hints || "[]");
  const challenge = guideMode() === "challenge";
  const rec = store.challenges[id] || (store.challenges[id] = { hints: 0, revealed: false, solved: false, points: 0 });
  const solution = el.querySelector(".solution");
  const actions = el.querySelector(".w-actions");
  const lead = el.querySelector(".lead");
  const result = el.querySelector(".result");
  const hintBox = el.querySelector(".hints");
  const timer = el.querySelector(".timer");

  if (rec.solved) el.classList.add("solved");
  if (!challenge) {
    lead.innerHTML = `<p class="result">${esc(t("challenge_guided"))}</p>`;
    if (rec.solved) result.innerHTML = esc(t("solved_already", { pts: rec.points }));
    return;
  }
  if (!rec.solved && !rec.start) { rec.start = Date.now(); saveStore(); }
  lead.innerHTML = `<p class="result">${esc(t("challenge_lead"))}</p>`;
  solution.hidden = !(rec.revealed || rec.solved);
  for (let k = 0; k < Math.min(rec.hints, hints.length); k++) hintBox.insertAdjacentHTML("beforeend", `<div class="hint-box">${inline(hints[k])}</div>`);

  const tickTimer = () => {
    if (rec.solved) { timer.textContent = rec.time ? fmtTime(rec.time) : ""; return; }
    const el2 = (Date.now() - rec.start) / 1000;
    timer.textContent = fmtTime(el2) + (target ? " · " + t("target_time", { t: fmtTime(target) }) : "");
  };
  tickTimer();
  el._tick = tickTimer;

  if (rec.solved) { result.innerHTML = `<span class="good">${esc(t("solved_already", { pts: rec.points }))}</span>`; return; }

  const solve = () => {
    const elapsed = (Date.now() - rec.start) / 1000;
    let pts = (check ? 100 : 60) + (target ? Math.max(0, Math.round(50 * (1 - elapsed / (2 * target)))) : 0) - 15 * rec.hints;
    pts = Math.max(10, pts);
    if (rec.revealed) pts = Math.min(pts, 10);
    Object.assign(rec, { solved: true, points: pts, time: elapsed });
    saveStore();
    el.classList.add("solved");
    solution.hidden = false;
    actions.innerHTML = "";
    result.className = "result good";
    result.textContent = t("solved", { pts });
    timer.textContent = fmtTime(elapsed);
    onScoreChange(pts);
    maybeBadges();
  };

  if (hints.length) {
    const hb = document.createElement("button");
    hb.className = "btn small";
    const label = () => hints.length > 1 ? t("hint_n", { n: Math.min(rec.hints + 1, hints.length), total: hints.length }) : t("hint");
    hb.textContent = label();
    hb.disabled = rec.hints >= hints.length;
    hb.onclick = () => {
      if (rec.hints >= hints.length) return;
      hintBox.insertAdjacentHTML("beforeend", `<div class="hint-box">${inline(hints[rec.hints])}</div>`);
      rec.hints++; saveStore();
      hb.textContent = label();
      hb.disabled = rec.hints >= hints.length;
    };
    actions.appendChild(hb);
  }
  const cb = document.createElement("button");
  cb.className = "btn small pri";
  cb.textContent = check ? t("check") : t("done_self");
  cb.onclick = () => {
    if (!check) return solve();
    const r = runChecks(check, lastState, store.manual);
    if (r.pass) return solve();
    const missing = r.results.filter(x => x.result !== true).map(x => x.item.label[currentLanguage()] || x.item.label.en);
    result.className = "result bad";
    result.textContent = t("not_yet", { missing: missing.join("; ") });
  };
  actions.appendChild(cb);
  if (!rec.revealed) {
    const sb = document.createElement("button");
    sb.className = "btn small";
    sb.textContent = t("show_solution");
    sb.onclick = () => { rec.revealed = true; saveStore(); solution.hidden = false; sb.remove(); };
    actions.appendChild(sb);
  }
}

function wirePredict(el) {
  const id = el.dataset.pid;
  const answer = +el.dataset.answer;
  const rest = document.querySelector(`[data-pid-rest="${CSS.escape(id)}"]`);
  const result = el.querySelector(".result");
  const buttons = [...el.querySelectorAll("[data-opt]")];
  const challenge = guideMode() === "challenge";
  const rec = store.predictions[id];

  const show = (choice, fresh) => {
    buttons.forEach(b => {
      b.disabled = true;
      if (+b.dataset.opt === answer) b.classList.add("right");
      else if (+b.dataset.opt === choice) b.classList.add("wrong");
    });
    const right = choice === answer;
    const pts = (store.predictions[id] || {}).points || 0;
    result.className = "result " + (right ? "good" : "bad");
    result.textContent = right ? (pts ? t("predict_right", { pts }) : t("predict_right0")) : t("predict_wrong");
    if (rest) rest.classList.remove("locked");
    if (fresh && pts) onScoreChange(pts);
  };

  if (rec) { show(rec.choice, false); return; }
  if (challenge && rest) {
    rest.classList.add("locked");
    result.textContent = t("predict_locked");
  }
  buttons.forEach(b => b.onclick = () => {
    const choice = +b.dataset.opt;
    store.predictions[id] = { choice, points: challenge && choice === answer ? 20 : 0 };
    saveStore();
    show(choice, true);
  });
}

// Re-evaluated on every state tick, so items turn green as the lab gets there.
function updateCheckpoints() {
  document.querySelectorAll("#guide-body .checkpoint").forEach(el => {
    const id = el.dataset.checkpoint;
    const { results, pass } = runChecks(id, lastState, store.manual);
    const language = currentLanguage();
    const items = results.map(({ item, result }) => {
      const label = esc(item.label[language] || item.label.en);
      if (item.manual) {
        return `<li class="manual ${result ? "pass" : ""}"><input type="checkbox" data-manual="${esc(item.id)}" ${result ? "checked" : ""} aria-label="${label}"><span>${label}</span></li>`;
      }
      const cls = result === true ? "pass" : result === false ? "fail" : "wait";
      const mark = result === true ? "✓" : result === false ? "✕" : "…";
      const fix = result === false && item.fix
        ? ` <button class="btn small" data-run="${esc(item.fix)}">▶ ./scripts/lab.sh ${esc(item.fix)}</button>` : "";
      return `<li class="${cls}"><span class="mark">${mark}</span><span>${label}${fix}</span></li>`;
    }).join("");
    const html = `<div class="w-head">✅ ${esc(t("checkpoint"))}<span class="timer">${esc(lastState ? t("cp_live") : t("cp_waiting"))}</span></div>` +
                 `<div class="w-body"><ul>${items}</ul>${pass ? `<p class="result good">${esc(t("cp_all_pass"))}</p>` : ""}</div>`;
    if (el._html !== html) {
      el.innerHTML = html;
      el._html = html;
      el.classList.toggle("all-pass", pass);
      el.querySelectorAll("[data-manual]").forEach(cb => cb.onchange = () => {
        store.manual[cb.dataset.manual] = cb.checked; saveStore(); updateCheckpoints();
      });
      el.querySelectorAll("[data-run]").forEach(b => b.onclick = () => runLabCommand(b.dataset.run));
    }
    if (pass && !store.done[currentStep]) {
      store.done[currentStep] = true; saveStore(); paintProgress(); maybeBadges(id);
    }
  });
}

const BADGES = { step3: "badge_rov", step5: "badge_aspa", step7: "badge_leak", step8: "badge_drop" };
function maybeBadges(checkpointId) {
  const award = key => {
    if (store.badges[key]) return;
    store.badges[key] = Date.now(); saveStore();
    toast(t("badge_earned", { name: t(key) }), "gold");
  };
  if (checkpointId && BADGES[checkpointId]) award(BADGES[checkpointId]);
  const all = Object.values(store.challenges);
  if (all.length >= 3 && all.every(c => c.solved && !c.revealed)) award("badge_clean");
}

function onScoreChange() {
  const el = document.getElementById("score");
  if (!el) return;
  el.textContent = `⭐ ${totalScore()}`;
  el.classList.remove("bump"); void el.offsetWidth; el.classList.add("bump");
}

// --------------------------------------------------------------- glossary --
// Built from the guide's own Glossary table, so the tooltips always say
// exactly what the guide says, in the guide's language.
function buildGlossary(text) {
  glossary = [];
  const sec = text.split(/^## /m).find(p => /^(Glossary|Glosario|Glossário)\b/.test(p));
  if (!sec) return;
  for (const line of sec.split("\n")) {
    const m = line.match(/^\|\s*\*\*([^*]+)\*\*\s*\|\s*(.+?)\s*\|\s*$/);
    if (!m) continue;
    const def = m[2].replace(/\*\*|`|\*/g, "");
    const names = new Set([m[1]]);
    const paren = m[1].match(/^(.+?)\s*\((.+)\)$/);
    if (paren) { names.add(paren[1]); names.add(paren[2]); }
    for (const n of [...names]) if (n.includes("/")) n.split("/").forEach(x => names.add(x.trim()));
    for (const n of names) if (n.length > 1) glossary.push({ term: n, def: `${m[1]}: ${def}` });
  }
  glossary.sort((a, b) => b.term.length - a.term.length);
}

function applyGlossary(root) {
  if (!glossary.length || /^(Glossary|Glosario|Glossário)/.test(steps[currentStep].title)) return;
  const used = new Set();
  const skip = node => node.closest("pre, code, a, h1, h2, h3, h4, th, abbr, button, .w-head, .cb-head, .alert-title, table");
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const texts = [];
  while (walker.nextNode()) texts.push(walker.currentNode);
  for (const g of glossary) {
    if (used.has(g.def)) continue;
    const caseSensitive = /[A-Z].*[A-Z]/.test(g.term);
    const re = new RegExp(`(?<![\\p{L}\\d_/-])${g.term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![\\p{L}\\d_-])`, caseSensitive ? "u" : "iu");
    for (const node of texts) {
      if (!node.parentNode || skip(node.parentNode)) continue;
      const m = node.nodeValue.match(re);
      if (!m) continue;
      const after = node.splitText(m.index);
      after.nodeValue = after.nodeValue.slice(m[0].length);
      const abbr = document.createElement("abbr");
      abbr.className = "gloss";
      abbr.title = g.def;
      abbr.textContent = m[0];
      node.parentNode.insertBefore(abbr, after);
      texts.push(after);
      used.add(g.def);
      break;
    }
  }
}

// ------------------------------------------------------------ navigation --
function paintProgress() {
  const bar = document.getElementById("guide-progress");
  if (!bar) return;
  bar.innerHTML = steps.map((s, k) =>
    `<span class="${store.done[k] ? "done" : store.visited[k] ? "visited" : ""}${k === currentStep ? " current" : ""}" title="${esc(s.title)}" data-step="${k}"></span>`).join("");
  bar.querySelectorAll("[data-step]").forEach(s => s.onclick = () => showStep(+s.dataset.step));
}

function showStep(n, keepScroll) {
  if (!steps.length) return;
  currentStep = Math.max(0, Math.min(n, steps.length - 1));
  const body = document.getElementById("guide-body");
  const scroll = body.scrollTop;
  body.innerHTML = md(steps[currentStep].text);
  body.scrollTop = keepScroll ? scroll : 0;
  document.getElementById("guide-select").value = String(currentStep);
  document.getElementById("guide-counter").textContent = `${currentStep + 1} / ${steps.length}`;
  document.getElementById("guide-prev").disabled = currentStep === 0;
  document.getElementById("guide-next").disabled = currentStep === steps.length - 1;

  body.querySelectorAll("[data-copy]").forEach(b => b.onclick = () => {
    const text = b.dataset.copy;
    const done = () => { b.textContent = t("copied"); setTimeout(() => (b.textContent = t("copy")), 1300); };
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, () => fallbackCopy(text, done));
    else fallbackCopy(text, done);
  });
  body.querySelectorAll("[data-open-term]").forEach(b => b.onclick = () => openTerminalFor(b.dataset.openTerm));
  body.querySelectorAll("[data-reveal]").forEach(b => b.onclick = () => {
    const box = b.closest(".code-block");
    box.querySelector(".reveal-out").replaceWith(box.querySelector("template").content.cloneNode(true));
  });
  body.querySelectorAll(".challenge").forEach(wireChallenge);
  body.querySelectorAll(".predict").forEach(wirePredict);
  updateCheckpoints();
  applyGlossary(body);

  store.visited[currentStep] = true; saveStore();
  paintProgress();
  PREF.set("step", String(currentStep));
}

// navigator.clipboard needs a secure context; http://<ip>:8080 isn't one
function fallbackCopy(text, done) {
  const ta = document.createElement("textarea");
  ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
  document.body.appendChild(ta); ta.select();
  try { document.execCommand("copy"); done(); } catch (_) {}
  ta.remove();
}

// "Step 5" / "Paso 5" / "Passo 5" -> index in steps
function stepIndexFor(number) {
  return steps.findIndex(s => new RegExp(`^(Step|Paso|Passo) ${number}\\b`).test(s.title));
}

async function loadGuide() {
  const language = currentLanguage();
  const file = `GUIDE.${language}.md`;
  let text;
  try {
    const r = await fetch(file, { cache: "no-store" });
    if (!r.ok) throw new Error(r.status);
    text = await r.text();
  } catch (_) {
    document.getElementById("guide-body").innerHTML = `<p>${t("guide_error", { file })}</p>`;
    return;
  }
  buildGlossary(text);

  // each "## " starts a step; whatever comes before the first one is the intro
  const parts = text.split(/^## /m);
  steps = [{ title: t("overview"), text: parts[0].trim() }];
  for (const p of parts.slice(1)) steps.push({ title: p.split("\n")[0].trim(), text: "## " + p.trim() });

  const selectEl = document.getElementById("guide-select");
  selectEl.innerHTML = steps.map((e, k) => `<option value="${k}">${k + 1}. ${esc(e.title)}</option>`).join("");
  selectEl.onchange = () => showStep(+selectEl.value);
  showStep(Math.min(+PREF.get("step", 0) || 0, steps.length - 1));
  // the header's "lab ≈ Step N" names a step by its title, in this language
  if (typeof paintStepChip === "function" && lastState) paintStepChip(lastState);
}

// ticks the visible challenge timers once a second
setInterval(() => document.querySelectorAll("#guide-body .challenge").forEach(el => el._tick && el._tick()), 1000);
