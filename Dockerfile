FROM binhex/arch-int-gui:latest
LABEL org.opencontainers.image.authors="Toetje585"
LABEL org.opencontainers.image.source="https://github.com/winegameservers/arch-fs25server"

# release tag name from buildx arg
ARG RELEASETAG

# arch from buildx --platform, e.g. amd64
ARG TARGETARCH

ADD build/*.conf /etc/supervisor/conf.d/

# add install bash script
ADD build/root/*.sh /root/

# add bash script to run app
ADD run/nobody/*.sh /usr/local/bin/

# add custom bootstrap + health scripts
ADD scripts/*.sh /usr/local/bin/

# add pre-configured config files for nobody
ADD config/nobody/ /home/nobody/.build/

# add rootfs files

COPY build/rootfs /

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh && \
	/bin/bash /root/install.sh "${RELEASETAG}" "${TARGETARCH}" && \
	chmod +x /usr/local/bin/fs25-bootstrap.sh /usr/local/bin/fs25-healthcheck.sh

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
