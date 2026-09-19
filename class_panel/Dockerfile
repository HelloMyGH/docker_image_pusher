# syntax=docker/dockerfile:1

# ---------- 构建阶段 ----------
FROM rust:bookworm AS builder
WORKDIR /app

# 国内 cargo 源加速
COPY .cargo .cargo

# 先只拷 Cargo.toml 并下载依赖源码（此层可被缓存，仅依赖下载）
COPY Cargo.toml ./
RUN mkdir -p src \
 && echo 'fn main() {}' > src/main.rs \
 && cargo fetch

# 拷贝全部真实源码（覆盖 dummy main.rs）后一次性完整编译
COPY src ./src/
COPY static ./static/
RUN cargo build --release

# 硬性断言：真实二进制含 axum/tokio/reqwest，体积必然 > 5MB；
# 若仍是 400 多 KB 的 dummy，构建直接失败，杜绝产出假镜像
RUN size=$(stat -c%s target/release/class-panel) \
 && echo "built binary size: $size bytes" \
 && test "$size" -gt 5000000

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
