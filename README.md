# iic-osic-tools + SPICE OPUS (unofficial build)

An extended build of [`hpretl/iic-osic-tools`](https://hub.docker.com/r/hpretl/iic-osic-tools), the all-in-one open-source IC design environment from the Institute for Integrated Circuits, Johannes Kepler University Linz. This image adds **SPICE OPUS**, **Open MPI** and **mpi4py** on top of the upstream image, and comes with simple start scripts for Linux, macOS and Windows.

Docker Hub image: `stralax/iic-osic-tools`

> This project is not affiliated with or endorsed by JKU/IIC or the SPICE OPUS authors.

---

## What is in this repository

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the extended image on top of `hpretl/iic-osic-tools:latest`. |
| `start_icc.sh` | Start/stop/remove script for Linux, macOS and Windows (WSL / Git Bash). |
| `start_icc.bat` | The same script for Windows `cmd` (Docker Desktop, no WSL needed). |

---

## What was added to the upstream image

| Component | Details |
|---|---|
| **SPICE OPUS** | Version 3.0 r407 (build 2023.08.23), installed from the official `.deb` package for amd64 and arm64. Binary: `spiceopus`, files in `/usr/lib/spiceopus`. |
| **Open MPI** | `libopenmpi-dev` |
| **Python headers** | `python3-dev` |
| **mpi4py** | Installed with pip, system-wide |

Environment variables set in the image:

- `PARALLEL_MIRRORED_STORAGE=/`
- `QT_LOGGING_RULES="qt.qpa.theme.gnome=false"` (hides a Qt GNOME theme warning)

The default user is `1000:1000`, same as upstream. Everything else from the upstream image is unchanged.

<!-- If you added Visual Studio Code to the Dockerfile, add a row for it above. Otherwise delete this comment. -->

---

## Quick start

**Requirements:** Docker (Docker Desktop on Windows and macOS, Docker Engine on Linux). On Linux your user must be in the `docker` group, otherwise the commands need `sudo`.

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/Stralax/iic-osic-tools/main/start_icc.sh -o start_icc.bat
chmod +x start_icc.sh
./start_icc.sh
```

### Windows (cmd or PowerShell)

```bat
curl -fsSL https://raw.githubusercontent.com/Stralax/iic-osic-tools/main/start_icc.bat -o start_icc.bat
```

Use `curl.exe` (not `curl`) so it also works in PowerShell. Start Docker Desktop first.

### Open the desktop

After startup, open the printed URL in your browser (defaults):

```
http://localhost:80/?password=abc123
```

Your designs are stored on the host in `~/eda/designs` (`%USERPROFILE%\eda\designs` on Windows) and mounted into the container at `/foss/designs`.

The first start downloads the image, which takes a while. The compressed download is several GB and the extracted image needs roughly 15-20 GB of disk space (the upstream documentation mentions about 4 GB compressed and about 20 GB extracted).

---

## How the start script works

Run `./start_icc.sh` and it looks at the current state of the container:

| Container state | What you are asked |
|---|---|
| **Does not exist** | Nothing. It checks for a newer image, creates the container and starts it. |
| **Stopped** | `s` = start, `r` = remove |
| **Running** | `s` = stop, `r` = stop and remove |

Things it does for you:

- **Update check on start.** When you press `s` on a stopped container, the script pulls the image first. If the container was created from an older image, it is removed and re-created from the newer one. If you are offline, it warns you and uses the local image.
- **Startup check.** After starting, it watches the container for a few seconds and prints the last log lines if it crashes, instead of silently printing a URL for a dead container.
- **Dry run.** Prints the commands instead of executing them.
- **Host-specific fixes.** Adds the SELinux label option on SELinux hosts and the OpenSSL workaround on Apple Silicon.

### Changing settings

Every setting has a default in the script and can be overridden from the terminal.

| Variable | Default | Meaning |
|---|---|---|
| `IMAGE` | `stralax/iic-osic-tools:latest` | Image to run |
| `NAME` | `iic-osic-tools_xvnc_uid_<uid>` | Container name |
| `DESIGNS` | `~/eda/designs` | Designs folder on the host |
| `WEB_PORT` | `80` | Browser (noVNC) port |
| `VNC_PORT` | `5901` | Port for VNC clients |
| `VNC_PW` | `abc123` | VNC password |
| `XKB_KEYBOARD_LAYOUT` | `si` | Keyboard layout (`si`, `us`, `de`, ...) |
| `DRY_RUN` | *(empty)* | Any value = print commands only |

Linux / macOS:

```bash
XKB_KEYBOARD_LAYOUT=us WEB_PORT=8080 ./start_icc.sh
DRY_RUN=1 ./start_icc.sh
```

Windows (cmd):

```bat
set WEB_PORT=8080 && start_icc.bat
set DRY_RUN=1 && start_icc.bat
```

> **Note:** settings are applied when the container is *created*. To apply new settings to an existing container, press `r` to remove it and run the script again.

---

## Checking that SPICE OPUS works

Open a terminal inside the container and run:

```bash
spiceopus
```

A small test circuit (`rc.cir`):

```
* rc.cir
V1 in 0 DC 5
R1 in out 1k
C1 out 0 1u
.end
```

In the SPICE OPUS console: `source rc.cir`, then `op`, then `print v(out)`. The expected value is 5 V.

The package also ships examples and documentation in `/usr/lib/spiceopus/documentation` (for example `getstarted.html` and `amplifier.cir`).

---

## Platform support

| System | Works | Notes |
|---|---|---|
| Linux (Docker) | Yes | User must be in the `docker` group. |
| macOS Intel | Yes | Docker Desktop. |
| macOS Apple Silicon | Yes | Otherwise it runs under emulation or fails. |
| Windows, `start_icc.bat` | Yes | Docker Desktop. The file must have CRLF line endings. |
| Windows, `start_icc.sh` | Yes | Inside WSL or Git Bash. |

---

## Troubleshooting and cleanup

- **Port 80 is in use:** start with `WEB_PORT=8080`.
- **Container stops right after start:** the script prints the last log lines. You can also run `docker logs <container name>`.
- **Free up disk space:**
  ```bash
  docker image prune        # remove untagged images
  docker container prune    # remove stopped containers
  docker system df          # show what can be reclaimed
  ```
  An image cannot be removed while a container (even a stopped one) still uses it. Remove the container first.

---

## Licenses and credits

- The start scripts are modeled after `start_vnc.sh` / `start_vnc.bat` from the [IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS) project by Harald Pretl and Georg Zachl (Johannes Kepler University), published under the **Apache License 2.0**. They have been modified and simplified.
- **SPICE OPUS** is developed at the Faculty of Electrical Engineering, University of Ljubljana. See <https://fides.fe.uni-lj.si/spice/> for documentation and its license terms.
- The upstream tools in the image keep their own licenses.

Before making the Docker Hub repository public, check that the SPICE OPUS license allows redistribution.