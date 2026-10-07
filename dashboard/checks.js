// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The rpki-selflab authors
// ============================================================================
// Checkpoints: what the lab's real state should look like at each point of
// the guide, tested live against /api/status.json.
//
// The guide places one with <!-- checkpoint: ID -->, and a challenge's
// "Check my lab" button uses the same ID (<!-- challenge check=ID ... -->).
// Each item's test returns true (pass), false (fail) or null (no data yet).
// "fix" is the step command that gets the lab there; the panel offers to run
// it. Items with manual: true are a checkbox the student ticks.
// ============================================================================

// A compact, normalized view of the state the tests below read from.
function labView(state) {
  const cfg = state.config || {};
  const v = {
    origin: String(cfg.ORIGIN_ASN || "64500"),
    a: String(cfg.PROVIDER_A_ASN || "64501"),
    b: String(cfg.PROVIDER_B_ASN || "64502"),
    atk: String(cfg.ATTACKER_ASN || "666"),
    peer: String(cfg.PEER_ASN || "64499"),
    v4: cfg.ORIGIN_V4 || "203.0.113.0/24",
    v6: cfg.ORIGIN_V6 || "3fff:cafe::/32",
    v4max: String(cfg.ORIGIN_V4_MAXLEN || "24"),
    v6max: String(cfg.ORIGIN_V6_MAXLEN || "32"),
    nodes: state.nodes || {},
    stage: state.stage || {},
    krill: state.krill || {},
    routinator: state.routinator || {},
    fort: state.fort || {},
    rpkiClient: ((state.nodes || {}).observer2 || {}).rpki || {},
  };
  const OBS = ["observer1", "observer2", "observer3"];
  const norm = p => String(p || "").replace(/_/g, "-");
  v.routes = obs => {
    const n = v.nodes[obs] || {};
    return [...(n.routes4 || []), ...(n.routes6 || [])];
  };
  v.hasData = obs => !!(v.nodes[obs] && v.nodes[obs].up && v.nodes[obs].routes4);
  // the route for the origin's IPv4 prefix received from "from" (provider-a,
  // provider-b, attacker)
  v.route = (obs, from) => v.routes(obs).find(r => r.net === v.v4 && norm(r.proto).startsWith(from));
  v.pathHas = (r, asn) => !!r && String(r.path).split(/\s+/).includes(asn);
  v.leaked = obs => v.routes(obs).find(r => r.net === v.v4 && norm(r.proto).startsWith("provider-a") && v.pathHas(r, v.peer));
  // true when fn holds on all three observers, null while one has no data
  v.all = fn => {
    if (!OBS.every(o => v.hasData(o))) return null;
    return OBS.every(o => !!fn(o));
  };
  v.stageIs = s => OBS.every(o => v.stage[o]) ? OBS.every(o => v.stage[o] === s) : null;
  v.atkPath = () => {
    const r = OBS.map(o => v.route(o, "attacker")).find(x => x);
    return r ? String(r.path).trim() : null;
  };
  v.aspaProviders = () => {
    const o = (v.krill.aspas || []).find(x => String(x.customer) === v.origin);
    return o ? o.providers.map(String).sort() : null;
  };
  v.hasRoa = (prefix, max) => (v.krill.roas || []).some(r => r.prefix === prefix && String(r.max_length) === max && String(r.asn) === v.origin);
  v.validatorsAspa = list => {
    const want = list.slice().sort().join(",");
    const r = (v.routinator.aspa_list || []).find(x => String(x.customer).replace(/^AS/, "") === v.origin);
    const f = (v.fort.aspa_list || []).find(x => String(x.customer).replace(/^AS/, "") === v.origin);
    const c = (v.rpkiClient.aspa_list || []).find(x => String(x.customer).replace(/^AS/, "") === v.origin);
    const got = x => x ? x.providers.map(p => String(p).replace(/^AS/, "")).sort().join(",") : "";
    if (v.routinator.vrps === undefined && v.fort.roas === undefined) return null;
    return got(r) === want && got(f) === want && got(c) === want;
  };
  return v;
}

const L = (en, es, pt) => ({ en, es, pt });

const CHECKS = {
  prep: [
    { label: L("Krill has exactly one CA", "Krill tiene exactamente una CA", "O Krill tem exatamente uma CA"),
      test: v => v.krill.up === undefined ? null : !!v.krill.ca },
    { label: L("The CA has a parent (the delegation, RFC 6492)", "La CA tiene un padre (la delegación, RFC 6492)", "A CA tem um pai (a delegação, RFC 6492)"),
      test: v => v.krill.ca ? (v.krill.parents || []).length > 0 : (v.krill.up === undefined ? null : false) },
    { label: L("The CA holds the lab's ASN and both prefixes", "La CA tiene el ASN y los dos prefijos del laboratorio", "A CA tem o ASN e os dois prefixos do laboratório"),
      test: v => { const r = v.krill.resources || {}; return v.krill.ca ? (r.asn === `AS${v.origin}` && r.ipv4 === v.v4 && r.ipv6 === v.v6) : (v.krill.up === undefined ? null : false); } },
  ],
  step1: [
    { label: L("All three observers in stage none (no validation)", "Los tres observadores en la etapa none (sin validación)", "Os três observadores no estágio none (sem validação)"),
      test: v => v.stageIs("none"), fix: "step1-clean" },
    { label: L("AS666 and the peer are silent", "AS666 y el peer están callados", "AS666 e o peer estão calados"),
      test: v => (v.nodes.attacker && v.nodes.peer) ? (!v.nodes.attacker.announcing && !v.nodes.peer.leaking) : null, fix: "step1-clean" },
    { label: L("All three observers see the prefix through Provider A and Provider B", "Los tres observadores ven el prefijo por el Proveedor A y por el Proveedor B", "Os três observadores veem o prefixo pelo Provedor A e pelo Provedor B"),
      test: v => v.all(o => v.route(o, "provider-a") && v.route(o, "provider-b")) },
    { label: L("No ROAs and no ASPA in Krill yet", "Todavía no hay ROAs ni ASPA en Krill", "Ainda não há ROAs nem ASPA no Krill"),
      test: v => v.krill.ca ? (!(v.krill.roas || []).length && !(v.krill.aspas || []).length) : null, fix: "clean-objects" },
  ],
  step2: [
    { label: L("AS666 is announcing the origin's prefixes", "AS666 está anunciando los prefijos del origen", "AS666 está anunciando os prefixos da origem"),
      test: v => v.nodes.attacker ? !!v.nodes.attacker.announcing : null, fix: "step2-hijack-simple" },
    { label: L("The hijack is the selected route on all three observers", "El secuestro es la ruta seleccionada en los tres observadores", "O sequestro é a rota selecionada nos três observadores"),
      test: v => v.all(o => { const r = v.route(o, "attacker"); return r && r.best; }) },
  ],
  "step3-roas": [
    { label: L("Krill has both ROAs (IPv4 and IPv6)", "Krill tiene las dos ROAs (IPv4 e IPv6)", "O Krill tem as duas ROAs (IPv4 e IPv6)"),
      test: v => v.krill.ca ? (v.hasRoa(v.v4, v.v4max) && v.hasRoa(v.v6, v.v6max)) : null },
    { label: L("The three validators see them: 2 VRP on Routinator, FORT and rpki-client", "Los tres validadores las ven: 2 VRP en Routinator, FORT y rpki-client", "Os três validadores as veem: 2 VRP no Routinator, no FORT e no rpki-client"),
      test: v => (v.routinator.vrps == null && v.fort.roas == null) ? null : (v.routinator.vrps >= 2 && v.fort.roas >= 2 && v.rpkiClient.vrps >= 2), fix: "refresh" },
  ],
  step3: [
    { label: L("All three observers in stage rov-mark", "Los tres observadores en la etapa rov-mark", "Os três observadores no estágio rov-mark"),
      test: v => v.stageIs("rov-mark"), fix: "step3-rov-mark" },
    { label: L("AS666's route is ROV Invalid on all three observers", "La ruta de AS666 es ROV Invalid en los tres observadores", "A rota do AS666 é ROV Invalid nos três observadores"),
      test: v => v.all(o => { const r = v.route(o, "attacker"); return r && r.rov === "Invalid"; }) },
    { label: L("Provider B's path is selected again", "El camino del Proveedor B vuelve a ser el seleccionado", "O caminho do Provedor B volta a ser o selecionado"),
      test: v => v.all(o => { const r = v.route(o, "provider-b"); return r && r.best; }) },
  ],
  step4: [
    { label: L("AS666 is forging the path (it ends in the origin)", "AS666 está falsificando el camino (termina en el origen)", "O AS666 está forjando o caminho (termina na origem)"),
      test: v => { const p = v.atkPath(); return p === null ? (v.hasData("observer1") ? false : null) : p === `${v.atk} ${v.origin}`; }, fix: "step4-hijack-posrov" },
    { label: L("ROV calls the forged route Valid on all three observers", "ROV considera Valid la ruta falsificada en los tres observadores", "O ROV chama a rota forjada de Valid nos três observadores"),
      test: v => v.all(o => { const r = v.route(o, "attacker"); return r && r.rov === "Valid"; }) },
  ],
  "step5-aspa": [
    { label: L("Krill's ASPA object lists Provider A only", "El objeto ASPA de Krill lista solo al Proveedor A", "O objeto ASPA do Krill lista só o Provedor A"),
      test: v => v.krill.ca ? JSON.stringify(v.aspaProviders()) === JSON.stringify([v.a]) : null },
    { label: L("The three validators have it (1 ASPA on Routinator, FORT and rpki-client)", "Los tres validadores lo tienen (1 ASPA en Routinator, FORT y rpki-client)", "Os três validadores o têm (1 ASPA no Routinator, no FORT e no rpki-client)"),
      test: v => v.validatorsAspa([v.a]), fix: "refresh" },
  ],
  step5: [
    { label: L("All three observers in stage aspa-mark (the header says “ROV: marking · ASPA: marking”)", "Los tres observadores en la etapa aspa-mark (el encabezado dice “ROV: marcando · ASPA: marcando”)", "Os três observadores no estágio aspa-mark (o cabeçalho diz “ROV: marcando · ASPA: marcando”)"),
      test: v => v.stageIs("aspa-mark"), fix: "step5-aspa-mark" },
    { label: L("The forged path is ASPA Invalid on all three observers", "El camino falsificado es ASPA Invalid en los tres observadores", "O caminho forjado é ASPA Invalid nos três observadores"),
      test: v => v.all(o => { const r = v.route(o, "attacker"); return r && r.aspa === "Invalid"; }) },
    { label: L("…and so is Provider B's path (the mistake the next step fixes)", "…y también el camino del Proveedor B (el error que corrige el próximo paso)", "…e o caminho do Provedor B também (o erro que o próximo passo corrige)"),
      test: v => v.all(o => { const r = v.route(o, "provider-b"); return r && r.aspa === "Invalid"; }) },
    { manual: true, id: "diff5", label: L("I ran the diffs and found the RTR version 2 and the upstream check", "Ejecuté los diff y encontré la versión 2 de RTR y la verificación upstream", "Rodei os diff e achei a versão 2 do RTR e a verificação upstream") },
  ],
  step6: [
    { label: L("Krill's ASPA object lists Providers A and B", "El objeto ASPA de Krill lista a los Proveedores A y B", "O objeto ASPA do Krill lista os Provedores A e B"),
      test: v => v.krill.ca ? JSON.stringify(v.aspaProviders()) === JSON.stringify([v.a, v.b].sort()) : null, fix: "step6-add-provider-b" },
    { label: L("The three validators have the new list", "Los tres validadores tienen la lista nueva", "Os três validadores têm a lista nova"),
      test: v => v.validatorsAspa([v.a, v.b]), fix: "refresh" },
    { label: L("Provider B's path is ASPA Valid and selected on all three observers", "El camino del Proveedor B es ASPA Valid y está seleccionado en los tres observadores", "O caminho do Provedor B é ASPA Valid e está selecionado nos três observadores"),
      test: v => v.all(o => { const r = v.route(o, "provider-b"); return r && r.aspa === "Valid" && r.best; }) },
  ],
  step7: [
    { label: L("The peer is leaking to Provider A", "El peer está filtrando hacia el Proveedor A", "O peer está vazando para o Provedor A"),
      test: v => v.nodes.peer ? !!v.nodes.peer.leaking : null, fix: "step7-leak-on" },
    { label: L("The leaked path reaches all three observers as ROV Valid, ASPA Invalid", "El camino filtrado llega a los tres observadores como ROV Valid, ASPA Invalid", "O caminho vazado chega aos três observadores como ROV Valid, ASPA Invalid"),
      test: v => v.all(o => { const r = v.leaked(o); return r && r.rov === "Valid" && r.aspa === "Invalid"; }) },
  ],
  step8: [
    { label: L("All three observers in stage aspa-drop", "Los tres observadores en la etapa aspa-drop", "Os três observadores no estágio aspa-drop"),
      test: v => v.stageIs("aspa-drop"), fix: "step8-drop" },
    { label: L("AS666's forged route is gone from all three tables", "La ruta falsificada de AS666 desapareció de las tres tablas", "A rota forjada do AS666 sumiu das três tabelas"),
      test: v => v.all(o => !v.route(o, "attacker")) },
    { label: L("The leaked path is gone too", "El camino filtrado también desapareció", "O caminho vazado também sumiu"),
      test: v => v.all(o => !v.leaked(o)) },
    { manual: true, id: "filtered8", label: L("I found the rejected routes with “show route … filtered” on observer1", "Encontré las rutas rechazadas con “show route … filtered” en observer1", "Achei as rotas rejeitadas com “show route … filtered” no observer1") },
  ],
  step9: [
    { label: L("The peer stopped leaking", "El peer dejó de filtrar", "O peer parou de vazar"),
      test: v => v.nodes.peer ? !v.nodes.peer.leaking : null, fix: "step9-leak-off" },
    { label: L("Provider A's own path is back on all three observers", "El camino propio del Proveedor A volvió a los tres observadores", "O caminho próprio do Provedor A voltou aos três observadores"),
      test: v => v.all(o => { const r = v.route(o, "provider-a"); return r && !v.pathHas(r, v.peer); }) },
  ],
};

// Evaluates a checkpoint: [{item, result}] plus a summary.
function runChecks(id, state, manualDone) {
  const items = CHECKS[id] || [];
  const v = state ? labView(state) : null;
  const results = items.map(item => {
    if (item.manual) return { item, result: !!(manualDone && manualDone[item.id]) };
    if (!v) return { item, result: null };
    let r = null;
    try { r = item.test(v); } catch (_) { r = null; }
    return { item, result: r };
  });
  return { results, pass: results.length > 0 && results.every(x => x.result === true) };
}

// Which step of the story the lab's state matches, or null. Used for the
// "lab ≈ Step N" chip in the header.
function inferStep(state) {
  if (!state || !state.stage) return null;
  const v = labView(state);
  const s1 = v.stage.observer1;
  if (!s1 || v.stage.observer2 !== s1 || v.stage.observer3 !== s1) return null;
  const atkOn = !!(v.nodes.attacker || {}).announcing;
  const leak = !!(v.nodes.peer || {}).leaking;
  const path = v.atkPath();
  const forged = path && path.split(/\s+/).length > 1;
  const aspa = v.aspaProviders();
  if (s1 === "none") return atkOn ? 2 : 1;
  if (s1 === "rov-mark") return forged ? 4 : 3;
  if (s1 === "aspa-mark") {
    if (leak) return 7;
    return aspa && aspa.length >= 2 ? 6 : 5;
  }
  if (s1 === "aspa-drop") return leak ? 8 : 9;
  return null;
}
