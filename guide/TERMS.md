# Translation terms

The reference for anyone editing the guide (`guide/templates/GUIDE.*.md`),
the panels (`dashboard/i18n.js`, `dashboard/nodes.js`, `rir-web/panel.html`)
or the scripts' messages (`scripts/i18n.sh`, `images/console/menu.sh`).

## Rules

1. **English is the source.** A change starts in `GUIDE.en.md` and then goes
   to `GUIDE.es.md` and `GUIDE.pt.md` in the same commit. Translations follow
   the English text's *structure* exactly (headings, code blocks, directives);
   the wording should read as if it had been written in that language.
2. **`./scripts/check-guide-parity.sh`** checks the structure (headings,
   code fences and their targets, the commands inside them, the challenge,
   predict and checkpoint directives, the `{{NAME}}` markers).
   `generate-config.sh` runs it on every `up`.
3. **Never translate:** protocol vocabulary (BGP, ROA, ROV, ASPA, RTR, RRDP,
   VRP, TAL, AS_PATH, local_pref, large community, RFC numbers), the verdict
   words (Valid, Invalid, NotFound, Unknown), commands and their output,
   file names, the stage names (`none`, `rov-mark`, `aspa-mark`,
   `aspa-drop`), and the labels of Krill's own interface (the guide uses its
   English UI, matching the screenshots in `guide/img/`).
4. **Address the reader** as *you* (en), *usted* (es) and *você* (pt).
5. **Keep sentences short.** Long chains held together by colons and
   semicolons are an English habit; split them.

## Interface terms

| English | Español | Português | Avoid |
|---|---|---|---|
| guide (the walkthrough) | guía | roteiro | en: "script" |
| step | paso | passo | |
| stage (deployment stage) | etapa | estágio | |
| stage indicator (the header badge) | indicador de etapa | indicador de estágio | pt: "selo"; es: "insignia" |
| status label (the text inside a topology box) | etiqueta / el recuadro dice... | status / a caixa mostra... | "pill", "pílula", "píldora", "insignia" |
| box (a component in the topology) | recuadro | caixa | |
| orange (accepted, but shouldn't be) | naranja | laranja | "amber", "ámbar", "âmbar" |
| red (flagged or dropped) | rojo | vermelho | |
| Tools bar | barra de Herramientas | barra de Ferramentas | |
| Lab terminal | Terminal del laboratorio | Terminal do laboratório | |
| Lab commands | Comandos del laboratorio | Comandos do laboratório | |
| Verdicts / Events | Veredictos / Eventos | Vereditos / Eventos | |
| Checkpoint | Punto de control | Ponto de controle | |
| Challenge / Guided (modes) | Desafío / Guiado | Desafio / Guiado | |
| hint | pista | dica | |
| Before you look | Antes de mirar | Antes de olhar | |
| Along the way (end-of-step recap) | Para recordar | Para guardar | es: "En el camino"; pt: "No caminho" |
| marking / dropping | marcando / descartando | marcando / descartando | |
| hijack | secuestro | sequestro | |
| route leak / leaking | fuga de ruta / filtrando | vazamento de rota / vazando | |
| forged path | camino falsificado | caminho forjado | |
| backup (path) | respaldo | backup | |
| holder | titular | titular | |
| parent (CA) | padre | pai | |
| registry | registro | registro | |
