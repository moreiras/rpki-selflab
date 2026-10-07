# work/

Sus propios archivos de configuración van aquí. Es la única carpeta del
laboratorio en la que las terminales del panel pueden escribir:

| Dónde | Ruta | Acceso |
|---|---|---|
| su computadora | `work/` (esta carpeta) | lectura y escritura |
| la terminal **Comandos del laboratorio** del panel | `/lab/work` (la carpeta del laboratorio es el directorio de trabajo, así que `work/`) | lectura y escritura (`nano`, `vim`) |
| todos los routers (BIRD y OpenBGPD) | `/etc/lab-work` | solo lectura |

Un ciclo típico, partiendo de uno de los archivos del propio laboratorio:

```sh
cp bird/observer1-none.conf work/mi-observer1.conf
nano work/mi-observer1.conf
docker exec lab-observer1 birdc 'configure "/etc/lab-work/mi-observer1.conf"'
```

Para volver a la configuración de la guía, ejecute el comando de paso de la
etapa que quiera (por ejemplo, `./scripts/lab.sh step3-rov-mark`).

Todo en esta carpeta, salvo los README, lo ignora git.

Traducciones: [English](README.md) · [Português](README.pt.md)
