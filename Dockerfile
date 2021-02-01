FROM alpine:3.13.0

RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk --update add --no-cache \
    bash \
    zip \
    rsync \
    jq \
    yq \
    go \
    npm \
    openjdk11 \
    docker-cli \
    docker-compose

COPY . /home/fabkit

WORKDIR /home/fabkit