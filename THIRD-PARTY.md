# Third-party software

This lab does not modify or link against any of the software below: each piece
runs unmodified in its own container (or is installed from Alpine's package
repositories while building the lab's images). Each keeps its own license,
which applies to it, not to the lab's own files (see [LICENSE](LICENSE) and
[LICENSE-docs](LICENSE-docs)).

Names such as Krill, Routinator, FORT, BIRD, OpenBGPD, nginx and Alpine belong
to their respective projects. Using them here doesn't imply their endorsement.

| Component | Used for | Version | License |
|---|---|---|---|
| [Krill](https://github.com/NLnetLabs/krill) | the student's CA and the simulated registry (LabNIC) | 0.16.0 | MPL-2.0 |
| [Routinator](https://github.com/NLnetLabs/routinator) | observer1's validator | 0.15.2 | BSD-3-Clause |
| [FORT Validator](https://github.com/NICMx/FORT-validator) | observer2's validator | 1.7.0.experimental | MIT |
| [BIRD](https://bird.network.cz/) | origin, providers, peer, attacker and observer1 | 3.1.4 | GPL-2.0-or-later |
| [OpenBGPD](https://www.openbgpd.org/) | observer2 | 8.8 | ISC |
| [nginx](https://nginx.org/) | serves the panel and the guide | 1.29 | BSD-2-Clause |
| [ttyd](https://github.com/tsl0922/ttyd) | terminals in the browser | Alpine package | MIT |
| [Alpine Linux](https://alpinelinux.org/) | base of most of the lab's own images | 3.22 | various, per package |
| [Debian](https://www.debian.org/) | base of the FORT image, which is built from source | bookworm | various, per package |
| Docker CLI and Compose plugin | run inside the console container | Alpine packages | Apache-2.0 |
| Python | the panel's status collector and the registry panel | Alpine package | PSF-2.0 |

Versions are the ones pinned in `docker-compose.yml` and the `Dockerfile`s at
the time of writing. Licenses were taken from each project's own repository or
website; check them there before redistributing.

## If you redistribute the lab's images

Publishing container images or a virtual machine that contains BIRD (GPL) or
the Alpine and Debian packages means redistributing that software. Include the license
texts and either the corresponding source or a written offer for it, as each
license requires. The lab's own files stay under Apache-2.0 and CC BY 4.0
either way.
