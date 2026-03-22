# -- Build stage --
FROM rust:1.83-slim AS builder

RUN apt-get update && apt-get install -y pkg-config && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Cargo.toml Cargo.lock* ./
# Cache dependency build with a dummy main
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release 2>/dev/null || true
RUN rm -rf src

COPY src ./src
RUN cargo build --release

# -- Runtime stage --
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/onyx-server /usr/local/bin/onyx-server

RUN mkdir -p /data
ENV ONYX_DB_PATH=/data/onyx.db
ENV ONYX_BIND=0.0.0.0:3000
ENV RUST_LOG=onyx_server=info

EXPOSE 3000

CMD ["onyx-server"]
