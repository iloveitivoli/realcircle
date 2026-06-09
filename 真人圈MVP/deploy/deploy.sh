#!/usr/bin/env bash
# 真人圈 RealCircle —— 一键部署到服务器(CentOS 9 Stream / Rocky / RHEL 系)
# =============================================================================
# 用法(在 真人圈MVP/ 目录下运行):
#   方式 A(自动输密码,需 sshpass):
#     RC_SSH_PASS='你的root密码' ./deploy/deploy.sh
#   方式 B(交互输密码,过程中输入 1~数次):
#     ./deploy/deploy.sh
#
# 可选环境变量:
#   RC_HOST   服务器 IP(默认 202.182.114.88)
#   RC_USER   登录用户(默认 root)
#   RC_PORT   应用端口(默认 3000,经 nginx 反代到 80)
#
# 部署内容:Node 20 + systemd 常驻服务(JSON 存储,零依赖) + nginx 反代(含 WebSocket) + 放行 80
# 密码绝不写入任何文件;仅在本机内存中用于本次 SSH。
set -euo pipefail

RC_HOST="${RC_HOST:-202.182.114.88}"
RC_USER="${RC_USER:-root}"
RC_PORT="${RC_PORT:-3000}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # 真人圈MVP 目录
CTRL="/tmp/rc-ssh-%r@%h:%p"

echo "▶ 部署目标: ${RC_USER}@${RC_HOST}  (应用端口 ${RC_PORT} → nginx 80)"

# ---- SSH/SCP 封装:有 sshpass+密码则自动,否则交互;用 ControlMaster 复用连接只认证一次 ----
SSH_BASE=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o ControlMaster=auto -o ControlPath="$CTRL" -o ControlPersist=120 \
          -o PreferredAuthentications=password,publickey)
if command -v sshpass >/dev/null 2>&1 && [ -n "${RC_SSH_PASS:-}" ]; then
  RUN_SSH() { sshpass -p "$RC_SSH_PASS" ssh "${SSH_BASE[@]}" "$@"; }
  RUN_SCP() { sshpass -p "$RC_SSH_PASS" scp "${SSH_BASE[@]}" "$@"; }
  echo "  认证: sshpass(自动)"
else
  [ -z "${RC_SSH_PASS:-}" ] && echo "  认证: 交互输入(提示时输入服务器密码;装 sshpass 并设 RC_SSH_PASS 可全自动)"
  RUN_SSH() { ssh "${SSH_BASE[@]}" "$@"; }
  RUN_SCP() { scp "${SSH_BASE[@]}" "$@"; }
fi

# ---- 1. 打包代码(排除依赖与运行时数据) ----
echo "▶ 打包代码…"
TGZ="$(mktemp -t realcircle.XXXXXX).tgz"
COPYFILE_DISABLE=1 tar -C "$HERE" \
  --exclude=node_modules --exclude=data.json --exclude='*.tmp' \
  --exclude=.test-data.json --exclude='public/uploads' \
  -czf "$TGZ" server.js storage.js liveness.js ws.js sms.js package.json public deploy 2>/dev/null
echo "  → $(du -h "$TGZ" | cut -f1)"

# ---- 2. 上传 ----
echo "▶ 上传到服务器…"
RUN_SSH "${RC_USER}@${RC_HOST}" "mkdir -p /opt/realcircle"
RUN_SCP "$TGZ" "${RC_USER}@${RC_HOST}:/opt/realcircle/app.tgz"

# ---- 3. 远程安装(一次性脚本) ----
echo "▶ 远程安装与启动…"
RUN_SSH "${RC_USER}@${RC_HOST}" RC_PORT="$RC_PORT" 'bash -s' <<'REMOTE'
set -euo pipefail
PORT="${RC_PORT:-3000}"
cd /opt/realcircle
tar xzf app.tgz && rm -f app.tgz

# Node 18+(系统自带旧版 node 时强制升级到 20)
NODE_MAJOR=$(node -v 2>/dev/null | sed -n 's/^v\([0-9]*\).*/\1/p')
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 18 ]; then
  echo "  安装 Node 20(当前: ${NODE_MAJOR:-无})…"
  dnf module reset -y nodejs >/dev/null 2>&1 || true
  dnf module disable -y nodejs >/dev/null 2>&1 || true
  curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  dnf install -y nodejs --allowerasing >/dev/null 2>&1
fi
echo "  node $(node --version)"

# systemd 常驻服务
cat >/etc/systemd/system/realcircle.service <<UNIT
[Unit]
Description=RealCircle 真人圈
After=network.target

[Service]
WorkingDirectory=/opt/realcircle
ExecStart=/usr/bin/node server.js
Environment=NODE_ENV=production
Environment=PORT=${PORT}
Environment=STORAGE=json
Environment=DATA_FILE=/opt/realcircle/data.json
Environment=ADMIN_PHONE=13800000001
Restart=always
RestartSec=2
User=root

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now realcircle >/dev/null 2>&1
systemctl restart realcircle

# nginx 反代(含 WebSocket 升级)
if ! command -v nginx >/dev/null 2>&1; then
  echo "  安装 nginx…"
  dnf install -y nginx >/dev/null 2>&1
fi
# 用极简 nginx.conf,彻底避免发行版默认 server 与我们的 default_server 在 80 端口冲突
cat >/etc/nginx/nginx.conf <<'NGINX'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;
events { worker_connections 1024; }
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on;
  keepalive_timeout 65;
  include /etc/nginx/conf.d/*.conf;
}
NGINX
cat >/etc/nginx/conf.d/realcircle.conf <<NGINX
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name _;
  client_max_body_size 25m;
  location / {
    proxy_pass http://127.0.0.1:${PORT};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
  }
}
NGINX
setsebool -P httpd_can_network_connect 1 2>/dev/null || true   # SELinux 放行反代
if nginx -t; then systemctl enable nginx >/dev/null 2>&1; systemctl restart nginx; else echo "  ⚠ nginx 配置测试失败(见上)"; fi

# 防火墙放行 80
if systemctl is-active firewalld >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

echo "  等待服务就绪…"
OK=""
for i in 1 2 3 4 5 6; do
  if curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then OK=1; break; fi
  sleep 2
done
echo "  服务状态: realcircle=$(systemctl is-active realcircle) nginx=$(systemctl is-active nginx)"
if [ -n "$OK" ]; then
  echo "  应用健康检查: $(curl -fsS http://127.0.0.1:${PORT}/api/health)"
else
  echo "  ⚠ 应用未就绪,realcircle 最近日志:"; journalctl -u realcircle -n 25 --no-pager 2>/dev/null
fi
echo "  外网入口(nginx 80): $(curl -fsS -o /dev/null -w 'HTTP %{http_code}' http://127.0.0.1/ 2>/dev/null || echo '无响应')"
REMOTE

rm -f "$TGZ"
echo ""
echo "✅ 部署完成 → http://${RC_HOST}/"
echo "   日志: ssh ${RC_USER}@${RC_HOST} 'journalctl -u realcircle -f'"
