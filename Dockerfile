ARG DOCKER_VERSION=19.03.8

FROM docker:${DOCKER_VERSION} AS docker-cli

FROM lsiobase/alpine:3.12 AS build

ARG COMPOSE_VERSION

RUN \
 apk add --no-cache \
    bash \
    build-base \
    ca-certificates \
    curl \
    gcc \
    git \
    libc-dev \
    libffi-dev \
    libgcc \
    make \
    musl-dev \
    openssl \
    openssl-dev \
    python3-dev \
    py3-pip \
    zlib-dev

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

RUN \
 mkdir -p /compose && \
 if [ -z ${COMPOSE_VERSION+x} ]; then \
    COMPOSE_VERSION=$(curl -sX GET "https://api.github.com/repos/docker/compose/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]' | awk '$0="alpine-"$0'); \
 fi && \
 COMPOSE_VERSION=$(echo "$COMPOSE_VERSION" | sed 's|alpine-||') && \
 git clone https://github.com/docker/compose.git && \
 cd /compose && \
 git checkout "${COMPOSE_VERSION}" && \
 pip3 install virtualenv==16.2.0 && \
 pip3 install tox==2.9.1 && \
 PY_ARG=$(printf "$(python3 -V)" | awk '{print $2}' | awk 'BEGIN{FS=OFS="."} NF--' | sed 's|\.||g' | sed 's|^|py|g') && \
 sed -i "s|envlist = .*|envlist = ${PY_ARG},pre-commit|g" tox.ini && \
 tox --notest && \
 mkdir -p dist && \
 chmod 777 dist && \
 /compose/.tox/${PY_ARG}/bin/pip3 install -q -r requirements-build.txt && \
 echo "$(script/build/write-git-sha)" > compose/GITSHA && \
 PYINSTVER=$(cat requirements-build.txt | grep pyinstaller | sed 's|pyinstaller==|v|') && \
 git clone --single-branch --branch develop https://github.com/pyinstaller/pyinstaller.git /tmp/pyinstaller && \
 cd /tmp/pyinstaller/bootloader && \
 git checkout ${PYINSTVER} && \
 /compose/.tox/${PY_ARG}/bin/python3 ./waf configure --no-lsb all && \
 /compose/.tox/${PY_ARG}/bin/pip3 install .. && \
 cd /compose && \
 export PATH="/compose/pyinstaller:${PATH}" && \
 /compose/.tox/${PY_ARG}/bin/pyinstaller --exclude-module pycrypto --exclude-module PyInstaller docker-compose.spec && \
 ls -la dist/ && \
 ldd dist/docker-compose && \
 mv dist/docker-compose /usr/local/bin && \
 docker-compose version

############## runtime stage ##############
FROM lsiobase/alpine:3.12

ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="aptalca"

COPY --from=build /compose/docker-compose-entrypoint.sh /usr/local/bin/docker-compose-entrypoint.sh
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=build /usr/local/bin/docker-compose /usr/local/bin/docker-compose
ENTRYPOINT ["sh", "/usr/local/bin/docker-compose-entrypoint.sh"]
