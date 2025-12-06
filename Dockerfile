FROM toetje585/arch-fs25server:latest AS upstream

FROM binhex/arch-int-gui:latest AS nss_builder
ARG NWRAPPER_VERSION=1.1.16
RUN set -euxo pipefail && \
    pacman -Syy --noconfirm && \
    pacman -S --noconfirm --needed base-devel cmake curl && \
    tmpdir=$(mktemp -d) && cd "${tmpdir}" && \
    curl -fSL "https://ftp.samba.org/pub/cwrap/nss_wrapper-${NWRAPPER_VERSION}.tar.gz" -o nss_wrapper.tar.gz && \
    tar -xzf nss_wrapper.tar.gz && cd "nss_wrapper-${NWRAPPER_VERSION}" && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr && \
    make -j"$(nproc)" && make DESTDIR=/opt/nss-wrapper install && \
    cd / && rm -rf "${tmpdir}" && \
    pacman -Scc --noconfirm

FROM binhex/arch-int-gui:latest AS deps_base
ARG FAST_INSTALL=yes
ARG SKIP_FULL_UPGRADE=yes
COPY build/root/install-packages.sh /tmp/install-packages.sh
COPY build/root/upd.sh /tmp/upd.sh
RUN set -euxo pipefail && \
    chmod +x /tmp/install-packages.sh /tmp/upd.sh && \
    FAST_INSTALL="${FAST_INSTALL}" SKIP_FULL_UPGRADE="${SKIP_FULL_UPGRADE}" /tmp/install-packages.sh && \
    rm -f /tmp/install-packages.sh /tmp/upd.sh

FROM deps_base
LABEL org.opencontainers.image.authors="Toetje585"
LABEL org.opencontainers.image.source="https://github.com/winegameservers/arch-fs25server"

# release tag name from buildx arg
ARG RELEASETAG

# arch from buildx --platform, e.g. amd64
ARG TARGETARCH
ARG PATCH_ID=dev

ENV FS25_PATCH_ID=${PATCH_ID}

ADD build/*.conf /etc/supervisor/conf.d/

# add install bash script
ADD build/root/*.sh /root/

# add bash script to run app
ADD run/nobody/*.sh /usr/local/bin/

# add custom bootstrap + health scripts
ADD scripts/*.sh /usr/local/bin/
# helper utilities keep script extensions (ts, symlink)
ADD scripts/ts /usr/local/bin/ts
ADD scripts/symlink /usr/local/bin/symlink

# add pre-configured config files for nobody
ADD config/nobody/ /home/nobody/.build/

# add rootfs files

COPY build/rootfs /

# install app
#############

# pull in the compiled nss_wrapper bits
COPY --from=nss_builder /opt/nss-wrapper/usr /usr

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh && \
	/bin/bash /root/install.sh "${RELEASETAG}" "${TARGETARCH}" && \
	chmod +x /usr/local/bin/fs25-bootstrap.sh /usr/local/bin/fs25-healthcheck.sh /usr/local/bin/init.sh /usr/local/bin/ts /usr/local/bin/symlink /usr/local/bin/utils.sh

# docker settings
#################

# env
#####

# set environment variables for user nobody
ENV HOME=/home/nobody

# set environment variable for terminal
ENV TERM=xterm

# set environment variables for language
ENV LANG=en_GB.UTF-8

# set permissions
#################

# run script to set uid, gid and permissions via custom bootstrap
CMD ["/usr/local/bin/fs25-bootstrap.sh"]
