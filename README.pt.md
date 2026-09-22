# RPKI SelfLab

*Laboratório autônomo e guia de autoestudo para RPKI, ROA, ROV e ASPA*

*[English](README.md) · [Español](README.es.md) · [Português](README.pt.md)*

Laboratório de RPKI (ROA, ROV e ASPA) em contêineres, para rodar em qualquer computador
com Docker (Mac, Windows ou Linux - testado com OrbStack e Docker Desktop).
Ele publica ROAs e um objeto ASPA e depois mostra o que **dois validadores
diferentes e dois roteadores diferentes** fazem com exatamente os mesmos
objetos - enquanto um sequestrador (AS666) e um peer que vaza rotas tentam
atrapalhar. O guia do laboratório é uma história só: três ataques, e o momento
em que cada um deixa de funcionar.

Ele tem dois modos, escolhidos com a variável `MODE` no `lab.conf`:

| MODE | Quem certifica os recursos | Internet |
|---|---|---|
| `local` (padrão) | **LabNIC**, um RIR/NIR simulado que roda dentro do laboratório | não precisa |
| `beta` | o sistema de testes do Registro.br | precisa, além de um login em beta.registro.br |

No modo local o laboratório é **autocontido**: âncora de confiança própria,
repositório próprio e um painel de registro onde acontecem a delegação da CA e
a autorização de publicação, usando as mesmas trocas de XML das RFC 6492 e 8183.

O guia está em **[guide/GUIDE.en.md](guide/GUIDE.en.md)** (também em
[espanhol](guide/GUIDE.es.md) e [português](guide/GUIDE.pt.md)). No painel web,
o mesmo conteúdo aparece renderizado passo a passo, no idioma selecionado ali.

## Primeiros passos

```sh
./scripts/lab.sh up
open http://localhost:8080
```

| Serviço | URL | Observação |
|---|---|---|
| Painel do laboratório | http://localhost:8080 | topologia clicável |
| Krill (CA) | http://krill.localhost:8080 | token `passlab` |
| Routinator | http://routinator.localhost:8080 | validador do observer1 |
| FORT (RTR) | localhost:3324 | validador do observer2, sem interface web |
| Console (ttyd) | http://console.localhost:8080 | terminal no navegador |
| Painel do registro | http://registry.localhost:8080 | só no `MODE=local` |
| Krill do LabNIC | http://rir-krill.localhost:8080 | só no `MODE=local`, token `passlab` |

Tudo é acessível por uma só porta, a 8080: o painel em `localhost`, e cada um
dos outros aplicativos web sob o seu próprio `<nome>.localhost` (os navegadores
resolvem `*.localhost` para a sua máquina, e o nginx roteia pelo nome). As portas
própias dos serviços (3000, 3001, 7681, 8081, 8323) continuam publicadas também.
Isso ajuda na máquina virtual, em que só a 8080 precisa ser encaminhada.

## Como máquina virtual

Se você prefere não instalar o Docker, o laboratório também vem como uma
pequena máquina virtual com área de trabalho própria (navegador e terminal) que
já contém tudo, imagens inclusive: nada a configurar, e roda sem acesso à
Internet. Veja [vm/README.pt.md](vm/README.pt.md).

## Topologia

```
                 LabNIC   (RIR/NIR: âncora de confiança + repositório)
                /                                      \
            RRDP                                        RRDP
             v                                            v
        Routinator                                  FORT Validator
             |  RTR v2 :3323                             |  RTR v2 :3323
             v                                            v
   observer1  AS64510  (BIRD)                observer2  AS64511  (OpenBGPD)

        os dois observadores recebem o MESMO prefixo pelos DOIS caminhos:

        Provedor A  AS64501                    Provedor B  AS64502
                     \                          /
                      \                        /
                       origem  AS64500  --  Krill (a CA do titular)
                       10.0.0.0/24 , 3fff:cafe::/32
```

O AS64500 é multihomed e anuncia `10.0.0.0/24` e `3fff:cafe::/32`. Cada
observador recebe o mesmo prefixo pelos dois provedores. A origem prefere o
Provedor B: ela repete seu ASN duas vezes (prepend) ao anunciar para o
Provedor A (o backup), então o caminho de A é dois saltos mais longo. Mais dois
roteadores estão na topologia e ficam em silêncio até que a história do guia os
ligue:

```
   AS666 (atacante) ---- sessões BGP diretas ----> observer1, observer2
                         (um cliente dos observadores)

   peer  AS64999 ---- peering privado ---- origem AS64500
        |
        +---- trânsito ---- Provedor A
```

- **AS666** sequestra os prefixos da origem: primeiro anunciando-os como seus
  (`step2-hijack-simple`), depois forjando o AS_PATH para que termine na
  origem verdadeira (`step4-hijack-posrov`).
- **peer** é uma rede legítima que faz peering privado com a origem e compra
  trânsito do Provedor A. Ela vaza as rotas da origem para o Provedor A quando
  o guia manda (`step7-leak-on`) - um vazamento de rota, que o ROV nunca
  consegue enxergar e o ASPA consegue.

| Rede Docker | IPv4 | IPv6 | entre |
|---|---|---|---|
| `lab-l-org-a` | 10.200.1.0/24 | fd00:1::/64 | origem ↔ Provedor A |
| `lab-l-org-b` | 10.200.2.0/24 | fd00:2::/64 | origem ↔ Provedor B |
| `lab-l-a-obs1` | 10.200.3.0/24 | fd00:3::/64 | Provedor A ↔ observer1 |
| `lab-l-b-obs1` | 10.200.4.0/24 | fd00:4::/64 | Provedor B ↔ observer1 |
| `lab-l-a-obs2` | 10.200.5.0/24 | fd00:5::/64 | Provedor A ↔ observer2 |
| `lab-l-b-obs2` | 10.200.6.0/24 | fd00:6::/64 | Provedor B ↔ observer2 |
| `lab-l-666-obs1` | 10.200.7.0/24 | fd00:7::/64 | AS666 ↔ observer1 |
| `lab-l-666-obs2` | 10.200.8.0/24 | fd00:8::/64 | AS666 ↔ observer2 |
| `lab-l-peer-org` | 10.200.9.0/24 | fd00:9::/64 | peer ↔ origem (peering privado) |
| `lab-l-peer-a` | 10.200.10.0/24 | fd00:10::/64 | peer ↔ Provedor A (trânsito) |
| `lab-mgmt` | 172.30.0.0/24 | fd00:30::/64 | Krill, validadores, observadores, painel |

## Os dois observadores

O laboratório roda de propósito o mesmo experimento duas vezes, em duas pilhas
independentes:

| | observer1 | observer2 |
|---|---|---|
| Roteador | BIRD 3.1.4 | OpenBGPD 8.8 |
| Validador | Routinator | FORT Validator |
| ASN | 64510 | 64511 |
| Como se lê o veredito | large communities definidas pelos filtros do laboratório | atributos nativos `ovs` / `avs` da rota |
| Inspecionar com | `birdc show route table master4 all` | `bgpctl show rib detail` |

O BIRD não tem atributo de validação por rota, então os arquivos `bird/observer1-*.conf` gravam
cada veredito numa large community — `(64510,1,x)` para ROV e `(64510,2,x)` para
ASPA. O OpenBGPD calcula os dois nativamente e o `bgpctl -j` entrega tudo em
JSON, e é por isso que as duas configurações parecem tão diferentes testando a
mesma coisa.

### Por que o observer2 usa `role provider`

O OpenBGPD só executa a verificação ASPA numa sessão que tenha um papel (role)
da RFC 9234, e **o papel decide qual algoritmo ASPA roda**. Os observadores
ficam acima dos provedores — os anúncios sobem a partir da origem —, então cada
observador é o upstream dos provedores e as rotas chegam de um cliente. Isso
seleciona o algoritmo *upstream*, o mesmo que os `bird/observer1-*.conf` pedem
com `aspa_check_upstream()`.

Configure `role customer` no lugar e o algoritmo *downstream* roda: o caminho
pelo Provedor B volta como **Valid**. Mesmos objetos, mesmo AS_PATH, veredito
diferente. É a coisa mais surpreendente deste laboratório, e não é bug de
nenhuma das duas implementações.

Uma consequência: trocar de estágio no observer2 exige reiniciá-lo, porque o
papel é negociado na abertura da sessão, e uma sessão RTR que já está de pé
mantém a versão que negociou. Depois de um `bgpctl reload` puro, todo `avs`
volta para `unknown`. Os comandos `step*` que trocam de estágio já fazem o
reinício para você (o nome do estágio fica guardado em `/etc/lab-stage` dentro
do contêiner, então um reinício posterior volta no mesmo estágio).

### Estágios de implantação

Os observadores não sobem validando nada: começam como roteadores BGP comuns, e
o guia implanta a validação neles por estágios, como você faria num roteador
real - primeiro *marcando* o que uma verificação sinaliza (uma community e uma
preferência menor, nada é descartado), depois *descartando*. Cada estágio é um
arquivo de configuração completo por observador:

| Estágio | observer1 (BIRD) | observer2 (OpenBGPD) | O que faz |
|---|---|---|---|
| `none` | `observer1-none.conf` | `observer2-none.conf` | BGP comum, sem validação (como o laboratório começa) |
| `rov-mark` | `observer1-rov-mark.conf` | `observer2-rov-mark.conf` | sessão RTR + ROV, rotas inválidas apenas marcadas |
| `rov-drop` | `observer1-rov-drop.conf` | `observer2-rov-drop.conf` | rotas ROV Invalid rejeitadas |
| `aspa-mark` | `observer1-aspa-mark.conf` | `observer2-aspa-mark.conf` | ROV e verificação ASPA, os dois apenas marcando |
| `aspa-drop` | `observer1-aspa-drop.conf` | `observer2-aspa-drop.conf` | ROV e ASPA Invalid ambos rejeitados |

Ler um arquivo depois do outro é o ponto: o que muda entre dois estágios é o
que significa implantar aquela verificação. O selo no cabeçalho do painel mostra
o estágio em que os observadores estão.

## Os comandos da história

O `./scripts/lab.sh` alterna o AS666 e o peer entre comportamentos; os nomes
levam o número do passo do guia a que pertencem. Todos podem ser repetidos com
segurança.

| Comando | O que faz |
|---|---|
| `step1-clean` | AS666 e peer em silêncio, e os dois observadores de volta ao BGP comum (sem validação) |
| `step2-hijack-simple` | o AS666 anuncia os prefixos da origem como seus |
| `step3-rov-mark` | implanta o ROV nos dois observadores, apenas marcando |
| `step4-hijack-posrov` | o AS666 forja o caminho para que termine na origem verdadeira |
| `step5-aspa-mark` | implanta também a verificação ASPA, também apenas marcando |
| `step7-leak-on` | o peer começa a vazar as rotas da origem para o Provedor A |
| `step8-drop` | ROV e ASPA passam a descartar as rotas inválidas (o que roteadores de verdade fazem) |
| `step9-leak-off` | o peer para de vazar |
| `step9-hijack-off` | o AS666 fica em silêncio |

## Arquivos

```
lab.conf                    MODE, LANGUAGE, titular, ASN e prefixos (o que você edita)
docker-compose.yml          topologia, redes e as versões fixadas das imagens
bird/
  vars.conf                 GERADO a partir do lab.conf: os "define" do BIRD
  origin.conf               AS64500, origina os prefixos
  provider-a.conf           AS64501, trânsito autorizado
  provider-b.conf           AS64502, o outro upstream da origem
  attacker-off.conf         AS666, em silêncio (sessões de pé, nada anunciado)
  attacker-simple.conf      AS666, sequestro ingênuo (AS_PATH: 666)
  attacker-posrov.conf      AS666, caminho forjado (AS_PATH: 666 <origem>)
  peer-off.conf             AS64999, só peering (comportamento correto)
  peer-leak.conf            AS64999, também vaza para o Provedor A
  observer1-<stage>.conf    AS64510, um arquivo por estágio de implantação (none, rov-mark,
                            rov-drop, aspa-mark, aspa-drop)
openbgpd/
  vars.conf                 GERADO a partir do lab.conf: macros do OpenBGPD
  observer2-<stage>.conf    AS64511, um arquivo por estágio de implantação
rir/krill.conf              o Krill do LabNIC em modo testbed (TA + repositório)
rir-web/                    o painel do registro (Python puro + HTML)
images/bird/                Alpine 3.22 + BIRD 3.1.4
images/openbgpd/            Alpine 3.22 + OpenBGPD 8.8
images/fort/                FORT Validator, compilado do fonte
images/console/             ttyd (terminal no navegador) + coletor de estado
images/utils/               gera a PKI interna e instala o TAL
dashboard/
  index.html                o painel
  language.js               seletor de idioma (en/es/pt), compartilhado com o rir-web
guide/
  templates/GUIDE.*.md           as fontes do guia de aula, com marcadores {{NAME}} (edite estes)
  GUIDE.en.md, .es.md, .pt.md    COMPILADOS de templates/ pelo generate-config.sh (não edite)
web/nginx.conf              serve o painel e faz proxy do Routinator
vm/                         a máquina virtual: template do Packer, scripts, releases (veja vm/README.md)
scripts/
  lab.sh                    up / down / refresh / reset / step* (os comandos da história)
  validate.sh               resumo do estado do laboratório, em texto
  generate-config.sh        lab.conf -> bird/vars.conf + openbgpd/vars.conf + guide/GUIDE.*.md
  i18n.sh                   catálogo de mensagens (en/es/pt) usado pelos scripts acima
```

## Versões

Todas as versões são **fixadas de propósito**. O laboratório faz parsing da
saída dessas ferramentas (o `status.py` e o `validate.sh` leem a saída do
`birdc`, do `bgpctl` e do Routinator), então uma atualização automática no meio
de um curso pode quebrar o painel sem que uma única linha deste repositório
tenha mudado.

| Componente | Versão | Fixada em | Se você mudar |
|---|---|---|---|
| Krill | `v0.16.0` | `docker-compose.yml` (serviços `krill` e `rir`) | no 0.16 o ASPA só existe pela CLI; os passos `krillc aspas` do guia assumem esses nomes de subcomando |
| Routinator | `v0.15.2` | `docker-compose.yml` (`routinator`) | precisa do `--enable-aspa` e de RTR v2; versões antigas ignoram os objetos ASPA em silêncio |
| FORT Validator | `1.7.0.experimental` | `FORT_VERSION` em `images/fort/Dockerfile` | **ASPA e RTR v2 só existem a partir desta tag.** A 1.6.x sobe normalmente e serve ROAs, e todo `avs` do observer2 fica `unknown` |
| BIRD | 3.1.4 | indiretamente, pelo `FROM alpine:3.22` em `images/bird/Dockerfile` | `aspa_check_upstream()` precisa de BIRD ≥ 2.16. Subir o Alpine muda a versão do BIRD como efeito colateral |
| OpenBGPD | 8.8 | indiretamente, pelo `FROM alpine:3.22` em `images/openbgpd/Dockerfile` | precisa de 8.x para `aspa-set`, `role` e `rtr { min-version 2 }` |
| nginx | `1.29-alpine` | `docker-compose.yml` (`web`) | só serve o painel; risco baixo |

Duas dessas fixações são **indiretas** e vale conhecê-las: BIRD e OpenBGPD são
pacotes do Alpine, então as versões deles são congeladas pelo `alpine:3.22`, e
não escolhidas aqui. O Alpine só faz backport de correções de segurança dentro
de um branch de release, então o `3.22` continua entregando BIRD 3.1.4 e
OpenBGPD 8.8 — mas trocar essa linha para `alpine:3.23` muda os dois roteadores
de uma vez, em silêncio.

O FORT é compilado do fonte (`images/fort/Dockerfile`) em vez de puxado do
`nicmx/fort-validator`, porque a imagem publicada é só amd64 e o laboratório
deve continuar nativo em hosts arm64. A compilação é em Debian, e não em
Alpine, porque o FORT inclui `<sys/queue.h>`, um header BSD/glibc que a musl
não fornece.

Para mover uma versão fixada: edite o único lugar listado acima, depois rode
`./scripts/lab.sh up` (ele reconstrói) e `./scripts/validate.sh` para confirmar
que os dois observadores continuam produzindo vereditos, e não `?`.

### A PKI interna (MODE=local)

Toda URI de RPKI é HTTPS, e os validadores e o Krill validam TLS - eles não têm
o botão "prosseguir assim mesmo" do navegador. Então o laboratório gera a
própria autoridade certificadora (o contêiner `pki-init`), que assina o
certificado do `rir.lab`. O certificado dessa CA é entregue a quem precisa
confiar nela:

| Quem | Como |
|---|---|
| Routinator | `--rrdp-root-cert=/pki/ca.pem` |
| FORT | instalado no trust store do sistema pelo entrypoint da imagem |
| Krill do titular | `KRILL_HTTPS_ROOT_CERTS=/pki/ca.pem` |
| Painel do registro | contexto SSL do Python |

O FORT recebe tratamento diferente porque o `--http.ca-path` dele espera um
diretório com hashes do OpenSSL, e não um arquivo único, e instalar a CA no
trust store do sistema é menos frágil do que manter esse diretório.

O Routinator também roda com `--allow-dubious-hosts`, porque `rir.lab` não é um
nome público, e com `--disable-rsync`, já que o único transporte aqui é o RRDP.

Todas as imagens usadas (Alpine, Debian, nginx, Krill, Routinator) são
multi-arquitetura (amd64/arm64), e o FORT e o OpenBGPD são compilados ou
empacotados nativamente, então nada roda sob emulação em Apple Silicon,
Intel/AMD ou Windows.

## Idioma

O painel do laboratório, o painel do registro e as mensagens impressas pelos
scripts (`lab.sh`, `validate.sh`, ...) existem em inglês, espanhol e português.
O padrão é definido por `LANGUAGE` no `lab.conf`; cada navegador pode trocar de
idioma livremente pelo seletor no topo de cada painel, sem afetar ninguém mais.

O vocabulário de protocolo (BGP, ROA, ASPA, números de RFC, os estados
Valid/Invalid/Unknown, nomes de comando) fica em inglês nos três idiomas — é o
vocabulário que a saída de linha de comando do Krill, do Routinator, do BIRD e
do OpenBGPD já usa, e misturar idiomas ali só atrapalharia a conferência
cruzada com as ferramentas.

Os comentários no código-fonte (scripts, arquivos `*.conf`, Dockerfiles,
Python) estão todos em inglês, independentemente do idioma do laboratório.

## Valores diferentes

Tudo o que você pode querer mudar fica no **`lab.conf`**. Os valores mostrados
ao longo deste README (AS64500, 10.0.0.0/24, ...) são os **padrões**; o guia,
por outro lado, é compilado a partir do `lab.conf` e sempre mostra os seus:

```sh
ORIGIN_ASN=64500
ORIGIN_V4=10.0.0.0/24
ORIGIN_V4_MAXLEN=24
ORIGIN_V6=3fff:cafe::/32
ORIGIN_V6_MAXLEN=32
```

Edite e rode `./scripts/lab.sh up`. Isso chama o `scripts/generate-config.sh`,
que traduz esses valores para `bird/vars.conf` (os `define` do BIRD) e
`openbgpd/vars.conf` (as macros do OpenBGPD), incluídos por todos os
roteadores. O painel relê o `lab.conf` a cada ciclo, e o `up` também compila o
guia a partir de `guide/templates/` com os seus valores.

Os ASNs dos provedores e dos observadores — 64501/64502/64510/64511 — também
estão lá, mas não precisam mudar: são ASNs de documentação (RFC 5398) e
funcionam com qualquer ASN de origem. O mesmo vale para `ATTACKER_ASN` (666) e
`PEER_ASN` (64999), que pertencem à história do guia; o do peer está na faixa
de uso privado (RFC 6996), e nenhum dos dois toca a Internet real.

## Licença

- O código e as configurações do laboratório: [Apache-2.0](LICENSE).
- O guia, os READMEs e suas traduções: [CC BY 4.0](LICENSE-docs).
- Os softwares que o laboratório executa mantêm suas próprias licenças: veja [THIRD-PARTY.md](THIRD-PARTY.md).
