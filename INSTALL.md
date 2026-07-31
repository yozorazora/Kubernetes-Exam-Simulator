# Installation Guide

This is a **one-time setup**. Once it's done, you only ever need to run
`practice.sh` or `start-exam.sh` to start a session.

Pick your OS below.

---

## Windows setup (via WSL2)

The CKA exam runs on Linux, so on Windows you'll practice inside WSL2 (Windows
Subsystem for Linux). `setup.sh` installs Linux tools, so it must be run
**inside your WSL2 Ubuntu terminal**, not PowerShell or cmd.

### 1. Install WSL2 + Ubuntu

Open PowerShell **as Administrator** and run:

```powershell
wsl --install -d Ubuntu-22.04
```

Restart your PC if prompted, then open the "Ubuntu 22.04" app from the Start
menu and finish creating your Linux username/password.

### 2. Install Docker Desktop

- Download and install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/).
- Open Docker Desktop → **Settings → Resources → WSL Integration** → enable
  integration for your Ubuntu-22.04 distro → **Apply & Restart**.
- Confirm it works from inside Ubuntu:
  ```bash
  docker info
  ```

### 3. Get this project into WSL2

Copy (or clone) this folder so it lives inside the WSL2 filesystem, e.g.:

```bash
cp -r /mnt/c/Users/<you>/Desktop/cka-simulator ~/cka-simulator
cd ~/cka-simulator
```

> You *can* run it from `/mnt/c/...` directly, but file I/O is noticeably
> slower across the Windows/Linux boundary — copying it into `~/` (the native
> Linux filesystem) is recommended.

### 4. Run setup (one time only)

```bash
bash setup.sh
```

This installs `kind`, `kubectl`, `etcdctl`, `jq` (if missing) and creates 4
local Kubernetes clusters. Takes a few minutes and needs ~8 GB RAM free.

### 5. Load the exam environment (every new terminal session)

```bash
source .exam-env
```

### You're set up. Going forward, just run:

```bash
bash start-exam.sh    # timed 2-hour exam
# or
bash practice.sh      # untimed practice mode
```

---

## macOS setup

No WSL2 needed — the Mac terminal is already Unix-based. However,
`setup.sh` only knows how to auto-install **Linux** binaries for `kind`,
`kubectl`, and `etcdctl`. On macOS you must install these tools yourself
first via Homebrew — `setup.sh` will detect they're already present and
skip its (Linux-only) download step for each one.

### 1. Install Docker Desktop for Mac

Download and install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/),
then start it and confirm:

```bash
docker info
```

### 2. Install Homebrew (if you don't have it)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Install required tools via Homebrew

```bash
brew install kind kubectl helm jq etcd
```

> `etcd` is required here specifically because it bundles `etcdctl`
> (used for Task 05 — etcd backup/restore). If you skip this,
> `setup.sh` will silently install a Linux `etcdctl` binary that
> cannot run on macOS and will fail only later, when you reach Task 05.

### 4. Get this project onto your Mac

Clone or copy this folder anywhere, e.g.:

```bash
cd ~/Desktop
# git clone <your-repo-url> cka-simulator   (once pushed to GitHub)
cd cka-simulator
```

### 5. Run setup (one time only)

```bash
bash setup.sh
```

Since `kind`, `kubectl`, `etcdctl`, and `jq` are already on your `PATH` from
Homebrew, `setup.sh` will skip its own installers and go straight to creating
the 4 local Kubernetes clusters.

### 6. Load the exam environment (every new terminal session)

```bash
source .exam-env
```

### You're set up. Going forward, just run:

```bash
bash start-exam.sh    # timed 2-hour exam
# or
bash practice.sh      # untimed practice mode
```

---

## Common prerequisites (both platforms)

| Requirement | Notes |
|-------------|-------|
| Docker Desktop | Must be running before `setup.sh` |
| 8 GB+ RAM free | 4 clusters with multiple nodes each |
| Python 3 | Used by some verification scripts |
| Helm v3 | Required for Task 24 |

---

## Every time you come back to practice

You don't need to repeat setup. Just:

```bash
cd cka-simulator        # or ~/cka-simulator on WSL2
source .exam-env
bash practice.sh         # or: bash start-exam.sh
```

If Docker Desktop was restarted, make sure it's running first
(`docker info` should succeed) — the kind clusters persist across
Docker/PC restarts as containers, so you don't need to re-run `setup.sh`
unless you've torn everything down with `teardown.sh`.

---

## Tearing down

To delete all 4 clusters and reclaim resources:

```bash
bash teardown.sh
```

Run `setup.sh` again any time to rebuild from scratch.

---

## Troubleshooting

- **`docker info` fails** — Docker Desktop isn't running, or (Windows) WSL
  integration isn't enabled for your distro.
- **`setup.sh` hangs on cluster creation** — usually not enough RAM/CPU
  allocated to Docker Desktop. Increase it in Docker Desktop → Settings →
  Resources.
- **macOS: a command fails with "Exec format error"** — you ran `setup.sh`
  before installing that tool via Homebrew, so it downloaded a Linux binary.
  Fix: `brew install <tool>` the missing one, delete the broken binary from
  `/usr/local/bin` or `/opt/homebrew/bin`, and re-run `setup.sh`.
- **Windows: everything is very slow** — you're likely running from
  `/mnt/c/...`. Copy the project into the WSL2 filesystem (`~/`) instead.
