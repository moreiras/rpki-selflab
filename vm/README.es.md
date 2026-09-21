# RPKI SelfLab como máquina virtual

Una pequeña máquina virtual con un escritorio propio, para que **no haya nada que
configurar**: ningún puerto que reenviar, ningún modo de red que elegir, ninguna
dirección que averiguar. Usted la enciende y, cerca de un minuto después, un
navegador se abre en el panel del laboratorio y un terminal queda a una tecla de
distancia. Docker, el laboratorio y todas las imágenes que necesita están dentro
(unos 650 MB comprimidos), y todo funciona sin acceso a Internet.

Archivos de una release (`rpki-selflab-vX.Y.Z-<arq>`):

| Archivo | Para |
|---|---|
| `...-arm64.qcow2` | Macs con Apple Silicon (M1 y posteriores) y otras computadoras ARM |
| `...-amd64.qcow2` | computadoras Intel y AMD (Windows, Linux, Macs Intel) |
| `SHA256SUMS` | sumas de verificación: `shasum -a 256 -c SHA256SUMS` (Linux/macOS) |

Dé a la VM **al menos 3 GB de RAM (4 GB es mejor), 2 CPUs** y 8 GB de disco (la
imagen crece hasta ese tamaño).

## Uso

1. Inicie la VM (instrucciones por sistema más abajo) y espere cerca de un
   minuto. El navegador muestra "Iniciando el laboratorio..." y después abre el
   panel solo.
2. Dentro de la VM:
   - **Alt+1** el navegador, con el panel del laboratorio y la guía (pestaña *Guion*);
   - **Alt+2** un terminal, ya en la carpeta del laboratorio (`/opt/lab`);
   - **Alt+Espacio** cambia la distribución del teclado (US, brasileño, español);
   - **Alt+Enter** abre otro terminal, **Alt+F** pone la ventana a pantalla completa.
3. El escritorio inicia sesión solo como `labuser`. La contraseña de `root` es
   `labpass` (`su -` en el terminal).
4. Para empezar de nuevo, en el terminal: `./scripts/lab.sh reset` y luego
   `./scripts/lab.sh up`. Ambos funcionan sin conexión.

El mouse y el teclado pueden quedar capturados por la ventana de la VM: use la
tecla de liberación de su programa (QEMU: `Ctrl+Alt+G`; UTM y VirtualBox indican
cuál es en la ventana).

## macOS

La imagen para Apple Silicon (`arm64`) funciona a toda velocidad con **UTM**
(gratuito, https://mac.getutm.app) o con QEMU.

**UTM:** *Create a New Virtual Machine* → *Virtualize* → *Linux*. Deje vacía la
ISO de arranque. Use 4096 MB de memoria y 2 CPUs. Termine y edite la VM: quite el
disco predeterminado y use *New Drive → Import…* con el `.qcow2` (interfaz
*VirtIO*), y compruebe que la pantalla sea *virtio-gpu-pci* (no una variante
`-gl`). Inicie.

**QEMU** (`brew install qemu`), en la carpeta de la imagen:

```sh
# una capa descartable sobre la imagen, para que la imagen misma quede intacta
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-arm64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-aarch64 -machine virt,accel=hvf -cpu host -smp 2 -m 4096 \
  -bios "$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd" \
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 \
  -nic user -device virtio-gpu-pci -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display cocoa
```

Para empezar de cero, borre `selflab-disk.qcow2` y créelo otra vez.

## Linux

**QEMU/KVM** en una computadora Intel/AMD:

```sh
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-amd64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 2 -m 4096 \
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 \
  -nic user -device virtio-vga -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display gtk
```

**virt-manager:** *Nueva máquina virtual* → *Importar imagen de disco existente* →
elija el `.qcow2`, SO *Generic Linux*, 4096 MB y 2 CPUs; antes de iniciar, ponga
el *Video* en *Virtio* (la imagen `arm64` también necesita firmware UEFI en una
computadora ARM).

**VirtualBox:** vea la sección de Windows (es igual).

## Windows

**VirtualBox** (Intel/AMD; https://www.virtualbox.org). Convierta la imagen una
vez (`qemu-img` viene con QEMU para Windows, o use cualquier computadora
Linux/macOS):

```
qemu-img convert -O vdi rpki-selflab-vX.Y.Z-amd64.qcow2 rpki-selflab.vdi
```

Después, *Nueva*: tipo *Linux*, versión *Other Linux (64-bit)*, 4096 MB, 2 CPUs,
*Usar un archivo de disco duro virtual existente* → el `.vdi`, y deje EFI
**apagado**. Antes de iniciar: *Pantalla → Controlador gráfico: VMSVGA* con 128 MB
de memoria de video, y *Sistema → Dispositivo señalador: Tableta USB*. La red
puede quedar en el valor predeterminado (NAT); el laboratorio no la usa.

**QEMU para Windows** (https://www.qemu.org/download/#windows), en PowerShell, con
la *Plataforma de hipervisor de Windows* activada para ganar velocidad:

```powershell
qemu-img create -f qcow2 -b rpki-selflab-vX.Y.Z-amd64.qcow2 -F qcow2 selflab-disk.qcow2

qemu-system-x86_64 -machine "q35,accel=whpx:tcg" -cpu max -smp 2 -m 4096 `
  -drive file=selflab-disk.qcow2,if=virtio,format=qcow2 `
  -nic user -device virtio-vga -device qemu-xhci -device usb-kbd -device usb-tablet `
  -display sdl
```

**Hyper-V** (Windows Pro): `qemu-img convert -O vhdx rpki-selflab-vX.Y.Z-amd64.qcow2 rpki-selflab.vhdx`,
cree una VM de **Generación 1** con 4096 MB y ese disco, e inicie.

## Si algo se ve mal

- **Pantalla en blanco o negra por un rato:** espere; el primer arranque tarda
  cerca de un minuto (el navegador espera el laboratorio y se abre solo).
- **La ventana es pequeña o no sigue el tamaño:** ajuste la resolución en la
  configuración de pantalla del programa de la VM, o use pantalla completa (Alt+F
  dentro de la VM y el modo de pantalla completa de su programa).
- **El teclado escribe caracteres equivocados:** Alt+Espacio recorre las
  distribuciones US, brasileña (ABNT2) y española.
- **El panel dice que no hay nada en ejecución:** abra el terminal (Alt+2) y
  ejecute `./scripts/lab.sh status`; el registro de arranque es
  `/var/log/rpki-selflab.log`.

## Estado

La imagen `arm64` se construyó y se inició en un Mac con Apple Silicon usando QEMU
(con aceleración por hardware): el escritorio, el navegador abriendo el panel y el
terminal funcionaron. Los demás programas y sistemas de este archivo no se
probaron.

## Para quien mantiene: construir una release

Vea la sección correspondiente en [README.md](README.md) (en inglés): `vm/release.sh`,
el versionado por la etiqueta git `vMAJOR.MINOR.PATCH` y cómo se hacen las imágenes.
