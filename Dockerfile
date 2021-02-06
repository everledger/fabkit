FROM alpine:3.13.0

RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk --update add --no-cache \
    bash \
    git \
    zip \
    rsync \
    jq \
    yq \
    go \
    npm \
    openjdk11 \
    docker-cli \
    docker-compose && \
    rm -rf \
		/usr/local/go/pkg/*/cmd \
		/usr/local/go/pkg/bootstrap \
		/usr/local/go/pkg/obj \
		/usr/local/go/pkg/tool/*/api \
		/usr/local/go/pkg/tool/*/go_bootstrap \
		/usr/local/go/src/cmd/dist/dist

ENV GOPATH /go
ENV PATH /usr/local/go/bin:$GOPATH/bin:$PATH
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

RUN go get -u github.com/onsi/ginkgo/ginkgo

ENV FABKIT_ROOT /home/fabkit

WORKDIR $FABKIT_ROOT