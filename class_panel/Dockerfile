# syntax=docker/dockerfile:1

# ---------- 构建阶段 ----------
FROM rust:bookworm AS builder
WORKDIR /app

COPY .cargo .cargo
COPY Cargo.toml Cargo.toml

# 先编译依赖（利用 Docker 层缓存，改源码不重编依赖）
RUN mkdir src && echo "fn main() {}" > src/main.rs \
 && cargo build --release 2>/dev/null || true

# 拷贝真实源码并编译
COPY src src
COPY static static
RUN cargo build --release

# ---------- 运行阶段 ----------
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/class-panel /usr/local/bin/class-panel

ENV PORTAINER_URL=http://10.22.27.32:9000
ENV ENDPOINT_MAP=pc01=3,pc02=4,pc03=6,pc04=7,pc05=8,pc06=9,pc07=10,pc08=11,pc09=12

EXPOSE 8080
CMD ["class-panel"]
