# work/

Your own configuration files go here. This is the one folder of the lab
that the panel's terminals can write to:

| Where | Path | Access |
|---|---|---|
| your computer | `work/` (this folder) | read and write |
| the panel's **Lab commands** terminal | `/lab/work` (the lab's folder is the working directory, so `work/`) | read and write (`nano`, `vim`) |
| every router (BIRD and OpenBGPD) | `/etc/lab-work` | read only |

A typical loop, starting from one of the lab's own files:

```sh
cp bird/observer1-none.conf work/my-observer1.conf
nano work/my-observer1.conf
docker exec lab-observer1 birdc 'configure "/etc/lab-work/my-observer1.conf"'
```

To go back to the guide's configuration, run the step command for the stage
you want (for example `./scripts/lab.sh step3-rov-mark`).

Everything in this folder except the READMEs is ignored by git.

Translations: [Español](README.es.md) · [Português](README.pt.md)
