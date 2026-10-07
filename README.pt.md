# RPKI SelfLab

*Laboratório autônomo e guia de autoestudo para RPKI, ROA, ROV e ASPA*

*[English](README.md) · [Español](README.es.md) · [Português](README.pt.md)*

**Site do projeto, com a história do laboratório ilustrada passo a passo:
https://moreiras.github.io/rpki-selflab/pt/**

Laboratório de RPKI (ROA, ROV e ASPA) em contêineres. Roda em qualquer
computador com Docker (Mac, Windows ou Linux, testado com OrbStack e Docker
Desktop). Ele publica ROAs e um objeto ASPA, e depois mostra o que **três
validadores diferentes, combinados com dois roteadores diferentes,** fazem com
exatamente os mesmos objetos, enquanto um sequestrador (AS666) e um peer que vaza rotas
tentam atrapalhar. O guia é uma história só: três ataques, e qual verificação
barra cada um.

O guia está em **[guide/GUIDE.en.md](guide/GUIDE.en.md)** (também em
[espanhol](guide/GUIDE.es.md) e [português](guide/GUIDE.pt.md)). No painel web,
o mesmo conteúdo aparece passo a passo ao lado da topologia ao vivo, no idioma
selecionado ali, e cada bloco de comandos diz onde roda, com um botão que abre
o terminal certo.

**Como usar.** O painel controla um laboratório completo, e seguir o roteiro é
o caminho recomendado: cada passo prepara o seguinte, e os pontos de controle
se marcam sozinhos quando o laboratório chega lá. Alguns passos são desafios,
com a solução escondida atrás de dicas e de um cronômetro. Depois de terminar,
use o laboratório como quiser: a última seção do roteiro tem ideias em aberto,
a pasta `work/` guarda as suas próprias configurações, e qualquer comando de
passo põe o laboratório de volta nos trilhos.

## Início rápido

1. **Instale o Docker** com o Compose v2 (o que instalar em cada sistema está
   em [Antes de começar: o Docker](#antes-de-começar-o-docker)). No Windows,
   faça tudo dentro do terminal do Ubuntu do WSL 2.
2. **Baixe o laboratório.** Clone o repositório:

   ```sh
   git clone https://github.com/moreiras/rpki-selflab.git
   cd rpki-selflab
   ```

   ou baixe o código-fonte (`.zip` ou `.tar.gz`) da versão mais recente em
   [Releases](https://github.com/moreiras/rpki-selflab/releases) e descompacte.
3. **Suba o laboratório**, dentro da pasta dele:

   ```sh
   ./scripts/lab.sh up
   ```

   Depois abra **http://localhost:8080** no navegador e siga o roteiro na
   coluna da esquerda do painel.

O primeiro `up` baixa e constrói as imagens, o que leva alguns minutos.
Prefere não instalar o Docker? Também há uma máquina virtual pronta: veja
[Como máquina virtual](#como-máquina-virtual).

## Modos local e beta

O laboratório tem dois modos, escolhidos com a variável `MODE` no `lab.conf`:

| MODE | Quem certifica os recursos | Internet |
|---|---|---|
| `local` (padrão) | **LabNIC**, um RIR/NIR simulado que roda dentro do laboratório | não precisa |
| `beta` | o sistema de testes do Registro.br | precisa, além de um login em beta.registro.br |

No modo local o laboratório é **autocontido**: tem a sua própria âncora de
confiança, o seu próprio repositório, e um painel de registro onde acontecem a
delegação da CA e a autorização de publicação, com as mesmas trocas de XML das
RFC 6492 e 8183.

Os dois modos usam o modelo **delegado** do RPKI: você roda a sua própria CA
(o Krill), o registro a certifica, e os objetos são publicados no
repositório do registro. O Registro.br oferece apenas esse modelo, e oferece
também o serviço de publicação, e por isso é esse o arranjo que o
laboratório ensina. O modelo hospedado, em que o
registro opera a CA por você, não é coberto; ROAs, ROV e ASPA funcionam do
mesmo jeito nos dois.

O modo `beta` foi criado só para alguns cursos do NIC.br. O modo `local`, em
que o laboratório é autocontido, é o padrão e quase certamente o que você
deve usar.

## Antes de começar: o Docker

Você precisa do Docker com o Compose v2, de um computador de 64 bits (amd64
ou arm64), de cerca de 2 GB de memória para o Docker e de 4 GB livres em
disco. Depois de no ar, o laboratório usa por volta de 300 MB de memória.

| Sistema | O que instalar |
|---|---|
| Linux | Docker Engine + o plugin do Compose: https://docs.docker.com/engine/install/ (depois https://docs.docker.com/engine/install/linux-postinstall/ para usá-lo sem `sudo`) |
| macOS | OrbStack (https://docs.orbstack.dev/quick-start, com o qual o laboratório é testado) ou Docker Desktop (https://docs.docker.com/desktop/setup/install/mac-install/) |
| Windows | WSL 2 (`wsl --install`, https://learn.microsoft.com/windows/wsl/install) mais o Docker Desktop com a integração WSL (https://docs.docker.com/desktop/features/wsl/). Clone e rode o laboratório **dentro** do terminal do Ubuntu, numa pasta do Linux como `~/rpki-selflab`, e não em `/mnt/c` |

Confira com `docker version`, `docker compose version` e
`docker run --rm hello-world`. A *Preparação 1* do roteiro explica tudo isso
com mais detalhes.

## Serviços e portas

Se algo der errado, `./scripts/lab.sh doctor` confere o Docker, as portas, os
contêineres e a preparação, e diz o que fazer a respeito de cada problema.

| Serviço | URL | Observação |
|---|---|---|
| Painel do laboratório | http://localhost:8080 | topologia clicável |
| Krill (CA) | http://krill.localhost:8080 | token `labpass` |
| Routinator | http://routinator.localhost:8080 | validador do observer1 |
| Console (ttyd) | http://console.localhost:8080 | terminal no navegador |
| Painel do registro | http://registry.localhost:8080 | só no `MODE=local` |
| Krill do LabNIC | http://rir-krill.localhost:8080 | só no `MODE=local`, token `labpass` |

Tudo passa por uma porta só, a 8080: o painel fica em `localhost`, e cada um
dos outros aplicativos web no seu próprio `<nome>.localhost` (os navegadores
resolvem `*.localhost` para a sua máquina, e o nginx roteia pelo nome). No
painel, a barra no alto abre todos eles, e os terminais, dentro do
próprio painel, em abas. Abra-o em exatamente `localhost`: pelo endereço IP,
esses nomes não resolvem.

Só a 8080 é publicada no seu computador, então o laboratório não briga com
outros programas. Se a 8080 já estiver ocupada, escolha outra porta em
`PANEL_PORT` no `lab.conf` e rode `./scripts/lab.sh up`; todos os endereços
acima passam a usar essa porta. `EXPOSE_PORTS=yes` no `lab.conf` publica também
a porta própria de cada serviço (Krill 3000, Krill do LabNIC 3001, Routinator
3323/8323, FORT 3324, ttyd 7681, registro 8081; veja
`docker-compose.ports.yml`), para ligar ferramentas de fora direto a um
serviço.

## Como máquina virtual

Se preferir não instalar o Docker, o laboratório também vem como uma pequena
máquina virtual, com área de trabalho própria (navegador e terminal), já com
tudo dentro, imagens inclusive. Não há nada a configurar, e roda sem acesso à
Internet. Veja [vm/README.pt.md](vm/README.pt.md).

## Topologia

![A topologia do laboratório: o registro no alto; o Routinator e o FORT acima do observer1 e do observer3; entre eles, o observer2, que valida no próprio host; os dois provedores e o AS666; e, embaixo, a origem, a sua CA e o peer](guide/img/topology.pt.svg)

O AS64500 é multihomed e anuncia `203.0.113.0/24` e `3fff:cafe::/32`. Cada
observador recebe o mesmo prefixo pelos dois provedores. A origem prefere o
Provedor B: repete o próprio ASN duas vezes (prepend) ao anunciar para o
Provedor A, o backup, então o caminho por A fica dois saltos mais longo. Mais
dois roteadores entram na topologia, desenhados com borda tracejada, e ficam
calados até a história do guia ligá-los:

- **AS666** sequestra os prefixos da origem: primeiro anunciando-os como seus
  (`step2-hijack-simple`), depois forjando o AS_PATH para terminar na origem
  verdadeira (`step4-hijack-posrov`).
- **peer** é uma rede legítima, com peering privado com a origem, que também
  compra trânsito do Provedor A. Quando o guia manda (`step7-leak-on`), ela
  vaza as rotas da origem para o Provedor A: um vazamento de rota, que o ROV
  não tem como enxergar e o ASPA pega.

| Rede Docker | IPv4 | IPv6 | entre |
|---|---|---|---|
| `lab-l-org-a` | 10.200.1.0/24 | fd00:1::/64 | origem ↔ Provedor A |
| `lab-l-org-b` | 10.200.2.0/24 | fd00:2::/64 | origem ↔ Provedor B |
| `lab-l-a-obs1` | 10.200.3.0/24 | fd00:3::/64 | Provedor A ↔ observer1 |
| `lab-l-b-obs1` | 10.200.4.0/24 | fd00:4::/64 | Provedor B ↔ observer1 |
| `lab-l-a-obs3` | 10.200.5.0/24 | fd00:5::/64 | Provedor A ↔ observer3 |
| `lab-l-b-obs3` | 10.200.6.0/24 | fd00:6::/64 | Provedor B ↔ observer3 |
| `lab-l-666-obs1` | 10.200.7.0/24 | fd00:7::/64 | AS666 ↔ observer1 |
| `lab-l-666-obs3` | 10.200.8.0/24 | fd00:8::/64 | AS666 ↔ observer3 |
| `lab-l-a-obs2` | 10.200.11.0/24 | fd00:11::/64 | Provedor A ↔ observer2 |
| `lab-l-b-obs2` | 10.200.12.0/24 | fd00:12::/64 | Provedor B ↔ observer2 |
| `lab-l-666-obs2` | 10.200.13.0/24 | fd00:13::/64 | AS666 ↔ observer2 |
| `lab-l-peer-org` | 10.200.9.0/24 | fd00:9::/64 | peer ↔ origem (peering privado) |
| `lab-l-peer-a` | 10.200.10.0/24 | fd00:10::/64 | peer ↔ Provedor A (trânsito) |
| `lab-mgmt` | 172.30.0.0/24 | fd00:30::/64 | Krill, validadores, observadores, painel |

## Os observadores

Os três observadores recebem os mesmos anúncios e objetos RPKI, mas cada um
combina um roteador e um validador do seu jeito:

| | observer1 | observer2 | observer3 |
|---|---|---|---|
| Roteador | BIRD 3.1.4 | OpenBGPD 8.8 | OpenBGPD 8.8 |
| Validador | Routinator | rpki-client 9.5, no mesmo host | FORT Validator |
| Como o roteador recebe os dados | RTR | um arquivo que ele inclui (`include`), reescrito pelo rpki-client | RTR |
| ASN | 64509 | 64510 | 64511 |
| Como se lê o veredito | large communities definidas pelos filtros do laboratório | atributos nativos `ovs` / `avs` da rota | atributos nativos `ovs` / `avs` da rota |
| Inspecionar com | `birdc show route table master4 all` | `bgpctl show rib detail` | `bgpctl show rib detail` |

O BIRD não tem atributo de validação por rota, então os arquivos
`bird/observer1-*.conf` gravam cada veredito numa large community:
`(64509,1,x)` para ROV, `(64509,2,x)` para ASPA. O OpenBGPD calcula os dois
nativamente, e o `bgpctl -j` entrega tudo em JSON. É por isso que as
configurações parecem tão diferentes testando exatamente a mesma coisa.

### observer2: validador e roteador no mesmo host

O observer2 segue o modelo do OpenBSD. O rpki-client roda dentro do contêiner
do roteador, valida o repositório e grava o `/var/db/rpki-client/openbgpd`
(um `roa-set` e um `aspa-set`), que o `openbgpd/observer2-<stage>.conf`
inclui. Em produção, uma tarefa do cron, tipicamente de hora em hora, roda o
rpki-client de novo e recarrega o bgpd; aqui o `rpki-refresh` faz isso a cada
`RPKI_CLIENT_INTERVAL` segundos (120, no `docker-compose.yml`) e em cada
comando de passo, e o entrypoint do contêiner o roda uma vez antes de o bgpd
subir. Não há sessão RTR, então não há versão de protocolo para negociar: o
`aspa-set` vem junto com o arquivo.

O exercício extra E do guia serve a mesma saída do rpki-client pelo RTR, com
o RTRTR no próprio observer2 (`rpki-rtr start`), que é como o rpki-client
alimenta roteadores que só falam RTR.

### Por que o observer2 e o observer3 usam `role provider`

O OpenBGPD só roda a verificação ASPA numa sessão que tenha um papel (role) da
RFC 9234, e **é o papel que decide qual algoritmo ASPA roda**. Os
observadores ficam acima dos provedores (os anúncios sobem a partir da
origem), então cada observador é o upstream dos provedores, e as rotas chegam
de um cliente. Isso seleciona o algoritmo *upstream*, o mesmo que os
`bird/observer1-*.conf` pedem com `aspa_check_upstream()`.

Troque para `role customer` e o algoritmo *downstream* entra em ação: o
caminho pelo Provedor B volta como **Valid**. Mesmos objetos, mesmo AS_PATH,
veredito diferente. É provavelmente a coisa mais surpreendente deste
laboratório, e não é bug de nenhuma das duas implementações.

Uma consequência prática disso: trocar de estágio no observer2 e no observer3
os reinicia. O papel é negociado na abertura da sessão, e no observer3 uma
sessão RTR já estabelecida mantém a versão que negociou; depois de um `bgpctl reload`
puro, todo `avs` volta para `unknown`. Os comandos `step*` que trocam de
estágio já cuidam do reinício para você (o nome do estágio fica guardado em
`/etc/lab-stage` dentro do contêiner, então um reinício posterior volta no
mesmo estágio).

### Estágios de implantação

Os observadores não sobem validando nada. Começam como roteadores BGP comuns,
e o guia implanta a validação neles por estágios, do jeito que você faria num
roteador real: primeiro *marcando* o que uma verificação sinaliza (uma
community e uma preferência menor, nada é descartado), depois *descartando*.
Cada estágio é um arquivo de configuração completo por observador:

| Estágio | observer1 (BIRD) | observer2, observer3 (OpenBGPD) | O que faz |
|---|---|---|---|
| `none` | `observer1-none.conf` | `observer2-none.conf`, `observer3-none.conf` | BGP comum, sem validação (como o laboratório começa) |
| `rov-mark` | `observer1-rov-mark.conf` | `observer2-rov-mark.conf`, `observer3-rov-mark.conf` | dados validados (RTR ou arquivo) + ROV, rotas inválidas apenas marcadas |
| `rov-drop` | `observer1-rov-drop.conf` | `observer2-rov-drop.conf`, `observer3-rov-drop.conf` | rotas ROV Invalid rejeitadas |
| `aspa-mark` | `observer1-aspa-mark.conf` | `observer2-aspa-mark.conf`, `observer3-aspa-mark.conf` | ROV e verificação ASPA, os dois apenas marcando |
| `aspa-drop` | `observer1-aspa-drop.conf` | `observer2-aspa-drop.conf`, `observer3-aspa-drop.conf` | ROV e ASPA Invalid ambos rejeitados |

O ponto é justamente ler um arquivo depois do outro: o que muda entre dois
estágios é o que significa implantar aquela verificação. O indicador de
estágio no cabeçalho do painel mostra o estágio em que os observadores estão.

## Os comandos da história

O `./scripts/lab.sh` alterna o AS666 e o peer entre comportamentos. Os nomes
levam o número do passo do guia a que pertencem. Cada um define o estado
*inteiro* do seu passo (atacante, peer, ROAs, objeto ASPA e o estágio dos
observadores), não só o que mudou em relação ao passo anterior; por isso são
seguros de rodar em qualquer ordem, a partir de qualquer ponto da história. A
partir do `step3-rov-mark`, cada comando também confere se a Preparação (a CA
do Krill, o parent dela, os recursos) realmente terminou antes de mexer em
qualquer coisa, e avisa o que está faltando quando não terminou.

| Comando | O que faz |
|---|---|
| `step1-clean` | AS666 e peer em silêncio, e os três observadores de volta ao BGP comum (sem validação) |
| `step2-hijack-simple` | o AS666 anuncia os prefixos da origem como seus |
| `step3-rov-mark` | implanta o ROV nos três observadores, apenas marcando |
| `step4-hijack-posrov` | o AS666 forja o caminho para que termine na origem verdadeira |
| `step5-aspa-mark` | implanta também a verificação ASPA, também apenas marcando |
| `step6-add-provider-b` | acrescenta o Provedor B ao objeto ASPA |
| `step7-leak-on` | o peer começa a vazar as rotas da origem para o Provedor A |
| `step8-drop` | ROV e ASPA passam a descartar as rotas inválidas (o que roteadores de verdade fazem) |
| `step9-leak-off` | o peer para de vazar |
| `step9-hijack-off` | o AS666 fica em silêncio |

Além desses: `refresh` (faz os validadores revalidarem agora, inclusive o
rpki-client), `doctor`
(confere o ambiente), `clean-objects` (apaga as ROAs e o ASPA da CA, mantendo
a CA, para recomeçar a história sem refazer a preparação), `status`, `logs`,
`down` e `reset`. O botão **Comandos** do painel lista
todos, com um botão para rodar cada um.

## Arquivos

```
lab.conf                    MODE, LANGUAGE, EXPOSE_PORTS, titular, ASN e prefixos (o que você edita)
docker-compose.yml          topologia, redes e as versões fixadas das imagens
docker-compose.ports.yml    opcional: as portas próprias dos serviços no host (EXPOSE_PORTS=yes)
bird/
  vars.conf                 GERADO a partir do lab.conf: os "define" do BIRD
  origin.conf               AS64500, origina os prefixos
  provider-a.conf           AS64501, trânsito autorizado
  provider-b.conf           AS64502, o outro upstream da origem
  attacker-off.conf         AS666, em silêncio (sessões de pé, nada anunciado)
  attacker-simple.conf      AS666, sequestro ingênuo (AS_PATH: 666)
  attacker-posrov.conf      AS666, caminho forjado (AS_PATH: 666 <origem>)
  peer-off.conf             AS64499, só peering (comportamento correto)
  peer-leak.conf            AS64499, também vaza para o Provedor A
  observer1-<stage>.conf    AS64509, um arquivo por estágio de implantação (none, rov-mark,
                            rov-drop, aspa-mark, aspa-drop)
  observer1-extra-*.conf    alternativas para os exercícios extras A e E do guia
openbgpd/
  vars.conf                 GERADO a partir do lab.conf: macros do OpenBGPD
  observer2-<stage>.conf    AS64510 (rpki-client, por arquivo), um arquivo por estágio de implantação
  observer3-<stage>.conf    AS64511 (FORT, pelo RTR), um arquivo por estágio de implantação
  observer*-extra-*.conf    alternativas para os exercícios extras A e E do guia
rir/krill.conf              o Krill do LabNIC em modo testbed (TA + repositório)
rir-web/                    o painel do registro (Python puro + HTML)
images/bird/                Alpine 3.22 + BIRD 3.1.4 (+ vim, nano)
images/openbgpd/            Alpine 3.22 + OpenBGPD 8.8 (+ vim, nano), para o observer3
images/openbgpd-rpki-client/  Alpine 3.22 + OpenBGPD 8.8 + rpki-client 9.5 + RTRTR, para o observer2
images/krill/               Krill 0.16.0 oficial + vim, nano
images/routinator/          Routinator 0.15.2 oficial + vim, nano
images/fort/                FORT Validator, compilado do fonte
images/console/             ttyd (terminais no navegador) + coletor de estado
images/utils/               gera a PKI interna e instala o TAL
dashboard/
  index.html                a página do painel
  app.js, app.css           topologia, painel lateral, dock (terminais/apps web em abas), eventos
  guide.js                  o renderizador do roteiro: blocos de comando, desafios, previsões, pontos de controle
  checks.js                 como o estado do laboratório deve estar em cada ponto de controle
  i18n.js, nodes.js         textos da interface e de cada componente (en/es/pt)
  language.js               seletor de idioma (en/es/pt), compartilhado com o rir-web
guide/
  templates/GUIDE.*.md           as fontes do guia de aula, com marcadores {{NAME}} (edite estes)
  GUIDE.en.md, .es.md, .pt.md    COMPILADOS de templates/ pelo generate-config.sh (não edite)
  img/                           capturas de tela usadas pelo guia
  TERMS.md                       termos e regras de tradução
work/                       os seus próprios arquivos de configuração (graváveis pelo Terminal do laboratório)
web/nginx.conf              serve o painel e faz proxy do Routinator
vm/                         a máquina virtual: template do Packer, scripts, releases (veja vm/README.md)
docs/                       o site do projeto (GitHub Pages): páginas en/pt/es e capturas;
                            docs/tools/screenshots.py refaz as capturas
scripts/
  lab.sh                    up / down / refresh / reset / doctor / clean-objects / step* (os comandos da história)
  validate.sh               resumo do estado do laboratório, em texto
  generate-config.sh        lab.conf -> bird/vars.conf + openbgpd/vars.conf + guide/GUIDE.*.md
  check-guide-parity.sh     confere se as três traduções do guia mantêm a mesma estrutura
  i18n.sh                   catálogo de mensagens (en/es/pt) usado pelos scripts acima
```

## Versões

Todas as versões são **fixadas de propósito**. O laboratório faz parsing da
saída dessas ferramentas (o `status.py` e o `validate.sh` leem a saída do
`birdc`, do `bgpctl` e do Routinator), e uma atualização automática no meio de
um curso pode quebrar o painel sem que uma única linha deste repositório tenha
mudado.

| Componente | Versão | Fixada em | Se você mudar |
|---|---|---|---|
| Krill | `v0.16.0` | `FROM` em `images/krill/Dockerfile` (usado pelos serviços `krill` e `rir`) | as capturas de tela e os passos do guia assumem a interface web do 0.16 (abas ROAs e ASPAs) e os nomes de subcomando do `krillc` |
| Routinator | `v0.15.2` | `FROM` em `images/routinator/Dockerfile` | precisa do `--enable-aspa` e de RTR v2; versões antigas ignoram os objetos ASPA em silêncio |
| FORT Validator | `1.7.0.experimental` | `FORT_VERSION` em `images/fort/Dockerfile` | **ASPA e RTR v2 só existem a partir desta tag.** A 1.6.x sobe normalmente e serve ROAs, e todo `avs` do observer3 fica `unknown` |
| BIRD | 3.1.4 | indiretamente, pelo `FROM alpine:3.22` em `images/bird/Dockerfile` | `aspa_check_upstream()` precisa de BIRD ≥ 2.16. Subir o Alpine muda a versão do BIRD como efeito colateral |
| OpenBGPD | 8.8 | indiretamente, pelo `FROM alpine:3.22` em `images/openbgpd/Dockerfile` e `images/openbgpd-rpki-client/Dockerfile` | precisa de 8.x para `aspa-set`, `role` e `rtr { min-version 2 }` |
| rpki-client | 9.5 | indiretamente, pelo `FROM alpine:3.22` em `images/openbgpd-rpki-client/Dockerfile` | o painel e o `doctor` leem a saída JSON dele e o `aspa-set` na saída para o OpenBGPD |
| RTRTR | `v0.3.3` | `FROM nlnetlabs/rtrtr` em `images/openbgpd-rpki-client/Dockerfile` | só é usado no exercício extra E; precisa transportar ASPA no RTR v2 (o StayRTR 0.6.4, companheiro habitual do rpki-client, não transporta) |
| nginx | `1.29-alpine` | `docker-compose.yml` (`web`) | só serve o painel; risco baixo |

Três dessas fixações são **indiretas**, e vale a pena conhecê-las: BIRD,
OpenBGPD e rpki-client são pacotes do Alpine, então as versões deles ficam
congeladas pelo `alpine:3.22`, não escolhidas aqui. O Alpine só faz backport
de correções de segurança dentro de um branch de release, então o `3.22`
continua entregando BIRD 3.1.4, OpenBGPD 8.8 e rpki-client 9.5. Trocar essa
linha para `alpine:3.23`, porém, muda todos de uma vez, em silêncio.

O FORT é compilado do fonte (`images/fort/Dockerfile`) em vez de puxado do
`nicmx/fort-validator`, porque a imagem publicada é só amd64, e o laboratório
precisa continuar nativo em hosts arm64. A compilação é em Debian, não em
Alpine, porque o FORT inclui `<sys/queue.h>`, um header BSD/glibc que a musl
não fornece.

Para mover uma versão fixada, edite o único lugar listado acima, depois rode
`./scripts/lab.sh up` (ele reconstrói) e `./scripts/validate.sh` para conferir
que os observadores continuam produzindo vereditos, e não `?`.

### A PKI interna (MODE=local)

Toda URI de RPKI é HTTPS, e os validadores e o Krill validam TLS de verdade:
não têm o botão "prosseguir assim mesmo" do navegador. Por isso o laboratório
gera a sua própria autoridade certificadora (o contêiner `pki-init`), que
assina o certificado do `rir.lab`. O certificado dessa CA é entregue a quem
precisa confiar nela:

| Quem | Como |
|---|---|
| Routinator | `--rrdp-root-cert=/pki/ca.pem` |
| FORT | instalado no trust store do sistema pelo entrypoint da imagem |
| rpki-client (observer2) | instalado no trust store do sistema pelo entrypoint da imagem |
| Krill do titular | `KRILL_HTTPS_ROOT_CERTS=/pki/ca.pem` |
| Painel do registro | contexto SSL do Python |

O FORT recebe tratamento diferente porque o `--http.ca-path` dele espera um
diretório com hashes do OpenSSL, não um arquivo único, e instalar a CA no
trust store do sistema é menos frágil do que manter esse diretório.

O Routinator também roda com `--allow-dubious-hosts`, já que `rir.lab` não é
um nome público, e com `--disable-rsync`, porque o único transporte aqui é o
RRDP. O rpki-client não precisa de nenhum dos dois: aceita o `rir.lab`, e só
tenta o rsync quando o RRDP falha.

Todas as imagens usadas (Alpine, Debian, nginx, Krill, Routinator, RTRTR) são
multi-arquitetura (amd64/arm64), e o FORT e o OpenBGPD são compilados ou
empacotados nativamente. Nada roda sob emulação, nem em Apple Silicon, nem em
Intel/AMD, nem em Windows.

## Idioma

O painel do laboratório, o painel do registro e as mensagens impressas pelos
scripts (`lab.sh`, `validate.sh`, ...) existem em inglês, espanhol e
português. O padrão é definido por `LANGUAGE` no `lab.conf`, mas cada
navegador pode trocar de idioma livremente pelo seletor no topo de cada
painel, sem afetar ninguém mais.

O vocabulário de protocolo (BGP, ROA, ASPA, números de RFC, os estados
Valid/Invalid/Unknown, nomes de comando) fica em inglês nos três idiomas. É o
vocabulário que a saída de linha de comando do Krill, do Routinator, do BIRD
e do OpenBGPD já usa, e misturar idiomas ali só atrapalharia a conferência
cruzada com as ferramentas.

Os comentários no código-fonte (scripts, arquivos `*.conf`, Dockerfiles,
Python) estão todos em inglês, independentemente do idioma do laboratório.

O inglês é a fonte de todas as traduções. Uma mudança no guia começa em
`guide/templates/GUIDE.en.md` e vai para os templates em espanhol e
português na mesma mudança; o `scripts/check-guide-parity.sh` (rodado a cada
`up`) confere se os três continuam com a mesma estrutura, e o
[guide/TERMS.md](guide/TERMS.md) lista os termos da interface e as palavras a
evitar em cada idioma.

## Valores diferentes

Tudo o que você pode querer mudar fica no **`lab.conf`**. Os valores mostrados
ao longo deste README (AS64500, 203.0.113.0/24, ...) são os **padrões**. O
guia, por outro lado, é compilado a partir do `lab.conf` e sempre mostra os
seus:

```sh
ORIGIN_ASN=64500
ORIGIN_V4=203.0.113.0/24
ORIGIN_V4_MAXLEN=24
ORIGIN_V6=3fff:cafe::/32
ORIGIN_V6_MAXLEN=32
```

Edite e rode `./scripts/lab.sh up`. Isso chama o `scripts/generate-config.sh`,
que traduz esses valores para `bird/vars.conf` (os `define` do BIRD) e
`openbgpd/vars.conf` (as macros do OpenBGPD), incluídos por todos os
roteadores. O painel relê o `lab.conf` a cada ciclo, e o `up` também compila o
guia a partir de `guide/templates/` com os seus valores.

Os ASNs dos provedores e dos observadores (64501/64502/64509/64510/64511) também
estão lá, mas não precisam mudar: são ASNs de documentação (RFC 5398) e
funcionam com qualquer ASN de origem. O `PEER_ASN` (64499) é o mesmo caso:
está dentro do mesmo bloco reservado, 64496-64511, e pertence à história do
guia como todo o resto do laboratório. Só o `ATTACKER_ASN` (666) fica de fora
dessa faixa: foi escolhido por ser fácil de lembrar, não por estar reservado
para nada. Nenhum dos dois toca a Internet real de qualquer forma.

## Licença

- O código e as configurações do laboratório: [Apache-2.0](LICENSE).
- O guia, os READMEs e suas traduções: [CC BY 4.0](LICENSE-docs).
- Os softwares que o laboratório executa mantêm suas próprias licenças: veja
  [THIRD-PARTY.md](THIRD-PARTY.md).
