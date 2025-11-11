# Farming Simulator 25 Docker Server

Dedicated Farming Simulator 25 server running inside a docker image based on ArchLinux. 
This fork now lives at https://github.com/Newskin01/arch-fs25server/ and traces its roots to https://github.com/wine-gameservers/arch-fs25server/.

## About This Fork

This tree tracks the upstream work from the wine-gameservers maintainers and applies a thin layer of automation so the image can serve as the centerpiece of a Pterodactyl egg. Their original implementation provides the Arch base image, init scripts, supervisor stack, and overall Giants UI experience—none of the enhancements below would be possible without that foundation, so sincere thanks to the upstream authors for sharing it.

## Highlights

- **Turn-key Pterodactyl experience** – `/home/container/fs-data` is treated as the single source of truth, the bootstrap migrates data automatically, and the egg ships health checks plus log-forwarding so Wings reads the right status.
- **Automated web branding** – the portal logos and XML config are patched on boot, `fs-data/media` assets sync into every Giants template, and a watchdog keeps Giants from reverting uploads.
- **Security guardrails** – strong password enforcement, optional VNC desktop, masked secrets, and helper flags such as `ALLOW_DEFAULT_PASSWORDS`, `ENABLE_VNC`, and `FS25_ALLOW_EMPTY_SERVER_PASSWORD` make intentions explicit.
- **Repeatable builds** – every push to `main` runs the GitHub Actions workflow in `.github/workflows/build.yaml`, which publishes `ghcr.io/newskin01/arch-fs25server` images tagged `latest` and with the commit SHA.

## Pre-built Images & CI

GitHub Actions (via [`build.yaml`](.github/workflows/build.yaml)) builds and pushes the container with Buildx. Images land in [GHCR](https://ghcr.io) under the lowercase name `ghcr.io/newskin01/arch-fs25server`. Each run produces two tags:

- `:latest` – tracks the tip of `main`.
- `:<commit-sha>` – immutable tag for the workflow’s source revision.

This repository contains the Docker image and bootstrap logic; the Pterodactyl egg (JSON, install script, healthchecks, and media checklist) lives in [Newskin01/pterodactyl-eggs](https://github.com/Newskin01/pterodactyl-eggs/tree/main/farming_simulator_25).

Use them directly:

```bash
docker pull ghcr.io/newskin01/arch-fs25server:latest
docker run --rm ghcr.io/newskin01/arch-fs25server:latest --help
```

The workflow also forwards `RELEASETAG=${{ github.ref_name }}` and `PATCH_ID=${{ github.run_number }}` into the build args so you can trace which automation produced a given image.

## Support

For questions or improvements specific to this fork, open an issue or pull request in [Newskin01/arch-fs25server](https://github.com/Newskin01/arch-fs25server). For upstream architectural questions or broader Farming Simulator tooling chat, refer to [wine-gameservers/arch-fs25server](https://github.com/wine-gameservers/arch-fs25server).

## Detailed additions

- **Persistent data hand-off**: the bootstrap now promotes `/home/container/fs-data` as the canonical storage root, migrates any stray `/opt/fs25` contents, and re-symlinks `/opt/fs25` on every boot. This keeps installs, configs, and saves intact across egg rebuilds.
- **Media checklist / pending loop**: the bootstrap writes `FS25_MEDIA_README.txt`, tracks a `.media_pending` flag, and idles until `FarmingSimulator2025*.exe` appears. Operators can import the egg immediately and let large downloads finish later without restart loops.
- **Portal automation**: every `dedicatedServer*.xml` and desktop shortcut is patched to respect `WEB_PORT`. Uploaded branding in `fs-data/media/` is replicated into all Giants web templates as both `.png` and `.jpg`, even if the env vars are left blank (the script auto-picks `login.*`/`main.*`/`logo.*`). A background “logo enforcer” keeps Giants from overwriting those assets and rewrites `dedicatedServer.xml` if needed.
- **Env-var bridge and secret masking**: Wings exposes `FS25_*` variables to dodge reserved names; the bootstrap maps them back to Giants’ `SERVER_*` vars. Logs now hide sensitive values and even patch the upstream `init.sh` banner so VNC/web passwords never print in plain text.
- **Health + log helpers**: alongside the original supervisor stack, the egg ships a lightweight readiness probe (`fs25-healthcheck.sh`) that pings both the web UI and gameplay port, writing `FS25_HEALTHCHECK=PASS` when the service is ready. A log forwarder tails the Giants log into `/home/container/fs-data/config/...` so Wings’ console stays in sync.
- **Security hardening**: the docker-compose file requires you to provide your own `VNC_PASSWORD`, `WEB_PASSWORD`, and `SERVER_PASSWORD`; the bootstrap enforces these values (unless you explicitly set `ALLOW_DEFAULT_PASSWORDS=yes`), TigerVNC is disabled by default and refuses to start unless the password is at least 8 characters, and the wrapped Binhex init script now masks any password log lines. Use `FS25_ALLOW_EMPTY_SERVER_PASSWORD=yes` only if you intentionally want an open server.

Everything else—from the Arch image, wine setup, Supervisor configs, to the Giants desktop experience—remains the upstream team’s work. If you rely on this egg, please consider starring or contributing to the [wine-gameservers/arch-fs25server](https://github.com/wine-gameservers/arch-fs25server) repository as thanks.

## Table of contents
<!-- vim-markdown-toc GFM -->
* [Highlights](#highlights)
* [Pre-built Images & CI](#pre-built-images--ci)
* [Support](#support)
* [Detailed additions](#detailed-additions)
* [Motivation](#motivation)
* [Getting Started](#getting-started)
	* [Hardware Requirements](#hardware-requirements)
	* [Software Requirements](#software-requirements)
		* [Linux Distribution](#linux-distribution)
		* [Server License](#server-license)
		* [VNC Client](#vnc-client)
* [Deployment](#deployment)
	* [Deploying with docker-compose](#docker-compose)
	* [Deploying with docker run](#docker-run)
* [Installation](#installation)
		* [Initial installation](#initial-installation)
			* [Downloading the dedicated server](#downloading-the-dedicated-server)
			* [Preparing the needed directories on the host machine](#preparing-the-needed-directories-on-the-host-machine)
			* [Unpack and move the installer](#unpack-and-move-the-installer)
			* [Starting the container](#starting-the-container)
			* [Connecting to the VNC Server](#connecting-to-the-vnc-server)
	* [Server Installation](#server-installation)
		* [Running the installation](#running-the-installation)
		* [Starting the admin portal](#starting-the-admin-portal)
* [Environment variables](#environment-variables)
<!-- vim-markdown-toc -->

# Motivation

GIANTS Software encourages its customers to consider renting a server from one of their verified partners, as it helps protect their business and maintain close relationships with these partners. Unfortunately, they do not allow third parties to host servers in order to support their partner network effectively.

For customers who prefer running personal servers, there is a requirement to purchase all the game content (game, DLC, packs) twice. This means obtaining one license for the player and another license specifically for the server.

While renting a server remains a viable option for certain players, it has become increasingly common for game developers to provide free-to-use server tools. Regrettably, the server tools provided by GIANTS Software are considered outdated and inefficient. As a result, users are compelled to set up an entire Windows environment. However, with our project, we have overcome this limitation by enabling users to deploy servers within a lightweight Docker environment, eliminating the need for a Windows setup.

# Getting Started

Please note that this may not cover every possible scenario, particularly for NAS (synology) users. In such cases, you may need to utilize the provided admin console to configure the necessary directories and user permissions. If you encounter any issues while attempting to run the program, kindly open an issue in this repository so others can benefit from the discussion.

## Hardware Requirements

Intel: Haswell or newer (Intel Celeron specially from older generations are not recommended)
AMD: Zen1 or newer

- Server for 2-4 players (without DLCs) 2.4 GHz (min. 3 Cores), 4 GB RAM
- Server for 5-10 players (with DLCs) 2.8 GHz (min. 3 Cores), 8 GB RAM
- Server for up to 16 players (with all DLCs) 3.2 GHz (min. 4 Cores), 12 GB RAM

Storage
- Base game only: Over 50 GB
- With all DLCs (as of November 2025): Over 65 GB

*Actual size may vary depending on installed DLCs and mods.*

## Software Requirements

### Linux Distribution

To install Docker and Docker Compose, please consult the documentation specific to your Linux distribution. It's important to note that the provided image is intended for operating systems that support Docker and utilize the x86_64 / amd64 architecture. Unfortunately, arm/apple architectures are not supported.

### Server License

GIANTS Software provides a dedicated server tool with the game, which means that in order to run a server, you will need to purchase an additional license from GIANTS. It is not possible to host and play on the same server using a single license. Therefore, you will need to buy everything twice in order to both run the server and play on it.

Please note that the Steam version of the game is not supported for running as a server inside a Docker environment. However, you can use the Steam version to play on the server.

To obtain the full game and all DLCs, we recommend purchasing the Farming Simulator 25 - Year 1 Bundle. This edition provides access to all the content, and it is the most cost-effective option to unlock all the game's features. Please be cautious about other versions available, as this edition ensures the inclusion of all the content you need.

- [Farming Simulator 25 - Year 1 Bundle](https://www.farming-simulator.com/buy-now.php?lang=en&country=us&platform=pcdigital)

## Building the image

If you need a custom build (for example to pin a specific upstream release, add your own branding, or host the image privately), you can compile it directly from this repository. The multi-stage `Dockerfile` pulls the upstream Arch base, installs the Binhex GUI dependencies, layers on `nss_wrapper`, and finally copies the scripts under `run/` and `scripts/`.

1. Clone this fork (which contains the Pterodactyl-oriented patches) and move into it:
   ```bash
   git clone https://github.com/Newskin01/arch-fs25server.git
   cd arch-fs25server
   ```
2. Run a build with your preferred metadata. Buildx is recommended so you can target linux/amd64 explicitly:
   ```bash
    docker buildx build \
      --platform linux/amd64 \
      --build-arg RELEASETAG="$(date +%Y%m%d)" \
      --build-arg PATCH_ID="$(git rev-parse --short HEAD)" \
      -t your-registry/arch-fs25server:custom .
   ```
   Optional args: set `FAST_INSTALL=no` if you want `pacman` to perform a full dependency sync, or `SKIP_FULL_UPGRADE=no` to force a system upgrade during the build.
3. Push/tag as needed: `docker push your-registry/arch-fs25server:custom` or `docker load` if you built with `--output type=docker`.

Please credit the upstream maintainers if you redistribute—this repo layers conveniences on top of their excellent base image.

## Deployment

The primary distinction between `docker run` and `docker-compose` is that `docker run` relies solely on command-line instructions, whereas `docker-compose` reads configuration data from a YAML file. If you are unsure about which option to choose, I recommend opting for `docker-compose`. It provides a more organized and manageable approach to container deployment by utilizing a YAML file to define and configure multiple containers and their dependencies.

### Docker compose
```yaml
services:
  arch-fs25server:
    image: toetje585/arch-fs25server:latest
    container_name: arch-fs25server
    environment:
      - VNC_PASSWORD=<your vnc password>
      - WEB_USERNAME=<dedicated server portal username>
      - WEB_PASSWORD=<dedicated server portal password>
      - SERVER_NAME=<your server name>
      - SERVER_PASSWORD=<your game join password>
      - SERVER_ADMIN=<your server admin password>
      - SERVER_PLAYERS=16
      - SERVER_PORT=10823
      - SERVER_REGION=en
      - SERVER_MAP=MapUS
      - SERVER_DIFFICULTY=3
      - SERVER_PAUSE=2
      - SERVER_SAVE_INTERVAL=180.000000
      - SERVER_STATS_INTERVAL=31536000
      - SERVER_CROSSPLAY=true
      - PUID=<UID from user>
      - PGID=<PGID from user>
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /opt/fs25/config:/opt/fs25/config
      - /opt/fs25/game:/opt/fs25/game
      - /opt/fs25/dlc:/opt/fs25/dlc
      - /opt/fs25/installer:/opt/fs25/installer
    ports:
      - 5900:5900/tcp
      - 6080:6080/tcp
      - 7999:7999/tcp
      - 10823:10823/tcp
      - 10823:10823/udp
    cap_add:
      - SYS_NICE
    restart: unless-stopped
```

### Docker run
```yaml
$ docker run -d \
    --name arch-fs25server \
    -p 5900:5900/tcp \
    -p 6080:6080/tcp \
    -p 7999:7999/tcp \
    -p 10823:10823/tcp \
    -p 10823:10823/udp \
    -v /etc/localtime:/etc/localtime:ro \
    -v /opt/fs25/installer:/opt/fs25/installer \
    -v /opt/fs25/config:/opt/fs25/config \
    -v /opt/fs25/game:/opt/fs25/game \
    -v /opt/fs25/dlc:/opt/fs25/dlc \
    -e VNC_PASSWORD="<your vnc password>" \
    -e WEB_USERNAME="<dedicated server portal username>" \
    -e WEB_PASSWORD="<dedicated server portal password>" \
    -e SERVER_NAME="<your server name>" \
    -e SERVER_PASSWORD="your game join password" \
    -e SERVER_ADMIN="<your server admin password>" \
    -e SERVER_PLAYERS="16" \
    -e SERVER_PORT="10823" \
    -e SERVER_REGION="en" \
    -e SERVER_MAP="MapUS" \
    -e SERVER_DIFFICULTY="3" \
    -e SERVER_PAUSE="2" \
    -e SERVER_SAVE_INTERVAL="180.000000" \
    -e SERVER_STATS_INTERVAL="31536000" \
    -e SERVER_CROSSPLAY="true" \
    -e PUID=<UID from user> \
    -e PGID=<PGID from user> \
    toetje585/arch-fs25server
```
# Installation

The published GHCR image already includes the bootstrap scripts, Media README workflow, and logo sync logic. In most cases you just need to:

1. Pull the image: `docker pull ghcr.io/newskin01/arch-fs25server:latest`
2. Provide the volumes from your host (see the compose snippet above or the Pterodactyl egg instructions in [Newskin01/pterodactyl-eggs](https://github.com/Newskin01/pterodactyl-eggs/tree/main/farming_simulator_25)).
3. Set the required environment variables (`VNC_PASSWORD`, `WEB_PASSWORD`, `SERVER_PASSWORD`, etc.) either in your compose file, Helm values, or Pterodactyl egg.
4. Start the container and watch the logs for the media checklist prompt.

If you are deploying through Pterodactyl, follow the egg README in [Newskin01/pterodactyl-eggs](https://github.com/Newskin01/pterodactyl-eggs/tree/main/farming_simulator_25) for import instructions, required server variables, and the `FS25_MEDIA_README.txt` upload workflow.

If you prefer the original hands-on installation instructions from upstream, keep reading—they are preserved below for reference.

<details>
<summary><strong>Legacy manual installation guide</strong></summary>

## Initial installation

Before starting the Docker container, it is necessary to go through the initial configuration process. Unlike many other games that provide standalone server binaries, Farming Simulator does not offer this option. Instead, the required files are included in the digital download package. To obtain these files, you will need to download the full game (ZIP Version) and all DLC from the [Download Portal](https://eshop.giants-software.com/downloads.php).

We will provide more detailed instructions below, but rest assured that the installation process is a one-time requirement. If the compose file is correctly configured with the correct mount paths, you will not lose the installation or configuration files even if you remove or purge the Docker image/container.

## Install Docker and Docker Compose
You will need to have docker and docker compose on your host. You can find detailled instructions for various OS's [at Docker](https://docs.docker.com/engine/install/). If you did everything correctly, `docker -v` and `docker compose version` should output some kind of version number.

## Choosing a non-root user

It is recommended to not run your FS server as a root user and instead either create a seperate user for that or re-use a non-privileged user. You technically can use the root user, but that raises major security concerns.

Choose a name for your user. This README uses `myuser` as example. We recommend to download this Readme File, open it in some kind of text editor and replace all ocurrances of `myuser` with your chosen username. To create a new user, run

```sh
sudo adduser myuser
sudo adduser myuser docker
```
The first command creates your new user. You will be asked for a password for this user, followed by some general information you can leave blank. You might also disable password login and add ssh-keys instead, but that is out of scope for this instructions.
The second command adds your newly created user to the docker group, so it can start docker containers later on.

If you just created this user, log out and re-login using your newly created user. The remainder of this README assumes that you are logged in as `myuser`.

## Downloading the dedicated server

If you purchased the game or already have a product key you can download the game and DLCs on the host machine from GIANTS [download portal](https://eshop.giants-software.com/downloads.php). You now should have a ZIP Archive containing Farming Simulator 25.
The DLC files are often just an .exe executable. You can just download them using `curl` or `wget`, we move them into the right place later on.

## Preparing the needed directories on the host machine

To ensure that the installation remains intact even if you remove or update the Docker container, it is important to configure specific directories on the host. A common practice is to place these directories in `/opt`, although you can choose any other preferred mount point according to your needs and preferences.

The remainder of this instructions assumes, that the game is inside of the directory `/mydir`, which should not be called this way. Instead, replace all occurences of `/mydir` with the directory you chose, e.G. `/opt`.

```sh
sudo mkdir -p /mydir/fs25/{config,game,installer,dlc}
```

To enable read and write access for the user account configured in the compose file (PUID/PGID), we need to ensure that the Docker container can interact with the designated directory. This can be achieved by executing the following command, which grants the necessary permissions:

```sh
sudo chown -R myuser:myuser /mydir/fs25
```

Note, that the first `myuser` in `myuser:myuser` relates to the user's name, the second `myuser` does relate to the users primary group. If you created that user as mentioned above, the users primary group will be called like the user itself, though it might not always be this way. If your user's primary group is called different, replace the second `myuser` with that group's name.

You can see your user's id (PUID), it's primary group name and the primary group ID (PGID) using the command
```sh
id myuser
```
which will output something like
```
uid=1000(myuser) gid=1000(myuser) groups=1000(myuser),0(root),27(sudo),100(users),998(docker)
```

You will need those values for the docker compose configuration, so make a note of them.

## Unpack and move the installer

You should now unpack the installer and place the unzipped files inside the directory `/mydir/fs25/installer/`, all dlc should be placed in the directory `/mydir/fs25/dlc/` directory. If we start the docker container those directories will be accessed by the container, hence making them available for installation.

## Downloading and updating the compose file / run command.
The reccomended way to start the docker containers is using the tool docker compose. You will need to download the `docker-compose.yml` from this repository and store it on your host. You can just leave it in your users home directory or place it somewhere else, as long as you remember where you left it.

Open it in some text editor of your choice.

> **Security reminder:** The compose file now expects secrets to be sourced from your environment (or a `.env` file sitting next to `docker-compose.yml`). Before you run `docker compose up`, define at least `VNC_PASSWORD`, `WEB_PASSWORD`, and `SERVER_PASSWORD`, each with unique 8+ character strings:
> ```bash
> cat <<'EOF' > .env
> VNC_PASSWORD=change-me-vnc
> WEB_PASSWORD=change-me-web
> SERVER_PASSWORD=change-me-game
> EOF
> ```
> `docker compose` automatically loads `.env`, so you don’t have to pass the values inline.

You'll find a tree structure. Under `services > arch-fs25server > mounts` you should find a list of directories. If you downloaded the file from here and put your game files into `/opt/fs25`, you're good to go.
If you chose another directory, make shure you change the paths accordingly. If you downloaded the Instructions File and replaced the dir name, these entries should be fine:
```yaml
- /mydir/fs25/installer:/opt/fs25/installer
- /mydir/fs25/config:/opt/fs25/config
- /mydir/fs25/game:/opt/fs25/game
- /mydir/fs25/dlc:/opt/fs25/dlc
```

You'll need to set a few values under `services > arch-fs25server` as well. The checked-in compose file deliberately contains **no** hard-coded secrets; instead it references `${VNC_PASSWORD}`, `${WEB_PASSWORD}`, `${SERVER_PASSWORD}`, etc. Populate those via `.env` or exported shell variables before running `docker compose up`. You'll find explanations in the Table [Environment variables](#environment-variables).

## Starting the container

With the host directories configured and the compose file set up accordingly, you are now ready to start the container.
inside the same direcoty where the modified docker-compose.yml is located run the following command.

```bash
docker compose up -d
```
The `-d` makes your containers run in the background, so they keep running if you disconnect from your shell session. To see what's happening, you can access the container's logs with `docker compose -f`


*Tip: You can use `$docker ps` to see if the container started correctly.

## Connecting to the VNC Server

After starting the Docker container for the first time, you will need to go through the initial installation of the game and DLC using a VNC client. This will allow you to set up the game and install the necessary content within the Docker environment.

This project includes a ready-to-go VNC Client, so you won't need to download anything. Because VNC exposes a full desktop, it is now **disabled by default**—set `ENABLE_VNC=yes` (and keep your 8+ character `VNC_PASSWORD` defined) before the first boot if you need the GUI installer. You need to know the port under which you'll be able to access VNC. If you didn't change it, it should be `6080`. If you are connected to your host via ssh, get your host's IP so you can access it. Otherwise, you can use `127.0.0.1` as your IP.

Open `http://<ip>:<port>/vnc.html?resize=remote&host=<ip>&port=<port>&&autoconnect=1` in a browser of your choice, while replacing IP and Port with your values. Please nothe, that both of them occur twice! You'll be prompted for a password, which you set as environment variable `VNC_PASSWORD`.

It might happen, that the connection fails on first attempt. Go get a coffee and wait a few minutes, before making another attempt, the initial start of the container can take up to 20minutes.

You should now see a desktop environment. Double Click 'Setup' to install FS25. You'll need your FS25 Serial Number now. Wait for the installation process to complete.
After that, click 'Start Server'. This should spawn your game server and also open the web admin portal. You don't need to access it from your host, you can also navigate to `http://<ip>:7999` from another machine. The credentials are those you chose as `WEB_USERNAME` and `WEB_PASSWORD` in the `docker-compose.yml`.

</details>

# Environment variables

Getting the PUID and GUID is explained [here](https://man7.org/linux/man-pages/man1/id.1.html).

| Name | Default | Purpose |
|----------|----------|-------|
| `VNC_PASSWORD` | _required, min 8 chars_ | Password for connecting using the VNC client (only used when `ENABLE_VNC=yes`) |
| `WEB_USERNAME` | `admin` | Username for admin portal at :7999 |
| `WEB_PASSWORD` | _required, min 8 chars_ | Password for the admin portal |
| `WEB_PORT` | `7999` | HTTP port used by the Giants web portal and patched shortcuts |
| `WEB_SCHEME` | `http` | Set to `https` if you terminate TLS upstream and want the internal portal treated as secure |
| `SERVER_NAME` || Servername that will be shown in the server browser |
| `SERVER_PORT` | `10823` | Default: 10823, port that the server will listen on |
| `SERVER_PASSWORD` | _required, min 8 chars_ | The game join password (set `FS25_ALLOW_EMPTY_SERVER_PASSWORD=yes` if you truly want it blank) |
| `SERVER_ADMIN` || The server ingame admin password |
| `SERVER_REGION` | `en` | en, de, jp, pl, cz, fr, es, ru, it, pt, hu, nl, cs, ct, br, tr, ro, kr, ea, da, fi, no, sv, fc |
| `SERVER_PLAYERS` | `16` | Default: 16, amount of players allowed on the server |
| `SERVER_MAP` | `MapUS` | Default: MapUS (Elmcreek), other official maps are: MapFR (Haut-Beyleron), MapAlpine (Erlengrat) |
| `SERVER_DIFFICULTY` | `3` | Default: 3, start from scratch |
| `SERVER_PAUSE` | `2` | Default: 2, pause the server if no players are connected 1, never pause the server |
| `SERVER_SAVE_INTERVAL` | `180.000000` | Default: 180.000000, in seconds.|
| `SERVER_STATS_INTERVAL` | `31536000` | Default: 120.000000|
| `SERVER_CROSSPLAY` | `true/false` | Default: true |
| `ENABLE_VNC` | `no` | Set to `yes` when you need the TigerVNC/noVNC desktop; requires `VNC_PASSWORD` |
| `ALLOW_DEFAULT_PASSWORDS` | `no` | Set to `yes` only for lab/testing to bypass the strong-password guard |
| `FS25_ALLOW_EMPTY_SERVER_PASSWORD` | `no` | Set to `yes` if you intentionally want `SERVER_PASSWORD` unset |
| `LOGIN_LOGO` | _(auto-detect)_ | Absolute or relative path (within `/home/container/fs-data/media`) to the portal login logo |
| `BOTTOM_LOGO` | _(auto-detect)_ | Absolute or relative path to the footer logo; defaults to the `main.*` assets if unset |
| `PUID` || PUID of username used on the local machine |
| `GUID` || GUID of username used on the local machine |

> **Pterodactyl tip:** If your Wings install only exposes variables prefixed with `FS25_`, use `FS25_WEB_USERNAME`, `FS25_SERVER_PORT`, etc. The bootstrap automatically maps `FS25_*` back to their native counterparts before starting Giants.

# Support

For questions specific to this fork, please open an issue or pull request in this repository. For upstream changes or broader Farming Simulator tooling discussion, refer to the original [wine-gameservers/arch-fs25server](https://github.com/wine-gameservers/arch-fs25server) project.

# Legal disclaimer
This Docker container is not endorsed by, directly affiliated with, maintained, authorized, or sponsored by [Giants Software](https://giants-software.com) and [Farming Simulator 25](https://farming-simulator.com/). The logo [Farming Simulator 25](https://giants-software.com) are © 2025 Giants Software.
