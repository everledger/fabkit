FROM alpine:3.13.0

RUN echo "@edgecommunity https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk add --no-cache \
  bash@edgecommunity \
  gawk \
  ncurses \
  git \
  zip \
  rsync \
  jq@edgecommunity \
  yq@edgecommunity \
  go \
  npm \
  openjdk11 \
  docker-cli \
  docker-compose

ENV GOPATH /go
ENV PATH /usr/local/go/bin:$GOPATH/bin:$PATH
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

RUN rm -rf \
  /usr/lib/go/pkg/*/cmd \
  /usr/lib/go/pkg/bootstrap \
  /usr/lib/go/pkg/obj \
  /usr/lib/go/pkg/tool/*/api \
  /usr/lib/go/pkg/tool/*/go_bootstrap \
  /usr/lib/go/src/cmd/dist/dist \
  /go/pkg \
  /root/.cache

COPY . /home/fabkit
ENV FABKIT_ROOT /home/fabkit

WORKDIR $FABKIT_ROOT