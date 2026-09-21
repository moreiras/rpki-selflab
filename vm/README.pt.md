# RPKI SelfLab como máquina virtual

Uma pequena máquina virtual com uma área de trabalho própria, para que **não haja
nada a configurar**: nenhuma porta a encaminhar, nenhum modo de rede a escolher,
nenhum endereço a descobrir. Você liga a VM e, cerca de um minuto depois, um
navegador abre no painel do laboratório e um terminal fica a uma tecla de
distância. O Docker, o laboratório e todas as imagens de que ele precisa estão
dentro (cerca de 650 MB compactados), e tudo funciona sem acesso à Internet.

Arquivos de uma release (`rpki-selflab-vX.Y.Z-<arq>`):

| Arquivo | Para |
|---|---|
| `...-arm64.qcow2` | Macs com Apple Silicon (M1 e posteriores) e outros computadores ARM |
| `...-amd64.qcow2` | computadores Intel e AMD (Windows, Linux, Macs Intel) |
| `SHA256SUMS` | somas de verificação: `shasum -a 256 -c SHA256SUMS` (Linux/macOS) |

Dê à VM **pelo menos 3 GB de RAM (4 GB é melhor), 2 CPUs** e 8 GB de disco (a
imagem cresce até esse tamanho).

## Usando

1. Inicie a VM (instruções por sistema abaixo) e espere cerca de um minuto. O
   navegador mostra "Iniciando o laboratório..." e depois abre o painel sozinho.
2. Dentro da VM:
   - **Alt+1** o navegador, com o painel do laboratório e o guia (aba *Roteiro*);
   - **Alt+2** um terminal, já na pasta do laboratório (`/opt/lab`);
   - **Alt+Espaço** alterna o layout do teclado (US, brasileiro, espanhol);
   - **Alt+Enter** abre outro terminal, **Alt+F** põe a janela em tela cheia.
3. A área de trabalho entra sozinha como `labuser`. A senha do `root` é
   `labpass` (`su -` no terminal).
4. Para recomeçar, no terminal: `./scripts/lab.sh reset` e depois
   `./scripts/lab.sh up`. Os dois funcionam offline.

O mouse e o teclado podem ficar presos na janela da VM: use a tecla de
liberação do seu programa (QEMU: `Ctrl+Alt+G`; o UTM e o VirtualBox mostram
qual é na janela).

## macOS

A imagem para Apple Silicon (`arm64`) roda em velocidade total com o **UTM**
(gratuito, https://mac.getutm.app) ou com o QEMU.

**UTM:** *Create a New Virtual Machine* → *Virtualize* → *Linux*. Deixe a ISO de
boot vazia. Use 4096 MB de memória e 2 CPUs. Conclua e edite a VM: remova o
disco padrão e use *New Drive → Import…* com o `.qcow2` (interface *VirtIO*), e
confira que a tela é *virtio-gpu-pci* (não uma variante `-gl`). Inicie.

**QEMU** (`brew install qemu`), na pasta da imagem:

```sh
# uma camada descartável sobre a imagem, para a imagem em si ficar intacta
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-arm64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-aarch64 -machine virt,accel=hvf -cpu host -smp 2 -m 4096 \
  -bios "$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd" \
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 \
  -nic user -device virtio-gpu-pci,xres=1600,yres=900 -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display cocoa,zoom-to-fit=on
```

Para recomeçar do zero, apague o `selflab-disk.qcow2` e crie-o de novo.

## Linux

**QEMU/KVM** em um computador Intel/AMD:

```sh
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-amd64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 2 -m 4096 \
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 \
  -nic user -device virtio-vga,xres=1600,yres=900 -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display gtk,zoom-to-fit=on
```

**virt-manager:** *Nova máquina virtual* → *Importar imagem de disco existente* →
escolha o `.qcow2`, SO *Generic Linux*, 4096 MB e 2 CPUs; antes de iniciar, ponha
o *Vídeo* em *Virtio* (a imagem `arm64` também precisa de firmware UEFI em um
computador ARM).

**VirtualBox:** veja a seção do Windows (é igual).

## Windows

**VirtualBox** (Intel/AMD; https://www.virtualbox.org). Converta a imagem uma vez
(o `qemu-img` vem com o QEMU para Windows, ou use qualquer computador Linux/macOS):

```
qemu-img convert -O vdi rpki-selflab-vX.Y.Z-amd64.qcow2 rpki-selflab.vdi
```

Depois, *Novo*: tipo *Linux*, versão *Other Linux (64-bit)*, 4096 MB, 2 CPUs,
*Usar um arquivo de disco rígido virtual existente* → o `.vdi`, e deixe o EFI
**desligado**. Antes de iniciar: *Tela → Controladora gráfica: VMSVGA* com 128 MB
de memória de vídeo, e *Sistema → Dispositivo apontador: Tablet USB*. A rede pode
ficar no padrão (NAT); o laboratório não a usa.

**QEMU para Windows** (https://www.qemu.org/download/#windows), no PowerShell, com
a *Plataforma do Hipervisor do Windows* ativada para ganhar velocidade:

```powershell
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-amd64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-x86_64 -machine "q35,accel=whpx:tcg" -cpu max -smp 2 -m 4096 `
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 `
  -nic user -device virtio-vga,xres=1600,yres=900 -device qemu-xhci -device usb-kbd -device usb-tablet `
  -display gtk,zoom-to-fit=on
```

**Hyper-V** (Windows Pro): `qemu-img convert -O vhdx rpki-selflab-vX.Y.Z-amd64.qcow2 rpki-selflab.vhdx`,
crie uma VM de **Geração 1** com 4096 MB e esse disco, e inicie.

## Se algo parecer errado

- **Tela em branco ou preta por um tempo:** espere; o primeiro início leva cerca
  de um minuto (o navegador espera o laboratório e abre sozinho).
- **Não consigo redimensionar a janela:** o QEMU não muda a resolução do
  convidado quando você arrasta a janela. Os comandos acima iniciam a tela em
  1600x900 e o `zoom-to-fit=on` a escala para o tamanho que a janela tiver; para
  outra resolução, mude `xres`/`yres` em `-device virtio-gpu-pci,xres=...,yres=...`.
  No VirtualBox use as configurações de *Tela*, e no UTM a resolução da tela dele.
- **O teclado digita caracteres errados:** Alt+Espaço percorre os layouts US,
  brasileiro (ABNT2) e espanhol.
- **O painel diz que nada está rodando:** abra o terminal (Alt+2) e rode
  `./scripts/lab.sh status`; o log de partida é `/var/log/rpki-selflab.log`.

## Situação

A imagem `arm64` foi montada e iniciada em um Mac com Apple Silicon usando QEMU
(com aceleração de hardware): a área de trabalho, o navegador abrindo o painel e
o terminal funcionaram. Os demais programas e sistemas deste arquivo não foram
testados.

## Para quem mantém: montando uma release

Veja a seção correspondente em [README.md](README.md) (em inglês): `vm/release.sh`,
o versionamento pela tag git `vMAJOR.MINOR.PATCH` e como as imagens são feitas.
