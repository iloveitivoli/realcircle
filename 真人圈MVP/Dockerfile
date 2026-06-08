# 真人圈 RealCircle — 生产镜像
FROM node:20-alpine
WORKDIR /app

# 复制运行所需文件。JSON 存储模式零第三方依赖;为支持运行时切到 PostgreSQL,
# 预装纯 JS 的 pg(仅在 STORAGE=postgres 时被 lazy require,JSON 模式不加载)。
COPY package.json ./
RUN npm install pg@^8.11.0 --omit=dev --no-save --no-package-lock && npm cache clean --force
COPY server.js storage.js liveness.js ws.js ./
COPY public ./public

ENV NODE_ENV=production
ENV PORT=3000
ENV STORAGE=json
ENV DATA_FILE=/data/data.json
VOLUME ["/data"]
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/health || exit 1

# 非 root 运行
RUN addgroup -S app && adduser -S app -G app && mkdir -p /data && chown app:app /data
USER app

CMD ["node", "server.js"]
