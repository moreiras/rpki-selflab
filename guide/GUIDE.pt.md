# RPKI SelfLab

*Laboratório autônomo e guia de autoestudo para RPKI, ROA, ROV e ASPA*

*[English](GUIDE.en.md) · [Español](GUIDE.es.md) · [Português](GUIDE.pt.md)*

**Objetivo:** acompanhar um sequestrador e um peer que vaza rotas por um
laboratório rodando na sua própria máquina. Ver o que a validação de origem
(ROV) pega, o que ela deixa passar, e o que o ASPA acrescenta - com cada
veredito conferido por duas pilhas independentes (BIRD + Routinator, e
OpenBGPD + FORT).

Este é um laboratório autocontido: tudo roda em contêineres na sua própria
máquina. Ele presume que você já tem uma noção básica de RPKI, ROAs, ROV e
ASPA. Você pode certificar seus recursos inteiramente de forma local ou, se
preferir usar um registro do mundo real, contra o sistema de testes do
Registro.br.

O laboratório é uma única história em nove passos: **três ataques, e o
momento em que cada um deixa de funcionar.** Uma preparação curta vem antes
(subir o laboratório, certificar seus recursos), e alguns exercícios extras
vêm no fim.

## O que o RPKI pede do seu próprio AS - e o que este laboratório implanta

O RPKI tem duas metades, e cada uma tem duas partes:

| | A origem publica... | ...e os roteadores validam |
|---|---|---|
| **Quem pode originar um prefixo** | **ROAs** (Route Origin Authorizations) | **ROV** (Route Origin Validation) |
| **Quais caminhos são plausíveis** | um objeto **ASPA** (Autonomous System Provider Authorization) | **verificação ASPA** |

Na vida real, **as duas coisas cabem no AS que você opera**: você *publica*
objetos sobre os seus próprios recursos e *valida* o que os seus vizinhos
enviam. Publicar sem validar protege os outros, mas não você. Validar sem
publicar protege você, mas deixa os seus próprios prefixos desprotegidos
para todos os demais.

Neste laboratório, para fins didáticos, as duas coisas ficam separadas:

- **A publicação é implantada apenas no AS de origem** (AS64500, cuja CA vive
  no Krill). Ele é o único AS que cria ROAs e um objeto ASPA.
- **A validação é implantada apenas nos ASes observadores** (observer1 e
  observer2), os dois roteadores que você vai observar. Todo o resto do
  laboratório é um roteador BGP comum que nunca olha para o RPKI.

A validação é implantada nos observadores **em dois estágios, para cada
verificação**: primeiro o roteador apenas *marca* o que a verificação sinaliza
(uma community, uma preferência menor - nada é descartado, então você vê o
que aconteceria), e só depois ele *descarta*. **Descartar as inválidas é o
que os roteadores de verdade fazem.** Marcar é o ensaio que você faz antes de
confiar numa verificação o bastante para deixá-la rejeitar rotas.

## Glossário

Uma revisão rápida, não uma introdução completa: é isso que estes termos
significam *neste laboratório*. Pule à frente se já está confortável com
eles.

| Termo | Significado |
|---|---|
| **RIR/NIR** | Registro Regional/Nacional de Internet - aloca ASNs e blocos de IP e, em RPKI, certifica que você é o titular deles |
| **CA** | Certificate Authority (Autoridade Certificadora) - o motor RPKI que transforma "estes recursos são seus" em certificados e objetos assinados |
| **TA** | Trust Anchor (âncora de confiança) - a CA na raiz da cadeia de confiança de um validador; tudo o mais ou é ela, ou foi (transitivamente) certificado por ela |
| **ROA** | Route Origin Authorization - um objeto assinado dizendo "este ASN pode originar este prefixo, até este comprimento" |
| **ASPA** | Autonomous System Provider Authorization - um objeto assinado dizendo "estes são os únicos ASes dos quais este AS aceita rotas como provedor upstream" |
| **ROV** | Route Origin Validation - confere o *último* AS da rota (o que a originou) contra as ROAs |
| **Verificação ASPA** | confere o *caminho inteiro*, salto a salto, contra os objetos ASPA |
| **RRDP** | RPKI Repository Delta Protocol - como um validador busca os objetos assinados num ponto de publicação |
| **RTR** | RPKI-to-Router protocol - como um validador entrega seus vereditos a um roteador |
| **VRP** | Validated ROA Payload - a tripla (ASN, prefixo, comprimento máximo) que um validador derivou de uma ROA |
| **Sequestro (hijack)** | anunciar um prefixo que pertence a outra pessoa, como se fosse seu (ou como se viesse através dela) |
| **Vazamento de rota** | repassar uma rota que você aprendeu de um vizinho para outro vizinho para o qual você não deveria (RFC 7908) - ninguém mente sobre a origem, mas o caminho tem um formato que não poderia acontecer legitimamente |

---

## A topologia

```
              LabNIC   (RIR/NIR: âncora de confiança + repositório)
             /                                              \
         RRDP                                                RRDP
          v                                                    v
     Routinator                                          FORT Validator
          |  RTR v2 :3323                                      |  RTR v2 :3323
          v                                                    v
  observer1 AS64510 (BIRD)                       observer2 AS64511 (OpenBGPD)

       os dois observadores recebem o MESMO prefixo pelos DOIS caminhos:

            Provedor A  AS64501
            Provedor B  AS64502
                          \          /
                           \        /
                    origem AS64500   +   Krill (a CA do titular)
                    203.0.113.0/24 , 3fff:cafe::/32
```

O AS64500 é multihomed, e tem uma preferência clara: **o Provedor B é a
entrada, o Provedor A é o backup.** Para conseguir isso, a origem faz
*prepend* do seu próprio ASN duas vezes ao anunciar para o Provedor A
(`64500 64500 64500` em vez de apenas `64500`), então
todo caminho por A parece dois saltos mais longo que o caminho por B - uma
engenharia de tráfego de entrada bem comum. Os dois provedores repassam o
**mesmo prefixo** aos dois observadores, com o mesmo AS de origem. O
laboratório roda a história inteira **duas vezes, em paralelo**, sobre duas
pilhas independentes: o observer1 e o observer2 veem exatamente os mesmos
anúncios e os mesmos objetos RPKI, mas cada um com o seu próprio roteador e o
seu próprio validador.

Mais dois roteadores entram na história. Os dois aparecem no painel, e os
dois ficam calados até que a história os ligue:

```
   AS666 (o atacante) ---- sessões BGP diretas ----> observer1, observer2
                             (um cliente dos observadores: qualquer cliente
                              pode enviar a eles um anúncio, e ninguém o
                              confere a menos que os observadores validem)

   peer AS64499 ---- peering privado ---- origem AS64500
        |
        +---- trânsito ---- Provedor A
```

| Componente | ASN | Papel |
|---|---|---|
| origem | 64500 | o seu AS; origina os prefixos |
| Provedor A | 64501 | um dos dois upstreams da origem - o backup (a origem faz prepend duas vezes para ele) |
| Provedor B | 64502 | o outro upstream da origem - o preferido |
| observer1 | 64510 | roteador que valida: **BIRD** + **Routinator** |
| observer2 | 64511 | roteador que valida: **OpenBGPD** + **FORT Validator** |
| AS666 | 666 | o atacante: um cliente dos observadores, que sequestra os prefixos da origem |
| peer | 64499 | uma rede legítima que faz peering com a origem e compra trânsito do Provedor A |

Os ASNs 64496-64511 são reservados para documentação (RFC 5398), e é dali que
vem cada ASN deste laboratório - origem, provedores, observadores, peer -
com uma única exceção: o AS666, que não está em nenhum bloco
reservado. Foi escolhido só por ser fácil de lembrar. De qualquer forma,
nenhum deles chega perto da Internet de verdade.

> O ASN e os prefixos da origem ficam no arquivo **`lab.conf`**, na raiz do
> laboratório. Quer outros? Edite lá e rode `./scripts/lab.sh up`: os
> roteadores, os scripts e este roteiro na tela passam a usar os novos
> valores. (O roteiro é escrito com marcadores `{{ NAME }}` em
> `guide/templates/`, e o `up` o compila em `guide/GUIDE.*.md` com os valores
> do `lab.conf`. Edite os templates, nunca os arquivos compilados.)

### Como a história está organizada

Todo passo começa com uma caixa de **Estado**: em qual estágio de implantação
os observadores estão, o que o AS666 e o peer estão fazendo, e
quais objetos RPKI deveriam existir. Se o seu laboratório não bate, a caixa
também diz como colocá-lo de volta.

Essa recuperação é deliberadamente simples: **cada comando
`./scripts/lab.sh stepN-*` define o estado *inteiro* do seu passo**, não só o
que mudou desde o anterior. Rode `step9-leak-off`, depois `step3-rov-mark`, e
você cai exatamente onde o Passo 3 espera. O vazamento, o estágio de
descarte, tudo o que o Passo 9 deixou para trás some, redefinido pelo próprio
`step3-rov-mark`. Vale para qualquer par de passos, em qualquer direção: os
comandos não presumem que você está indo para a frente, e não deixam nada
para o próximo tropeçar. Três coisas se movem juntas toda vez que um comando
`stepN-*` roda:

- **O estágio de implantação dos observadores.** Eles começam sem nenhuma
  validação, e a história os leva por quatro estágios: as duas verificações
  ficam marcando antes de qualquer uma delas começar a descartar, e só então
  as duas passam a descartar juntas, no Passo 8. Cada comando define um
  estágio inteiro nos **dois** observadores de uma vez, seja qual for o estágio
  em que estavam antes:

  | Estágio | O que os observadores fazem | Comando |
  |---|---|---|
  | `none` | BGP puro, sem validação (como o laboratório começa) | `step1-clean` |
  | `rov-mark` | ROV implantado, rotas inválidas apenas *marcadas* | `step3-rov-mark` |
  | `aspa-mark` | verificação ASPA entra em cena, também só *marcando* | `step5-aspa-mark` |
  | `aspa-drop` | ROV e ASPA passam a *descartar* juntos - produção | `step8-drop` |

  Cada estágio é um arquivo de configuração completo por observador
  (`bird/observer1-<stage>.conf`, `openbgpd/observer2-<stage>.conf`), e o
  roteiro pede que você os abra: **o que muda de um arquivo para o outro é o
  que significa implantar aquela verificação.** Você não precisa decorar em
  que estágio está - o selo no cabeçalho do painel diz (*validação:
  nenhuma*, *ROV: marcando*, *ROV: descartando*, ...), e fica âmbar se os
  dois observadores não estiverem no mesmo. O observer2 reinicia toda vez
  que o estágio muda (o OpenBGPD negocia os seus papéis da RFC 9234 e a sua
  versão do RTR quando uma sessão abre), então dê a ele dez ou quinze
  segundos para se acomodar antes de tirar conclusões do que ele mostra.
- **O AS666 e o peer.** Todo comando `stepN-*` também define o estado
  deles - silêncio, sequestro ingênuo, caminho forjado, vazamento - conforme
  o texto do roteiro para aquele passo descreve, mesmo os comandos cujo nome
  não os menciona (`step6-add-provider-b` e `step8-drop`, por exemplo,
  continuam colocando o AS666 de volta na forma de caminho forjado, já
  que é isso que esses passos esperam).
- **Os objetos RPKI da origem**, no Krill: as ROAs (criadas uma vez, a partir
  do `step3-rov-mark`) e o objeto ASPA, mantido exatamente na lista que cada
  passo espera - `krillc aspas add` substitui o objeto inteiro, então um
  comando pode fazê-lo crescer (Passo 6) ou encolher de volta (pulando para
  o Passo 5 depois que o Passo 6 rodou) com a mesma facilidade.

  Este também é o único lugar em que um comando `stepN-*` pode falhar sem
  culpa sua: a partir do `step3-rov-mark`, cada um começa conferindo se a
  Preparação realmente terminou - a CA existe, tem um pai ativo, tem o
  número de AS e os prefixos do `lab.conf`, e tem um repositório
  funcionando. Se não tiver, o comando para e avisa, em vez de criar ROAs
  silenciosamente que o Krill não consegue de fato publicar. A Preparação é
  a única parte da história que um comando `stepN-*` não pode fazer por
  você.

Os nomes de todos esses comandos carregam o número do passo a que pertencem.

---

## Preparação 1: subir o laboratório

O laboratório tem dois modos, escolhidos com a variável `MODE` no `lab.conf`:

| MODE | Quem certifica | Precisa de Internet? |
|---|---|---|
| `local` | o **LabNIC**, um registro simulado que roda dentro do laboratório | não |
| `beta` | o **beta.registro.br**, o sistema de testes do Registro.br | sim, e de um login no beta.registro.br |

Os dois modos usam exatamente os mesmos protocolos: RFC 6492 para a
delegação, RFC 8181 para a publicação. O que muda é o painel onde você cola
o XML e o tempo que os objetos levam para aparecer no validador - segundos
no modo local, alguns minutos no beta. O próximo passo de preparação tem uma
versão para cada modo; faça só a que corresponde ao seu.

1. Requisitos: Docker instalado (Mac, Windows ou Linux - **OrbStack**,
   Docker Desktop ou Docker Engine) e acesso à Internet.

2. No terminal, dentro da pasta do laboratório:

   ```
   #./scripts/lab.sh up
   ```

   Na primeira vez, o Docker baixa as imagens e constrói algumas locais.
   Leva alguns minutos.

3. Abra o painel do laboratório:

   **http://localhost:8080**

   Clicar em cada caixa da topologia abre o terminal daquele componente, a sua
   interface web e as suas informações de endereçamento.

   **Onde digitar os comandos deste roteiro.** Tudo pode ser feito sem sair
   do navegador, e cada bloco de comandos mostra as duas formas:

   - **No painel (a forma escrita primeiro nos blocos).** Clique numa caixa
     e use o botão **Shell** dela (**Terminal (krillc)** no Krill): você cai
     dentro daquele contêiner, então o comando é escrito sem nenhum prefixo,
     por exemplo `birdc show protocols` no Shell do observer1. O botão
     **Comandos do laboratório** abre um terminal já na pasta do
     laboratório, para `./scripts/lab.sh ...`, `cat bird/...` e `diff ...`.
   - **No terminal do seu próprio computador, na pasta do laboratório.** O
     mesmo comando, rodado de fora: `docker exec lab-<box> <command>`, como
     em `docker exec lab-observer1 birdc show protocols`. Use esta se
     preferir o seu próprio terminal, ou para o `reset`, que nunca deve
     rodar pelo painel.

4. Confira se os roteadores subiram e se as sessões BGP estão estabelecidas.
   No painel, a pílula de cada roteador mostra quantas das suas sessões BGP estão
   no ar. Para ver o detalhe:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc show protocols
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show summary
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc show protocols
   #docker exec lab-observer2 bgpctl show summary
   ```

   Você deve ver `provider_a_v4`, `provider_a_v6`, `provider_b_v4` e
   `provider_b_v6` em `Established` no observer1, mais `attacker_v4` e
   `attacker_v6`, as sessões com o AS666, que está no ar mas em
   silêncio por enquanto. O observer2 lista as mesmas seis sessões. Ainda não
   há protocolo `routinator`: os observadores não validam nada até o Passo 3.

---

## Preparação 2: certificar seus recursos (MODE=local)

> Faça isto se o `lab.conf` tiver `MODE=local`. Se tiver `MODE=beta`, pule para
> a Preparação 2-B.

Aqui você vai fazer **os dois lados** da conversa: o titular, no Krill, e o
registro, no painel do LabNIC. É a mesma troca de XML que acontece
entre um provedor e o seu RIR.

### O seu lado: a CA no Krill

1. Abra o Krill: **http://krill.localhost:8080**

   (Ele é servido pelo servidor web do laboratório, então não há aviso de
   certificado. O endereço direto, `https://localhost:3000`, continua
   funcionando, com um certificado autoassinado.)

2. Entre com o token **`labpass`**.

3. Crie a sua CA chamada **`acme_ca`**.
   Se quiser, troque o idioma para inglês no canto superior direito.

### O lado do registro: o painel do LabNIC

4. Em outra aba, abra o painel do registro: **http://registry.localhost:8080**

   Repare na seção *Allocated resources*: são exatamente o ASN e os blocos
   do seu `lab.conf`. O certificado que o registro está prestes a emitir
   cobre esse conjunto, nem mais, nem menos.

### Parte 1: delegação da CA (RFC 6492)

5. No Krill, vá em *Parent CAs* → *Add a new parent CA* e copie o XML do
   campo *Child Request* (o `child_request`).

6. No painel do LabNIC, cole esse XML no **Step 1** e clique em
   *Issue certificate*.

7. O registro devolve o `parent_response`. Copie-o.

8. De volta ao Krill, em *Parent CAs* → *Parent Response*, cole o XML. No
   campo *Parent CA name* use **`labnic`** e confirme.

### Parte 2: serviço de publicação (RFC 8181)

9. No Krill, vá em *Repository* → *Add a repository* e copie o XML do
   *Publisher Request* (o `publisher_request`).

10. No painel do LabNIC, cole-o no **Step 2** e clique em *Authorize publication*.

11. Copie o `repository_response` que aparece e cole-o no Krill,
    em *Repository* → *Repository Response*. Confirme.

### Conferindo

12. No Krill, a CA deve mostrar os recursos recebidos do pai: o
    ASN 64500 e os prefixos 203.0.113.0/24 e 3fff:cafe::/32.

13. No painel do LabNIC, a seção *Delegated RPKI* agora mostra **active**,
    com a data da última troca Up-Down e a contagem de objetos no
    repositório.

> **Por que duas partes separadas?** Porque são duas coisas independentes. A
> primeira diz *quais recursos são seus*; a segunda diz *onde você vai
> publicar os objetos assinados*. Um RIR pode certificar os seus recursos
> enquanto você publica em outro lugar, inclusive no seu próprio servidor de
> publicação.

**Repare no que você *não* fez:** criar uma ROA ou um objeto ASPA. Os seus
recursos estão certificados, mas nada diz quem pode anunciá-los. É aí que a
história começa.

---

## Preparação 2-B: certificar seus recursos (MODE=beta)

> Faça isto somente se o `lab.conf` tiver `MODE=beta`. Precisa de acesso à Internet e de um
> login no beta.registro.br.

1. Abra o Krill em **http://krill.localhost:8080**, entre com o token
   **`labpass`** e crie a CA **`acme_ca`**.

2. Em outra aba, entre em **https://beta.registro.br/login/**. No
   Painel, vá em *Holdership*, selecione o AS e role até a seção **RPKI**
   → *Configure RPKI*.

3. No Krill, em *Parent CAs* → *Add a new parent CA*, copie o XML do
   campo *Child Request* e cole-o no campo indicado no
   Registro.br.

4. Em caso de sucesso, aparece "RPKI enabled successfully!", junto com um
   campo **Parent response**. Copie o XML e cole-o no Krill, em
   *Parent CAs* → *Parent Response*, com o nome da CA pai
   **`nicbr_ca`**.

5. Ainda no Registro.br, em *Configure RPKI* → *Configure remote publication*.
   No Krill, em *Repository* → *Add a repository*, copie o *Publisher
   Request* e cole-o lá.

6. O campo se transforma em **Repository response**. Copie-o e cole-o no
   Krill, em *Repository* → *Repository Response*.

7. No fim, o Krill deve mostrar os recursos recebidos do pai.

**Repare no que você *não* fez:** criar uma ROA ou um objeto ASPA. Os seus
recursos estão certificados, mas nada diz quem pode anunciá-los. É aí que a
história começa. (No beta, os objetos levam alguns minutos para chegar aos
validadores sempre que um passo pedir que você crie um - conte com isso.)

---

## Passo 1: uma linha de base limpa

> **Estado:** estágio `none` (sem validação) · AS666 em silêncio · peer em silêncio · sem ROAs,
> sem ASPA.
>
> **Se o seu for diferente:** `./scripts/lab.sh step1-clean` silencia o AS666 e o
> peer *e* coloca os dois observadores de volta em BGP puro. Se sobraram ROAs ou um objeto ASPA
> de uma execução anterior (confira com `krillc roas list` e `krillc
> aspas list` no terminal do Krill), o jeito mais simples de sair é
> `./scripts/lab.sh reset`, depois `up`, depois a Preparação 2 de novo - rodado do
> terminal do seu próprio computador, não do painel.

1. Garanta que o laboratório está na linha de base:

   ```
   #./scripts/lab.sh step1-clean
   ```

2. Confira se o prefixo da origem chega aos dois observadores pelos dois
   provedores, e qual deles eles preferem:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   203.0.113.0/24  unicast [provider_b_v4 ...] * (100) [AS64500i]
        bgp_path: 64502 64500
        bgp_local_pref: 100

                unicast [provider_a_v4 ...] (100) [AS64500i]
        bgp_path: 64501 64500 64500 64500
        bgp_local_pref: 100
   ```

   ```
   flags  vs destination          gateway          lpref   med aspath origin
   *>    N-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     N-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   ```

   Dois caminhos em cada observador: `64502 64500` (o
   selecionado, a entrada preferida da origem, 2 saltos) e
   `64501 64500 64500 64500` (o backup,
   mantido na tabela mas com 4 saltos por causa dos prepends). Nenhum dos
   dois tem veredito (o BIRD não tem communities; o `N-?` do OpenBGPD é só
   "nada para comparar", e o painel mostra `-` para os dois), porque **os
   observadores ainda não estão validando nada.** O selo no cabeçalho do
   painel diz *validação: nenhuma*.

3. **Dê uma olhada em como esses roteadores estão configurados.** Abra os
   arquivos de linha de base dos observadores (no terminal de Comandos do laboratório, no seu próprio terminal na
   pasta do laboratório, ou no seu editor):

   ```
   #cat bird/observer1-none.conf
   #cat openbgpd/observer2-none.conf
   ```

   Você vai encontrar BGP comum: sessões com os dois provedores (e com o
   AS666, calado por enquanto), e uma política que aceita tudo:

   ```
   template bgp CUSTOMER4 {
       local as OBSERVER1_ASN;
       ipv4 {
           import all;                 # <- BIRD: aceita o que o vizinho enviar
           export none;
           import table on;
       };
   }
   ```

   ```
   deny from any
   allow from any                      # <- OpenBGPD: mesma ideia
   ```

   Não há sessão RTR com o Routinator nem com o FORT (os dois estão
   rodando, mas ninguém os escuta), e nada que saiba distinguir uma ROA de
   um buraco na parede. Tudo o que a história faz com esses dois arquivos,
   daqui em diante, é *implantar validação RPKI* num roteador.

**No caminho:** os validadores, a CA e o repositório já existem, e os
recursos estão certificados. Mesmo assim, do ponto de vista de um roteador,
nada disso importa até que alguém diga a ele para escutar.

---

## Passo 2: o sequestro ingênuo

> **Estado:** estágio `none` · AS666 em silêncio (prestes a mudar) · peer em silêncio · sem
> ROAs, sem ASPA.
>
> **Se o seu for diferente:** `./scripts/lab.sh step1-clean`.

O AS666 anuncia o prefixo da origem como se fosse dele.

1. Ligue-o:

   ```
   #./scripts/lab.sh step2-hijack-simple
   ```

2. **Antes de olhar:** o caminho do AS666 é apenas `666`, mais
   curto que o legítimo `64502 64500` (e que o backup por
   A). Qual você espera que os observadores prefiram? E existe *alguma
   coisa* que eles possam usar para distinguir os dois?

3. Agora olhe:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   203.0.113.0/24  unicast [attacker_v4 ...] * (100) [AS666i]
        bgp_path: 666
        bgp_local_pref: 100
   ```

   ```
   *>    N-? 203.0.113.0/24          10.200.8.10       100     0 666 i
   *     N-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     N-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   ```

   O sequestro **venceu**: é a rota selecionada (`*`, `*>`) nos dois
   observadores. O AS_PATH dele é mais curto (1 salto contra 2 e 4), e nada
   mais o distingue. No painel, a pílula do atacante mostra *sequestrando* e
   os seus links para os observadores ficam **âmbar**: um observador está
   aceitando o que ele anuncia. A tabela de *Vereditos* ganha novas linhas
   rotuladas *AS666*, sem vereditos, porque ainda não há validação.

**No caminho:** um sequestro com o ASN de origem errado. O truque mais
antigo que existe, e o motivo pelo qual as ROAs foram inventadas.

---

## Passo 3: o ROV entra, marcando o que parece errado

> **Estado:** estágio `none` (prestes a mudar) · AS666 fazendo o sequestro ingênuo ·
> peer em silêncio · ainda sem ROAs (você vai criá-las aqui), sem ASPA.
>
> **Se o seu for diferente:** `./scripts/lab.sh step1-clean`, depois
> `./scripts/lab.sh step2-hijack-simple`.

Este passo tem duas metades, nesta ordem: a **Origem publica** as ROAs, e os
**Observadores validam** - só marcando, por enquanto.

### A Origem publica: crie as ROAs

> **Espere a CA receber o seu certificado antes de criar ROAs.** Logo depois
> da preparação, a CA pode ainda não ter a classe de recursos do pai, e o
> Krill aceita o comando sem criar nada. Confira em *ROAs* se o Krill já
> mostra os seus prefixos; se a lista estiver vazia, espere alguns segundos
> ou rode `docker exec lab-krill krillc bulk refresh`.

1. No Krill, vá à seção **ROAs** e clique em *Add ROA*.

2. Crie a ROA IPv4:

   | campo | valor |
   |---|---|
   | ASN | 64500 |
   | Prefix | 203.0.113.0/24 |
   | Max length | 24 |

3. Crie a ROA IPv6:

   | campo | valor |
   |---|---|
   | ASN | 64500 |
   | Prefix | 3fff:cafe::/32 |
   | Max length | 32 |

   (Prefere a linha de comando? No terminal da caixa do Krill:
   `krillc roas update --add "203.0.113.0/24-24 => 64500"`, e o mesmo com
   `"3fff:cafe::/32-32 => 64500"`. Se o Krill disser que uma ROA é *duplicate*,
   ela já está lá.)

4. Faça os validadores as pegarem, e confira que pegaram:

   ```
   #./scripts/lab.sh refresh
   #./scripts/validate.sh
   ```

   O `validate.sh` imprime o que o Routinator validou (duas ROAs). No
   painel, as caixas do Routinator e do FORT mostram `2 VRP`. Se ainda não
   aparecer nada, **é questão de tempo**: o Krill precisa publicar e os
   validadores precisam reler (segundos no modo local, minutos no beta) -
   rode `refresh` de novo.

Por enquanto nada mudou para os roteadores: as ROAs estão publicadas e
validadas, mas **nenhum roteador está escutando os validadores.** Olhe os
observadores de novo se quiser - o sequestro ainda está vencendo.

### Os Observadores validam

1. Implante o ROV nos dois observadores, na sua primeira forma segura:

   ```
   #./scripts/lab.sh step3-rov-mark
   ```

2. **Veja do que é feita esta implantação.** Compare os novos arquivos com a
   linha de base que você leu no Passo 1 (o `diff` mostra exatamente o que foi acrescentado):

   ```
   #diff bird/observer1-none.conf bird/observer1-rov-mark.conf
   #diff openbgpd/observer2-none.conf openbgpd/observer2-rov-mark.conf
   ```

   Três ideias, presentes nos dois roteadores:

   **(a) Uma sessão com um validador**, pela qual o roteador aprende as ROAs:

   ```
   protocol rpki routinator {                      # observer1 (BIRD)
       remote 172.30.0.20 port 3323;
       roa4 { table roa4_table; };
       roa6 { table roa6_table; };
       ...
   }
   ```

   ```
   rtr 172.30.0.50 {                               # observer2 (OpenBGPD)
       port 3323
   }
   ```

   **(b) Um teste em cada rota**, comparando o seu AS de origem (o *último*
   AS no caminho) e o prefixo com as ROAs. O BIRD calcula isso no filtro de
   importação e registra o resultado numa large community, para você poder
   lê-lo depois; o OpenBGPD calcula nativamente, no atributo `ovs` da rota:

   ```
   filter import_customer_v4 {                     # observer1 (BIRD)
       if roa_check(roa4_table, net, bgp_path.last) = ROA_INVALID then {
           bgp_large_community.add((OBSERVER1_ASN,1,0));
           bgp_local_pref = 10;                    # <- (c) uma ação: perde para qualquer rota válida
       } else if roa_check(roa4_table, net, bgp_path.last) = ROA_VALID then
           bgp_large_community.add((OBSERVER1_ASN,1,2));
       else
           bgp_large_community.add((OBSERVER1_ASN,1,1));
       accept;
   }
   ```

   **(c) Uma ação sobre o resultado.** Neste estágio a ação é só *reduzir a
   preferência* de uma rota inválida - nada é rejeitado ainda:

   ```
   match from any ovs invalid    set { localpref 10 }      # observer2 (OpenBGPD)
   ```

   > **Isso não é coisa de BIRD ou de OpenBGPD.** Qualquer roteador que
   > suporte ROV tem as mesmas três peças, com sintaxe diferente: uma sessão
   > com um validador (RTR), uma política que casa com o estado de
   > validação, e uma ação. No Cisco IOS XR é uma `route-policy` testando
   > `validation-state`; no Junos, um `policy-statement` casando com
   > `validation-database`; na Huawei, `if-match rpki` numa route-policy -
   > consulte a documentação da sua plataforma para a sintaxe exata. O BIRD
   > e o OpenBGPD aparecem aqui porque são livres e fáceis de rodar em
   > contêineres, não porque sejam o que você vai encontrar no trabalho. O
   > que vale em qualquer lugar é a anatomia.
   >
   > Prefere digitar a configuração a lê-la? Parta de
   > `bird/observer1-none.conf`, acrescente as peças acima, salve o
   > resultado como um novo arquivo em `bird/`, e carregue-o com `docker
   > exec lab-observer1 birdc 'configure "/etc/bird-lab/your-file.conf"'`. O
   > script só poupa a digitação.

3. Agora olhe as rotas de novo:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   203.0.113.0/24  unicast [attacker_v4 ...] (100) [AS666i]
        bgp_path: 666
        bgp_local_pref: 10
        bgp_large_community: (64510, 1, 0)                   <- ROV Invalid
   ```

   ```
   *>    V-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     V-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   *     !-? 203.0.113.0/24          10.200.8.10        10     0 666 i
   ```

   O sequestro ainda está na tabela, visível, não sumiu, mas agora carrega
   **ROV Invalid** e um `local_pref` de 10, então perde para os caminhos
   legítimos, e o do Provedor B volta a ser a rota selecionada. O selo no
   cabeçalho diz *ROV: marcando*, e os links do atacante ficam
   **vermelhos**: ele está anunciando, e os dois observadores estão
   sinalizando isso. Tudo o que você precisava conferir está certo: o
   sequestro está sinalizado, os caminhos legítimos são `Valid`, e nada
   legítimo foi prejudicado. **Esse é o ponto do estágio de marcação** - ver
   o que a verificação *faria* antes de deixá-la rejeitar qualquer coisa.

   **É aqui que o ROV fica pelo resto da história: marcando, não
   descartando.** Um roteador que só marca ainda usa uma rota inválida
   sempre que ela é o melhor que ele tem, então marcar sozinho não é o fim
   do trabalho. É o ensaio. Você vai ver como é o descarte de verdade, de
   produção, para o ROV e o ASPA juntos, no Passo 8, depois que as duas
   verificações tiverem tido a sua vez de se provar assim.

### Como ler os vereditos

Os dois observadores os mostram de formas diferentes:

- **observer1 (BIRD)** não tem atributo de validação por rota, então os seus
  filtros registram cada veredito numa large community:

  | community | significado | | community | significado |
  |---|---|---|---|---|
  | (64510,1,0) | ROV Invalid | | (64510,2,0) | ASPA Invalid |
  | (64510,1,1) | ROV NotFound | | (64510,2,1) | ASPA Unknown |
  | (64510,1,2) | ROV Valid | | (64510,2,2) | ASPA Valid |

- **observer2 (OpenBGPD)** calcula os dois nativamente. A coluna `vs` é o
  par **ovs-avs**: estado da validação de origem, depois estado da
  validação ASPA, cada um `V` (valid), `!` (invalid) ou `N`/`?`
  (not-found / unknown). Então `V-!` é ROV Valid e ASPA Invalid. (Nenhuma
  verificação ASPA está implantada ainda, então a segunda metade é `?` por
  enquanto.)

**No caminho:** do que é feito "implantar o ROV" (uma sessão RTR, um teste
em cada rota, uma ação sobre o resultado) e como novos objetos chegam aos
roteadores: o Krill publica, os validadores relêem, os roteadores recebem a
mudança por RTR. Você acabou de ver cada salto.

---

## Passo 4: o caminho forjado

> **Estado:** estágio `rov-mark` · AS666 fazendo o sequestro ingênuo (marcado
> inválido, perdendo) · peer em silêncio · ROAs para os dois prefixos · sem ASPA.
>
> **Se o seu for diferente:** `./scripts/lab.sh step4-hijack-posrov` - ele
> também garante que as ROAs existem e coloca os observadores de volta em
> `rov-mark`.

O AS666 lê a mesma documentação que você. O ROV só olha o
**último** AS do caminho. Então, e se o último AS fosse o certo?

1. Passe o AS666 para o ataque de caminho forjado:

   ```
   #./scripts/lab.sh step4-hijack-posrov
   ```

   O AS666 agora anuncia o caminho `666 64500`, como se
   tivesse recebido o prefixo diretamente da origem verdadeira.

   **Essa relação é mentira.** O AS666 não tem sessão BGP nenhuma com
   o AS64500 - nem peering, nem trânsito, nada. Os dois nem estão
   conectados. A adjacência `666 64500` existe só porque a
   configuração do AS666 a *escreve no caminho*. Veja como:

   ```
   # Painel: clique na caixa attacker e depois em Shell:
   #cat /etc/bird.conf
   # Ou, no terminal do seu computador:
   #cat bird/attacker-posrov.conf
   ```

   Ache os filtros `forge_export`: `bgp_path.prepend(ORIGIN_ASN)` põe o
   número da origem no caminho *antes* de o roteador acrescentar o seu
   próprio na exportação. É essa a forjaria inteira. Compare com
   `bird/attacker-simple.conf` (sem filtro, então o caminho é só
   `666`), e confira que nenhum dos dois arquivos tem uma sessão
   com a origem: só com os dois observadores.

2. **Antes de olhar:** os observadores estão descartando tudo o que o ROV
   sinaliza como inválido. Isto vai ser descartado?

3. Olhe:

   ```
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   flags  vs destination          gateway          lpref   med aspath origin
   *>    V-? 203.0.113.0/24          10.200.8.10       100     0 666 64500 i
   *m    V-? 203.0.113.0/24          10.200.6.10       100     0 64502 64500 i
   *     V-? 203.0.113.0/24          10.200.5.10       100     0 64501 64500 64500 64500 i
   ```

   A rota forjada está **de volta**, e é a selecionada. O ROV diz `Valid` -
   o caminho termina em 64500, exatamente o que a ROA autoriza. Os
   links do atacante no painel ficam **âmbar** de novo. Três caminhos,
   todos "válidos", um deles uma mentira, e *nada do que você implantou até
   agora sabe dizer qual*.

   > O caminho forjado (`666 64500`, 2 saltos) empata com
   > o do Provedor B (`64502 64500`, também 2), e o
   > atacante ganha o empate por um critério de desempate (o router ID dele
   > por acaso é o menor); o backup do Provedor A tem 4 saltos e nem entra
   > na disputa. Isso é secundário: o ponto é que o ROV lhe entregou três
   > rotas igualmente válidas na aparência, e nenhum jeito de escolher
   > entre elas.

**No caminho:** a validação de origem consegue distinguir dois caminhos para
o mesmo prefixo, quando a origem é a mesma e uma ROA casa? Agora você sabe:
não consegue. Ela só olha o último AS.

---

## Passo 5: o ASPA entra, também marcando primeiro

> **Estado:** estágio `rov-mark` · AS666 forjando o caminho · peer em silêncio · ROAs para
> os dois prefixos · ainda sem ASPA (você vai criá-lo aqui).
>
> **Se o seu for diferente:** `./scripts/lab.sh step3-rov-mark` e
> `./scripts/lab.sh step4-hijack-posrov`; se um objeto ASPA já existir,
> `krillc aspas remove --customer AS64500` no terminal do Krill.

Mesmo formato do Passo 3: a **Origem publica** um objeto ASPA, depois os
**Observadores validam**, na mesma forma segura, só marcando, que o ROV usou.

### A Origem publica: crie o objeto ASPA

O Krill 0.16 ainda **não** tem ASPA na interface web. Por enquanto é
gerenciado pela linha de comando (a interface está a caminho na próxima
versão).

1. No painel, clique na caixa do **Krill** e depois no botão **Terminal (krillc)**.
   (Ou, do seu próprio terminal: `docker exec -it lab-krill bash`.)

2. Veja que ainda não há ASPA:

   ```
   #krillc aspas list
   ```

3. Crie o objeto ASPA declarando quais provedores podem propagar rotas do
   AS64500. Por causa da história, liste **só o Provedor A** por
   enquanto - você vai ver por quê no próximo passo:

   ```
   #krillc aspas add --aspa "AS64500 => AS64501"
   ```

4. Confira, e faça os validadores o pegarem:

   ```
   #krillc aspas list
   #./scripts/lab.sh refresh
   ```

> **Sobre a notação.** A sintaxe do Krill aceita uma restrição por família
> de endereços (`AS64501(v4)`), mas a versão final do perfil
> ASPA no IETF **removeu** essa opção: um único objeto ASPA vale para IPv4
> e IPv6 ao mesmo tempo. Não use os qualificadores `(v4)`/`(v6)`.
>
> **Um objeto por AS cliente.** A RFC exige exatamente um objeto ASPA por
> ASN cliente, listando *todos* os provedores. O `krillc aspas add`
> substitui o objeto inteiro (então é seguro repetir); para mudar a lista,
> use `krillc aspas update`.
>
> **Cuidado com uma flag.** Sem `--enable-aspa`, o Routinator simplesmente
> ignora objetos ASPA. É o erro número um ao montar um laboratório como
> este - aqui ela já está ligada.

Como com as ROAs, nada muda ainda para os roteadores: o objeto está
publicado, e nenhum roteador está verificando caminhos.

### Os Observadores validam

1. Implante a verificação ASPA nos dois observadores - o ROV continua só
   marcando:

   ```
   #./scripts/lab.sh step5-aspa-mark
   ```

2. **Compare com o estágio que você acabou de deixar** (`rov-mark`):

   ```
   #diff bird/observer1-rov-mark.conf bird/observer1-aspa-mark.conf
   #diff openbgpd/observer2-rov-mark.conf openbgpd/observer2-aspa-mark.conf
   ```

   As mesmas três ideias, desta vez aplicadas a caminhos:

   **(a) O validador agora também entrega objetos ASPA.** O ASPA só viaja
   na versão 2 do RTR, então cada roteador o pede:

   ```
   aspa table aspa_table;                          # observer1 (BIRD)
   protocol rpki routinator {
       ...
       aspa { table aspa_table; };                 # ASPA só existe na versão 2 do RTR
   }
   ```

   ```
   rtr 172.30.0.50 {                               # observer2 (OpenBGPD)
       port 3323
       min-version 2                               # sem isso, nenhum ASPA chega
   }
   ```

   **(b) Um teste em cada caminho**, e **(c) uma ação sobre o resultado** - neste
   estágio, só marcando:

   ```
   case aspa_check_upstream(aspa_table) {          # observer1 (BIRD)
       ASPA_INVALID: {
           bgp_large_community.add((OBSERVER1_ASN,2,0));
           bgp_local_pref = 20;                    # perde para um caminho válido
       }
       ASPA_VALID: {
           bgp_large_community.add((OBSERVER1_ASN,2,2));
           bgp_local_pref = 200;                   # prefere um caminho comprovado
       }
       ASPA_UNKNOWN: bgp_large_community.add((OBSERVER1_ASN,2,1));
   }
   ```

   ```
   neighbor 10.200.5.10 {                          # observer2 (OpenBGPD)
       remote-as $provider_a_asn
       role provider                               # <- o que liga a verificação ASPA
   }
   ...
   match from any avs invalid    set { localpref 20 }      # perde para um caminho válido
   match from any avs valid      set { localpref 200 }     # prefere um caminho comprovado
   ```

   > **Por que "upstream"?** O observador trata cada vizinho como um
   > *cliente*: para rotas vindas de um cliente, aplica-se o algoritmo mais
   > estrito, em que todo salto do caminho tem que ser um par
   > cliente→provedor autorizado. O BIRD pede isso pelo nome
   > (`aspa_check_upstream`); o OpenBGPD seleciona pelo papel da RFC 9234 da
   > sessão. É também a verificação que pega vazamentos de rota - você vai
   > conhecer um no Passo 7. O exercício extra A desmonta isso, e mostra o
   > que muda se você pedir o algoritmo *downstream*.
   >
   > A verificação ASPA é mais nova que o ROV, e o suporte em plataformas
   > comerciais ainda está chegando. Onde existe, tem a mesma anatomia da
   > implantação do ROV que você viu no Passo 3.

3. Olhe as rotas:

   ```
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.5.10       200     0 64501 64500 64500 64500 i
   *     V-! 203.0.113.0/24          10.200.8.10        20     0 666 64500 i
   *     V-! 203.0.113.0/24          10.200.6.10        20     0 64502 64500 i
   ```

   O caminho forjado agora é **ASPA Invalid**: o salto `64500 →
   666` não está autorizado, já que só 64501 está
   listado. Ele ainda é visível, mas com `local_pref` 20 perde para o
   caminho do Provedor A (`V-V`, 200). Os links do atacante ficam
   **vermelhos** de novo, e o selo diz *ROV: marcando · ASPA: marcando*.

   Duas rotas carregam `V-!`, porém, não uma. Olhe com atenção para a
   segunda: é o **Provedor B**, o caminho de entrada preferido da própria
   origem, fruto da engenharia de tráfego do Passo 1. O objeto ASPA que
   você acabou de criar só lista o Provedor A, então o ASPA também chama de
   inválido o caminho do Provedor B, e o que acabou sendo selecionado no
   lugar dele foi o caminho do Provedor A, o *backup*, o mesmo que a origem
   deliberadamente alongou com os prepends. Como nada é descartado ainda,
   você consegue ver esse erro antes que ele custe alguma coisa. Guarde
   esse pensamento para o próximo passo.

**No caminho:** o veredito ASPA que o ROV nunca poderia dar - o caminho em
si é o que está errado, mesmo com a origem certa - e um lembrete de por que
marcar roda antes de descartar: foi o que deixou você pegar um erro no seu
próprio objeto ASPA antes que ele derrubasse alguma coisa.

---

## Passo 6: você esqueceu um provedor

> **Estado:** estágio `aspa-mark` · AS666 forjando o caminho · peer em silêncio · ROAs para
> os dois prefixos · ASPA listando apenas o Provedor A.
>
> **Se o seu for diferente:** `./scripts/lab.sh step5-aspa-mark`, e no terminal
> do Krill `krillc aspas add --aspa "AS64500 => AS64501"` (isso substitui o
> objeto exatamente por essa lista), depois `./scripts/lab.sh refresh`.

A rota que você notou no fim do último passo, a do Provedor B, marcada ASPA
Invalid junto com a forjada, é um caminho *legítimo* - **justamente o que a
origem prefere** - rebaixado sem motivo melhor que um objeto incompleto. Os
observadores ficam com o caminho de backup, o mesmo que a origem
deliberadamente alongou com os prepends: a engenharia de tráfego da origem,
desfeita por um ASPA incompleto. Quando este estágio passar a descartar em
vez de marcar (Passo 8), é aí que o tráfego que costumava chegar por aquela
interface para de chegar, e alguém começa a perguntar por quê. (Este
laboratório não tem plano de dados, então você não vê o tráfego parar de
fato; você vê a preferência da rota desabar, que é a mesma coisa dita de
outro jeito.)

1. Conserte o objeto:

   ```
   #krillc aspas update --customer AS64500 --add "AS64502"
   #krillc aspas list
   #./scripts/lab.sh refresh
   ```

2. Confira os observadores:

   ```
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.6.10       200     0 64502 64500 i
   *     V-V 203.0.113.0/24          10.200.5.10       200     0 64501 64500 64500 64500 i
   *     V-! 203.0.113.0/24          10.200.8.10        20     0 666 64500 i
   ```

   Os dois caminhos legítimos voltaram para `V-V` e `local_pref` 200, e o
   Provedor B, a entrada preferida da origem, é reselecionado: uma vez
   empatados na preferência, vence o caminho mais curto. O forjado continua
   rebaixado (`V-!`, 20), e o AS666, ainda anunciando, continua
   derrotado. Repare como o conserto não envolveu o AS666 em nada:
   o objeto ASPA descreve as *suas* relações, e tudo o que as contradiz
   perde.

   (`./scripts/lab.sh step6-add-provider-b` faz exatamente esse conserto. É
   o comando para pular direto para o estado deste passo mais tarde, de
   qualquer ponto da história, sem digitar o comando `krillc` de novo à
   mão.)

3. O BIRD pegou a mudança sozinho, sem ninguém tocar no roteador,
   porque as suas sessões são configuradas com `import table on` e `rpki reload
   on`. Para forçar a revalidação à mão:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc reload in provider_b_v4
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc reload in provider_b_v4
   ```

**No caminho:** o que acontece quando um objeto ASPA esquece um provedor de
verdade (metade da Internet passa a ver as rotas daquele provedor como
inválidas), e como uma correção se propaga: republicar, revalidar, nenhum
roteador tocado.

Deixe o AS666 rodando. Ele é inofensivo agora, e serve de lembrete
útil no painel do que está sendo mantido de fora.

---

## Passo 7: o peer vaza (e o ASPA pega o que o ROV não pega)

> **Estado:** estágio `aspa-mark` · AS666 forjando o caminho (marcado, perdendo) · peer
> em silêncio · ROAs para os dois prefixos · ASPA listando os Provedores A e B.
>
> **Se o seu for diferente:** `./scripts/lab.sh step6-add-provider-b` - ele
> monta tudo o que este passo precisa (ASPA listando os dois provedores, peer
> em silêncio) sem o vazamento.

Este não é ataque de ninguém. O peer, uma rede legítima, tem um link de
peering privado com a origem, então ele *aprende* os prefixos da origem. Um
link de peering é bilateral: o que o peer aprende ali não é para repassar ao
provedor dele. Então alguém edita uma configuração...

1. Ligue o vazamento:

   ```
   #./scripts/lab.sh step7-leak-on
   ```

   O peer agora reanuncia ao Provedor A o que aprendeu da origem. Nada é
   forjado - o peer está dizendo a verdade sobre de onde a rota veio. No
   painel, a pílula do peer mostra *vazando*.

2. **Antes de olhar:** o Provedor A agora tem duas rotas para o prefixo da
   origem, a da própria origem e a do peer. Qual delas o Provedor A repassa
   aos observadores? E, uma vez que ela chega, marcando apenas o que
   parece inválido, você vai conseguir vê-la?

3. Olhe primeiro o Provedor A:

   ```
   # Painel: clique na caixa provider-a e depois em Shell:
   #birdc show route 203.0.113.0/24 all
   # Ou, no terminal do seu computador:
   #docker exec lab-provider-a birdc show route 203.0.113.0/24 all
   ```

   ```
   203.0.113.0/24  unicast [customer_peer_v4 ...] * (100) [AS64500i]
        bgp_path: 64499 64500
        bgp_local_pref: 100
                unicast [customer_v4 ...] (100) [AS64500i]
        bgp_path: 64500 64500 64500
        bgp_local_pref: 100
   ```

   O Provedor A só repassa a sua *melhor* rota, e nada de especial foi
   configurado para a do peer vencer: ela é simplesmente **mais curta**, 2
   saltos contra os 3 da própria origem. Os prepends que fizeram do
   Provedor A o *backup* também tornaram irresistível um vazamento por ele.
   (Isso é típico: uma rota vazada vence porque a engenharia de tráfego de
   alguém fez o caminho honesto parecer pior. Veja `bird/provider-a.conf` -
   lá não há política nenhuma.)

4. Agora os observadores:

   ```
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.6.10       200     0 64502 64500 i
   *     V-! 203.0.113.0/24          10.200.8.10        20     0 666 64500 i
   *     V-! 203.0.113.0/24          10.200.5.10        20     0 64501 64499 64500 i
   ```

   **O caminho próprio do Provedor A já sumiu.** Ele parou de anunciá-lo no
   momento em que escolheu o caminho mais curto do peer como melhor, e
   isso não tem nada a ver com o que os observadores fazem com o que
   recebem. O que chega do Provedor A em vez disso é o caminho vazado,
   `64501 64499 64500`, e como marcar nunca remove
   nada da tabela, você consegue olhar direto para ele. Duas coisas a
   notar:

   - **ROV Valid.** Claro, a origem realmente é 64500. Nada é
     forjado. *Um vazamento nunca pode ser pego pelo ROV*: ele não mente
     sobre quem originou o prefixo, mente sobre o *formato do caminho*.
   - **ASPA Invalid.** O salto `64500 → 64499` nunca foi
     autorizado: o objeto ASPA da origem lista os Provedores A e B, e o
     peer não é nenhum dos dois.

   O link do peer no painel fica **vermelho**. O caminho do Provedor B
   continua sendo o selecionado (`V-V`, 200) - não precisa de nenhuma ajuda
   do ASPA para vencer, já que também é o mais curto - mas o estrago é
   real: a origem perdeu o seu *backup*, e os outros clientes do Provedor A
   agora estão mandando o tráfego deles para a origem através do peer.

**No caminho:** um vazamento de rota não é ninguém forjando nada. É uma rota
cruzando uma fronteira que ela nunca deveria cruzar, e é um veredito que o
ROV estruturalmente não consegue dar, porque a origem no fim do caminho está
dizendo a verdade. O ASPA pega isso pelo mesmo motivo que pegou a forjadura
do Passo 4: um salto não autorizado, esteja onde estiver no caminho.

---

## Passo 8: implantando de verdade, descartar

> **Estado:** estágio `aspa-mark` · AS666 forjando o caminho (marcado, perdendo) · o peer
> vazando (marcado, perdendo) · ROAs para os dois prefixos · ASPA listando os Provedores A e B.
>
> **Se o seu for diferente:** `./scripts/lab.sh step7-leak-on` - ele monta
> tudo o que este passo precisa, vazamento incluído.

Toda rota inválida que você viu até agora ficou na tabela, rebaixada mas
visível, de propósito, para você poder olhar exatamente o que cada
verificação decidiu antes de confiar nela com alguma coisa. **Um roteador de
verdade não para por aí.** Marcar uma rota como inválida e continuar
usando-a sempre que nada melhor aparece não é para isso que o ROV ou o ASPA
servem; os dois só protegem alguma coisa quando uma rota inválida é de fato
rejeitada. Este é o passo em que isso acontece, para as duas verificações,
juntas, do jeito que você configuraria um roteador de produção desde o
início.

1. Passe os dois observadores para o descarte:

   ```
   #./scripts/lab.sh step8-drop
   ```

2. Compare o estágio que você acabou de deixar com este: a mudança é uma
   linha de política por verificação, em cada roteador:

   ```
   #diff bird/observer1-aspa-mark.conf bird/observer1-aspa-drop.conf
   #diff openbgpd/observer2-aspa-mark.conf openbgpd/observer2-aspa-drop.conf
   ```

   ```
       if roa_check(roa4_table, net, bgp_path.last) = ROA_INVALID then
           reject "ROV Invalid: ", net, " origin AS", bgp_path.last;   # observer1 (BIRD)
       ...
       ASPA_INVALID: reject "ASPA Invalid: ", net, " AS_PATH ", bgp_path;
   ```

   ```
   deny from any ovs invalid                               # observer2 (OpenBGPD)
   deny from any avs invalid
   ```

3. Olhe as rotas de novo:

   ```
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   ```
   *>    V-V 203.0.113.0/24          10.200.6.10       200     0 64502 64500 i
   ```

   **Duas rotas desapareceram, não uma.** O caminho forjado do
   AS666 sumiu, como esperado. O mesmo aconteceu com a entrada
   que costumava estar sob o Provedor A: o caminho vazado que você acabou
   de inspecionar. Ele não está perdido; o BIRD guarda o que rejeitou:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc show route table master4 filtered 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc show route table master4 filtered 203.0.113.0/24
   ```

   O selo agora diz *ROV + ASPA: descartando*. Repare no que o descarte
   **não** consertou: o caminho próprio e legítimo do Provedor A continua
   não aparecendo em lugar nenhum, porque o próprio Provedor A continua
   anunciando a rota vazada *no lugar da* sua, e nenhuma política nos
   observadores consegue fazer o Provedor A propagar algo que ele não está
   mandando. O ASPA protege os observadores de *usar* o vazamento; só o
   peer consertar a sua política de exportação estanca o vazamento na
   origem. É o próximo passo.

**No caminho:**

- **Marcar versus descartar.** Os mesmos vereditos dos Passos 3, 5 e 7 - a
  política é o que mudou. Marcar é como você implanta uma verificação sem
  quebrar nada; descartar é para o que a verificação *serve*, e é o que
  transforma um diagnóstico numa defesa.
- **Descartar não conserta o estrago upstream.** Ele só controla o que os
  próprios observadores aceitam. O Provedor A propagando o vazamento é um
  problema separado, consertado na origem, não nos observadores.
- **Daqui em diante, as duas verificações continuam descartando.** Um
  roteador que aprendeu a rejeitar rotas inválidas não volta atrás.

---

## Passo 9: guarde tudo

> **Estado:** estágio `aspa-drop` · AS666 forjando o caminho (derrotado) · o peer
> vazando · ROAs para os dois prefixos · ASPA listando os Provedores A e B.

1. Pare o vazamento:

   ```
   #./scripts/lab.sh step9-leak-off
   ```

   O caminho próprio do Provedor A volta nos dois observadores.

2. Se você vai seguir para os exercícios extras, silencie o AS666 também - eles ficam
   mais fáceis de ler sem ele:

   ```
   #./scripts/lab.sh step9-hijack-off
   ```

Os observadores continuam totalmente implantados, ROV e ASPA ambos
descartando, que é onde um roteador de verdade termina. (`./scripts/lab.sh
step1-clean` é o caminho de volta ao começo de tudo: silencia o
AS666 e o peer, *e* tira a validação dos observadores.)

---

## Resumo - o que pegou o quê, e o que a história respondeu

| Ataque | ROV | ASPA |
|---|---|---|
| Sequestro ingênuo (AS_PATH `666`) | **pega** (origem errada) | nada a verificar (caminho de um só AS) |
| Caminho forjado (AS_PATH `666 64500`) | **enganado** (a origem parece certa) | **pega** (o salto `64500 → 666` não está autorizado) |
| Vazamento de rota (AS_PATH `64501 64499 64500`) | **não enxerga** (a origem é genuína) | **pega** (o salto `64500 → 64499` não está autorizado) |

Nenhum dos dois é redundante. O ROV barra atacantes que mentem sobre a
origem; o ASPA barra caminhos que não poderiam ter acontecido. E a origem
tem que fazer a sua parte: um ASPA que esquece um provedor de verdade
(Passo 6) já é uma indisponibilidade por si só.

No caminho, a história foi respondendo, sem alarde, a perguntas que este
laboratório costumava tratar um exercício de cada vez:

- **Em que consiste, afinal, "implantar validação" num roteador?** Uma
  sessão com um validador, um teste em cada rota ou caminho, e uma ação
  sobre o resultado - as mesmas três peças para o ROV (Passo 3) e o ASPA
  (Passo 5), no roteador de qualquer fabricante.
- **Por que marcar primeiro e descartar depois, e por que descartar,
  afinal?** Marcar deixa você ver o que uma verificação faria antes de
  confiar nela, e foi o que pegou o seu próprio objeto ASPA incompleto no
  Passo 6 antes que ele quebrasse alguma coisa. Descartar é o que os
  roteadores de verdade fazem, e o que faz a verificação proteger alguma
  coisa - o Passo 8 liga as duas verificações de uma vez, do jeito que um
  roteador de produção é configurado desde o início.
- **O ROV consegue distinguir dois caminhos para o mesmo prefixo?** Não
  (Passo 4).
- **Como é um sequestro com o ASN de origem errado?** Passo 2, e como o ROV
  o barra no Passo 3.
- **O que acontece quando um ASPA esquece um provedor de verdade?** Passo 6.
- **Uma correção se propaga sozinha?** O BIRD revalida por conta própria; os
  objetos levam uma republicação e uma revalidação para chegar (Passos 3, 5
  e 6).
- **As duas pilhas independentes concordam?** Todo passo mostra as duas, e
  elas concordam em tudo o que a história examina - o Exercício extra A
  mostra onde não concordam.
- **O que é um vazamento de rota, e por que o ROV não o enxerga?** O Passo 7
  mostra; o Passo 8 mostra o que o descarte conserta, e o que não conserta,
  a respeito dele.

Quatro tópicos não couberam na história, e vivem nos extras abaixo: como os
algoritmos upstream e downstream diferem (e o `role` que escolhe um deles),
um sequestro que acerta o ASN mas erra o comprimento, um olhar por dentro
dos validadores e do RTR, e os vereditos **NotFound** e **Unknown** - os
"sem opinião" que você ainda não conheceu, porque a história nunca deixou um
prefixo descoberto.

---

## Exercícios extras

Os extras presumem que você terminou a história (os observadores em
`aspa-drop`, o peer em silêncio, `step9-hijack-off` executado) com objetos
para os dois prefixos e um ASPA listando os Provedores A e B. Cada um diz
qual estágio quer; os comandos `step` levam os dois observadores até lá de
uma vez.

### A. Upstream, downstream, e o papel que decide

*Estágio:* `step5-aspa-mark`.

No `bird/observer1-aspa-mark.conf` a verificação ASPA é:

```
case aspa_check_upstream(aspa_table) { ... }
```

O observador trata cada vizinho como o seu **cliente**. Para rotas vindas de
um cliente, aplica-se o *Algoritmo para Caminhos Upstream*, o mais estrito:
todo salto do caminho tem que ser uma relação cliente→provedor autorizada. É
a verificação que pega vazamentos de rota. Se a sessão fosse com um
provedor ou um peer, a chamada certa seria `aspa_check_downstream()`, mais
permissiva. O BIRD oferece as duas.

O OpenBGPD faz isso com um **role** de sessão (RFC 9234). Veja
`openbgpd/observer2-aspa-mark.conf`:

```
neighbor 10.200.5.10 {
    remote-as $provider_a_asn
    role provider
}
```

O OpenBGPD só executa a verificação ASPA numa sessão que tenha um role, e **é
o role que decide qual algoritmo ASPA roda**. `role provider` diz que o
sistema local é o upstream dos provedores (as rotas chegam de um cliente), e
isso seleciona o algoritmo *upstream*, o mesmo que o observer1 pede ao BIRD
com `aspa_check_upstream()`.

Para ver a diferença, você precisa de um caminho que o algoritmo estrito
rejeite e o permissivo não. Tire o Provedor B de volta do objeto ASPA (no
terminal do Krill):

```
#krillc aspas add --aspa "AS64500 => AS64501"
#./scripts/lab.sh refresh
```

O caminho pelo Provedor B agora aparece como Invalid nos dois observadores.

1. **Antes de mudar qualquer coisa:** os objetos em disco não vão mudar em
   nada, só uma palavra num arquivo de configuração. Você espera que o
   caminho pelo Provedor B continue Invalid, ou que vire?

2. `openbgpd/observer2-extra-a-role-customer.conf` é o
   `openbgpd/observer2-aspa-mark.conf` com exatamente essa uma palavra trocada:
   `role provider` virou `role customer` nos vizinhos do Provedor B
   (10.200.6.10 e fd00:6::10). Abra e compare (`diff
   openbgpd/observer2-aspa-mark.conf openbgpd/observer2-extra-a-role-customer.conf`),
   depois aplique à mão - não pelo `lab.sh`, já que esse estado só existe
   para este exercício:

   ```
   # Painel: clique na caixa observer2 e depois em Shell:
   #cp /etc/openbgpd-lab/observer2-extra-a-role-customer.conf /etc/bgpd.conf && bgpctl reload
   #bgpctl show rib 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer2 sh -c "cp /etc/openbgpd-lab/observer2-extra-a-role-customer.conf /etc/bgpd.conf && bgpctl reload"
   #docker exec lab-observer2 bgpctl show rib 203.0.113.0/24
   ```

   O caminho pelo Provedor B volta **Valid**. Os mesmos objetos, o mesmo
   AS_PATH, um veredito diferente, e nenhuma das duas implementações está
   errada. É a demonstração mais clara deste laboratório de que "este
   caminho é ASPA-válido?" não pode ser respondido sem dizer também *de
   quem* você o recebeu.

3. Agora faça o equivalente no BIRD: `bird/observer1-extra-a-downstream.conf` é
   o `bird/observer1-aspa-mark.conf` com `aspa_check_upstream` trocado por
   `aspa_check_downstream` nos dois filtros - abra e compare da mesma forma,
   depois aplique à mão:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc configure "/etc/bird-lab/observer1-extra-a-downstream.conf"
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc configure "/etc/bird-lab/observer1-extra-a-downstream.conf"
   ```

   **Antes de olhar:** você espera que o novo veredito do observer1
   coincida com o resultado do `role customer` do observer2 (`Valid`), ou
   com o resultado do seu `role provider` (`Invalid`)?

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc show route table master4 all 203.0.113.0/24
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc show route table master4 all 203.0.113.0/24
   ```

   Nenhum dos dois, na verdade: o BIRD reporta o caminho do Provedor B como
   **ASPA Unknown** (`(64510, 2, 1)`). As duas leituras são bem
   mais permissivas que o algoritmo upstream, que dizia `Invalid`, mas onde
   o OpenBGPD chama o caminho de válido, o BIRD diz que não sabe dizer.
   Duas implementações independentes, lendo a mesma aresta do mesmo draft
   de formas diferentes.

4. Compare os observadores lado a lado, depois pense nisto: se "upstream" e
   "downstream" é fundamentalmente sobre *de quem você recebeu a rota*, o
   que deveria acontecer numa topologia em que o mesmo vizinho é provedor
   para um prefixo e cliente para outro? (É por isso que a escolha de
   algoritmo do BIRD é uma chamada `aspa_check_*()` por sessão, e não uma
   configuração do laboratório inteiro, e por que o `role` do OpenBGPD é
   definido dentro de cada bloco `neighbor`.)

5. Desfaça: restaure `role provider` e `aspa_check_upstream`, adicione o Provedor B
   de volta ao ASPA (`krillc aspas add --aspa "AS64500 => AS64501, AS64502"`),
   rode `./scripts/lab.sh step5-aspa-mark` e `./scripts/lab.sh refresh`.

6. Mais um caso de borda, já que você está aqui: passe o AS666 de
   volta para o seu sequestro ingênuo (`./scripts/lab.sh
   step2-hijack-simple`). Com **um só AS** no caminho não há salto
   cliente→provedor para verificar, então o ASPA não tem nada a dizer sobre
   *quem pode originar um prefixo* - isso nunca foi trabalho dele. O BIRD
   chama esse caminho de `Valid` (`(64510, 2, 2)`), o OpenBGPD de
   `Unknown` (`?`). De novo, duas leituras de uma mesma aresta. Volte com
   `./scripts/lab.sh step9-hijack-off`.

### B. ASN certo, prefixo específico demais

*Estágio:* `step3-rov-mark` (para a rota inválida continuar visível).

O Passo 2 foi um sequestro com o ASN de origem errado. Este é o erro oposto:
a origem é totalmente legítima, mas o prefixo excede o que a ROA autorizou.
Um exemplo em IPv4 significaria desagregar 203.0.113.0/24 até um `/25`, algo
que é filtrado na Internet real em praticamente toda rede, e pareceria
artificial aqui. Anunciar um bloco IPv6 mais específico que um `/32` (um
`/36` ou `/40`, digamos) é uma prática operacional bem comum, e é isso que
este exercício usa. Para deixar claro que não é sobre nenhum dos dois
provedores, ele usa **dois** sub-blocos de 3fff:cafe::/32, um anunciado só ao
Provedor A e o outro só ao Provedor B.

O `bird/origin-extra-b.conf` é o `bird/origin.conf` mais exatamente isso:
duas rotas estáticas para `3fff:cafe:1000::/40` e `3fff:cafe:2000::/40`
(ambas dentro de 3fff:cafe::/32, ambas mais específicas do que
32 autoriza), e o filtro de exportação de cada provedor
ampliado para carregar também o seu próprio sub-bloco. Abra e compare com o
`bird/origin.conf` (`diff bird/origin.conf bird/origin-extra-b.conf`) antes
de aplicar à mão:

```
# Painel: clique na caixa origin e depois em Shell:
#birdc configure "/etc/bird-lab/origin-extra-b.conf"
# Ou, no terminal do seu computador:
#docker exec lab-origin birdc configure "/etc/bird-lab/origin-extra-b.conf"
```

Veja o que cada provedor de fato recebeu:

```
# Painel: clique na caixa provider-a e depois em Shell:
#birdc show route
# Painel: clique na caixa provider-b e depois em Shell:
#birdc show route
```

O Provedor A tem `3fff:cafe:1000::/40`; o Provedor B tem
`3fff:cafe:2000::/40` - cada um só o que era destinado a ele. Agora os
observadores:

```
# Painel: clique na caixa observer2 e depois em Shell:
#bgpctl show rib 3fff:cafe:1000::/40
#bgpctl show rib 3fff:cafe:2000::/40
# Ou, no terminal do seu computador:
#docker exec lab-observer2 bgpctl show rib 3fff:cafe:1000::/40
#docker exec lab-observer2 bgpctl show rib 3fff:cafe:2000::/40
```

```
*>    !-? 3fff:cafe:1000::/40  fd00:5::10         10     0 64501 64500 64500 64500 i
```

```
*>    !-? 3fff:cafe:2000::/40  fd00:6::10         10     0 64502 64500 i
```

Os dois caminhos são **ROV Invalid** - cada um um anúncio perfeitamente
legítimo por um provedor autorizado, rejeitado pelo mesmo motivo nos dois
lados: a ROA de 3fff:cafe::/32 só autoriza anúncios até
`/32`, e os dois sub-blocos são mais específicos que isso.
Não é sobre o Provedor A ou o Provedor B, é o prefixo. Em `rov-mark` os dois
continuam visíveis, rebaixados, exatamente como o sequestro no Passo 3. Rode
`step8-drop` e eles somem do mesmo jeito que o sequestro sumiu depois.

Desfaça quando terminar:

```
# Painel: clique na caixa origin e depois em Shell:
#birdc configure
# Ou, no terminal do seu computador:
#docker exec lab-origin birdc configure
```

> **O padrão:** o ROV confere *o que está sendo anunciado e por quem*. O
> ASPA confere *se o caminho que o trouxe até aqui é um que a origem
> autorizou*. Este exercício, e o sequestro ingênuo do Passo 2, quebram o
> ROV sem tocar no ASPA; o caminho forjado e o vazamento quebram o ASPA sem
> tocar no ROV. Uma implantação de verdade quer os dois rodando.

### C. Por dentro dos validadores, e o RTR

*Estágio:* `step5-aspa-mark` (para existirem tanto a tabela de ROAs quanto a de ASPAs).

A história só olhou os vereditos dos roteadores. Aqui olhamos como eles
chegaram lá.

1. Abra o Routinator: **http://routinator.localhost:8080**

   Ele está configurado para validar **apenas** a âncora de confiança do
   próprio laboratório, não a Internet inteira:

   ```
   --no-rir-tals  --extra-tals-dir=/tals  --enable-aspa
   ```

   O TAL é instalado automaticamente quando o laboratório sobe. Em
   `MODE=local` ele vem da âncora de confiança do próprio LabNIC (e
   está disponível para download no painel do registro); em `MODE=beta`, de
   `https://rpki-test-ta.beta.registro.br/ta/ta.tal`.

2. Olhe o conjunto validado, com ROAs e ASPAs:

   ```
   #curl -s http://routinator.localhost:8080/json
   ```

3. Veja o que o observer1 recebeu por RTR:

   ```
   # Painel: clique na caixa observer1 e depois em Shell:
   #birdc show protocols all routinator
   #birdc show route table roa4_table
   #birdc show route table aspa_table
   # Ou, no terminal do seu computador:
   #docker exec lab-observer1 birdc show protocols all routinator
   #docker exec lab-observer1 birdc show route table roa4_table
   #docker exec lab-observer1 birdc show route table aspa_table
   ```

   O protocolo RTR precisa estar `Established`. A tabela ASPA só é
   preenchida com a **versão 2 do RTR**, a versão que o Routinator negocia
   quando o ASPA está ligado.

4. E o observer2, que recebe os seus objetos do FORT:

   ```
   # Painel: clique na caixa observer2 e depois em Shell:
   #bgpctl show rtr
   #bgpctl show sets
   # Ou, no terminal do seu computador:
   #docker exec lab-observer2 bgpctl show rtr
   #docker exec lab-observer2 bgpctl show sets
   ```

   O `show rtr` tem que dizer `Version: 2`. O ASPA só viaja em PDUs da
   versão 2 do RTR: na versão 1 a sessão ainda sobe e as ROAs ainda chegam,
   mas todo veredito ASPA ficaria `unknown`. O `show sets` lista uma entrada
   de ROA para IPv4, uma para IPv6 e um ASPA (`#ASnum 1`).

### D. NotFound e Unknown

*Estágio:* `step5-aspa-mark`.

A história só mostrou **Valid** e **Invalid**. Os outros dois vereditos,
**NotFound** (nenhuma ROA cobre o prefixo) e **Unknown** (não existe objeto
ASPA para aquele ASN cliente), são na verdade o estado *padrão*, o mais
comum na Internet de verdade, onde a maioria dos prefixos ainda não tem
nenhuma cobertura RPKI. Eles nunca apareceram porque toda rota na história
estava coberta. Faça-os aparecer de propósito, tirando objetos:

1. Remova a ROA IPv4 e o objeto ASPA:

   ```
   # Painel: clique na caixa krill e depois em Shell:
   #krillc roas update --ca acme_ca --remove "203.0.113.0/24-24 => 64500"
   #krillc aspas remove --ca acme_ca --customer AS64500
   #krillc bulk publish
   # Ou, no terminal do seu computador:
   #docker exec lab-krill krillc roas update --ca acme_ca --remove "203.0.113.0/24-24 => 64500"
   #docker exec lab-krill krillc aspas remove --ca acme_ca --customer AS64500
   #docker exec lab-krill krillc bulk publish
   ```

2. Confirme que realmente sumiram antes de seguir (`krillc roas list --ca
   acme_ca` e `krillc aspas list --ca acme_ca` devem voltar ambos
   sem eles), depois faça o refresh:

   ```
   #./scripts/lab.sh refresh
   ```

3. Confira os vereditos de `203.0.113.0/24` nos dois observadores: os dois
   caminhos devem agora aparecer como **ROV NotFound, ASPA Unknown** -
   "não temos opinião", não uma rejeição, e por isso ficam na tabela mesmo
   com as duas verificações ligadas. Repare que `3fff:cafe::/32` não é
   afetado: a ROA dele ainda está lá, então ele mantém os seus vereditos
   normais. A cobertura é por prefixo - não ter nenhuma para um não diz
   nada sobre outro. (É também por isso que implantar o ROV não protege
   nada até que os *outros* ASes publiquem ROAs: um prefixo sem ROA não
   pode ser pego por nada.)

4. Restaure os dois objetos e faça o refresh de novo:

   ```
   # Painel: clique na caixa krill e depois em Shell:
   #krillc roas update --ca acme_ca --add "203.0.113.0/24-24 => 64500"
   #krillc aspas add --ca acme_ca --aspa "AS64500 => AS64501, AS64502"
   #krillc bulk publish
   # Ou, no terminal do seu computador:
   #docker exec lab-krill krillc roas update --ca acme_ca --add "203.0.113.0/24-24 => 64500"
   #docker exec lab-krill krillc aspas add --ca acme_ca --aspa "AS64500 => AS64501, AS64502"
   #docker exec lab-krill krillc bulk publish
   #./scripts/lab.sh refresh
   ```

> Se os vereditos do passo 4 não voltarem depois de um refresh, geralmente é
> só porque o refresh rodou antes de o Krill terminar de publicar (confira
> com `krillc roas list`/`krillc aspas list` antes, como no passo 2). Rodar
> `./scripts/lab.sh refresh` de novo alguns segundos depois resolve.

---

## Se algo não funcionar

| Sintoma | O que conferir |
|---|---|
| O que eu vejo não bate com um passo | Leia a caixa de **Estado** do passo e rode o único comando que ela lista - todo comando `stepN-*` define o seu estado inteiro (atacante, peer, ROAs, ASPA, estágio dos observadores), não só o que mudou desde o passo anterior, então é seguro rodá-lo de qualquer ponto da história. |
| Um comando `stepN-*` para com um erro de Krill/CA | A partir do `step3-rov-mark`, todo comando `stepN-*` confere se a Preparação realmente terminou antes de mexer em qualquer coisa - veja "Como a história está organizada". A mensagem diz o que falta (nenhuma CA, mais de uma, ou uma que ainda não está totalmente configurada); resolva isso no Krill e no painel, e rode o mesmo comando de novo. |
| A rota do AS666 não aparece | Quando um observador está *descartando* o que uma verificação sinaliza (estágio `aspa-drop`, a partir do `step8-drop`), essa rota some da tabela de propósito: olhe em `birdc show route table master4 filtered` no observer1. Antes disso, `none` não tem vereditos e `rov-mark`/`aspa-mark` só rebaixam, então a rota ainda deveria estar lá. Caso contrário, confira se você rodou o comando do passo e se a sessão está no ar: `docker exec lab-attacker birdc show protocols`. |
| Os dois observadores discordam, ou o selo de estágio está âmbar | O selo no cabeçalho do painel mostra o estágio que cada observador está realmente rodando; âmbar significa que diferem. Rode o comando de passo do estágio que você quer (ex.: `./scripts/lab.sh step8-drop`) para colocar os dois no mesmo. Logo depois de uma troca, o observer2 também precisa de dez ou quinze segundos para se acomodar (ele reinicia), então olhe de novo antes de concluir qualquer coisa. |
| Criei a ROA/ASPA mas nada mudou | `./scripts/lab.sh refresh` força os dois validadores a revalidar. Se ainda não mudar, o `refresh` pode ter rodado antes de o Krill terminar de publicar: confira `krillc roas list` / `krillc aspas list`, espere alguns segundos, faça o refresh de novo. |
| Criei a ROA mas ela não aparece no Krill | A CA ainda não tinha o certificado do pai. `docker exec lab-krill krillc bulk refresh`, refaça a ROA, depois `krillc bulk publish` |
| O Routinator não mostra nenhum ASPA | Faltou o `--enable-aspa`, ou o objeto ainda não foi publicado/revalidado. `./scripts/lab.sh refresh`. |
| A tabela `aspa_table` do BIRD está vazia | O RTR negociou a versão 1. Confira `birdc show protocols all routinator` e se o Routinator subiu com `--enable-aspa`. |
| Uma sessão BGP não sobe | `docker compose logs origin provider-a provider-b observer1 observer2 attacker peer` |
| O observer2 mostra `avs` como `unknown` em todo lugar | A sessão RTR negociou a versão 1, ou o FORT é anterior à 1.7.0.experimental. Confira se `bgpctl show rtr` diz `Version: 2`. |
| O observer2 mostra `avs` como `valid` nos DOIS caminhos | A sessão perdeu o seu role da RFC 9234 - geralmente depois de um `bgpctl reload` avulso. Rode de novo o comando de passo do estágio (`./scripts/lab.sh step5-aspa-mark` ou `step8-drop`), que reinicia o observer2 com a configuração do estágio. |
| O FORT não sobe ou não busca nada | `docker logs lab-fort`. Deve terminar com "First validation cycle successfully ended". Se o TLS falhar, a CA do laboratório não chegou ao seu repositório de confiança: confira se o volume `pki` está montado. |
| O Krill não consegue falar com o Registro.br | O contêiner precisa de acesso de saída à Internet: `docker exec lab-krill ping -c1 beta.registro.br` |
| Quero recomeçar do zero | `./scripts/lab.sh reset` (apaga a CA do Krill, o estado do registro do próprio LabNIC e o cache dos dois validadores), depois `up`. Não rode um `docker compose down -v` avulso: o LabNIC e o painel do registro só sobem sob o perfil `local` do compose, e um `docker compose down` avulso os deixa rodando silenciosamente - o `lab.sh` configura isso para você. Rode também do terminal do seu próprio computador, não do console dentro do navegador do painel: o `reset` derruba o laboratório inteiro, inclusive esse console, o que mata o comando pela metade. |
| Os validadores mostram ROAs/ASPA mas a CA do Krill parece completamente vazia | Você está olhando duas CAs diferentes: a sua própria (recém-criada) no Krill, e objetos antigos ainda publicados sob uma CA velha de mesmo nome no registro, sobras de um reset que não limpou tudo. `./scripts/lab.sh reset` (não um `docker compose down -v` avulso) limpa os dois lados juntos. |
| Mudei o `lab.conf` e nada mudou | `./scripts/lab.sh up` regenera o `bird/vars.conf`, recria os roteadores, e agora também devolve a história ao estado limpo (estágio `none`, AS666 e o peer calados). Se você mudou o ASN ou os prefixos e já tem uma CA, o certificado dela ainda tem os recursos *antigos* - refaça a delegação da Preparação 2 (no modo local, "Add parent" no Krill contra o mesmo parent atualiza os direitos; `docker exec lab-krill krillc bulk refresh` força a CA a buscá-los) antes que `step3-rov-mark` em diante volte a funcionar. |
| O painel do registro não abre | Ele só existe em `MODE=local`. Confira o `lab.conf` e rode `./scripts/lab.sh up` |
| O Krill não consegue falar com o LabNIC | O Krill precisa confiar na CA interna do laboratório: `docker logs lab-krill` mostra um erro de TLS se `/pki/ca.pem` não estiver montado |
| Troquei o MODE e a CA sumiu | É de propósito: cada modo tem o seu próprio volume, para um não atropelar o trabalho do outro |
| Os objetos estão no Routinator mas o BIRD não mudou | O BIRD revalida por conta própria, mas leva alguns segundos. Para forçar: `docker exec lab-observer1 birdc reload in provider_a_v4` |

## Referências

- RFC 6811 - validação de origem para o BGP
- RFC 9582 - perfil da ROA
- RFC 7908 - definição e classificação do problema dos vazamentos de rota BGP
- RFC 9234 - prevenção e detecção de vazamento de rotas usando roles
- `draft-ietf-sidrops-aspa-profile` - o perfil do objeto ASPA
- `draft-ietf-sidrops-aspa-verification` - os algoritmos upstream e downstream
- `draft-ietf-sidrops-8210bis` - RTR versão 2, que carrega os ASPAs
- Documentação do Krill: https://krill.docs.nlnetlabs.nl
- Documentação do Routinator: https://routinator.docs.nlnetlabs.nl
- Documentação do BIRD: https://bird.network.cz/

*Este guia está licenciado sob [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). O código do laboratório está sob Apache-2.0. Veja os arquivos `LICENSE` no repositório.*
