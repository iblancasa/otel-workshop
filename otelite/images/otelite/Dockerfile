# otelite has no official container image. We package the release binary.
# https://github.com/planetf1/otelite
ARG OTELITE_VERSION=v0.1.153

FROM debian:bookworm-slim AS download
ARG OTELITE_VERSION
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) triple=x86_64-unknown-linux-gnu ;; \
      arm64) triple=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported arch $TARGETARCH" && exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/otelite.tar.xz \
      "https://github.com/planetf1/otelite/releases/download/${OTELITE_VERSION}/otelite-${triple}.tar.xz"; \
    mkdir -p /tmp/otelite && tar -xJf /tmp/otelite.tar.xz -C /tmp/otelite --strip-components=1; \
    install -m 0755 /tmp/otelite/otelite /usr/local/bin/otelite

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data
COPY --from=download /usr/local/bin/otelite /usr/local/bin/otelite
ENV OTELITE_DATA_DIR=/data
EXPOSE 3000 4317 4318
ENTRYPOINT ["otelite"]
CMD ["serve", "--addr", "0.0.0.0:3000", "--storage-path", "/data"]
