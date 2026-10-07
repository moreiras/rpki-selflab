# work/

Os seus próprios arquivos de configuração ficam aqui. Esta é a única pasta
do laboratório em que os terminais do painel podem gravar:

| Onde | Caminho | Acesso |
|---|---|---|
| o seu computador | `work/` (esta pasta) | leitura e escrita |
| o terminal **Comandos do laboratório** do painel | `/lab/work` (a pasta do laboratório é o diretório de trabalho, então `work/`) | leitura e escrita (`nano`, `vim`) |
| todos os roteadores (BIRD e OpenBGPD) | `/etc/lab-work` | somente leitura |

Um ciclo típico, partindo de um dos arquivos do próprio laboratório:

```sh
cp bird/observer1-none.conf work/meu-observer1.conf
nano work/meu-observer1.conf
docker exec lab-observer1 birdc 'configure "/etc/lab-work/meu-observer1.conf"'
```

Para voltar à configuração do roteiro, rode o comando de passo do estágio
que você quer (por exemplo, `./scripts/lab.sh step3-rov-mark`).

Tudo nesta pasta, menos os READMEs, é ignorado pelo git.

Traduções: [English](README.md) · [Español](README.es.md)
