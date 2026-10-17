#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

REPO_RAW_BASE="${VMNET_REPO_RAW_BASE:-https://raw.githubusercontent.com/Grandova/vmnet-tun/main}"
REPO_FALLBACK_BASE="https://github.com/Grandova/vmnet-tun/raw/main"

SUB_URL="${TUN_SUBSCRIPTION_URL:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -TUN_SUBSCRIPTION_URL=*|--TUN_SUBSCRIPTION_URL=*|TUN_SUBSCRIPTION_URL=*|--url=*)
            SUB_URL="${1#*=}"
            shift
            ;;
        -TUN_SUBSCRIPTION_URL|--TUN_SUBSCRIPTION_URL|--url|-u)
            if [[ $# -lt 2 ]]; then
                err "参数 $1 缺少订阅 URL 值"
                exit 1
            fi
            SUB_URL="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

SUB_URL="${SUB_URL%\"}"
SUB_URL="${SUB_URL#\"}"
SUB_URL="${SUB_URL%\'}"
SUB_URL="${SUB_URL#\'}"

if [[ "$(id -u)" -ne 0 ]]; then
    err "请使用 root 权限运行安装脚本 (例如: sudo bash install-vmnet-tun.sh -TUN_SUBSCRIPTION_URL=\"...\")"
    exit 1
fi

if [[ -z "$SUB_URL" ]]; then
    err "必须通过 -TUN_SUBSCRIPTION_URL 指定订阅地址！"
    echo "示例:" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/Grandova/vmnet-tun/main/install.sh -o install-vmnet-tun.sh && bash install-vmnet-tun.sh -TUN_SUBSCRIPTION_URL=\"https://your-official-domain.example.com/hk/nodes.txt\"" >&2
    exit 1
fi

if [[ ! "$SUB_URL" =~ ^https?:// ]]; then
    err "订阅地址必须以 https:// 或 http:// 开头"
    exit 1
fi

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    x86_64|amd64)
        PKG_ARCH="amd64"
        ;;
    aarch64|arm64)
        PKG_ARCH="arm64"
        ;;
    *)
        err "不支持的 CPU 架构: ${ARCH_RAW} (仅支持 Linux amd64 / x86_64 与 arm64 / aarch64)"
        exit 1
        ;;
esac

info "检测到系统架构: Linux ${PKG_ARCH} (${ARCH_RAW})"

install_runtime_deps() {
    local missing=()
    command -v ip >/dev/null 2>&1 || missing+=("iproute2")
    command -v nft >/dev/null 2>&1 || missing+=("nftables")
    command -v curl >/dev/null 2>&1 || missing+=("curl")

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    info "正在检查并安装系统网络组件: ${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iproute2 nftables ca-certificates curl
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache iproute2 nftables ca-certificates curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y iproute nftables ca-certificates curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y iproute nftables ca-certificates curl
    fi
}

install_runtime_deps

if [[ ! -c /dev/net/tun ]]; then
    modprobe tun 2>/dev/null || true
fi

BIN_NAME="tun-linux-${PKG_ARCH}"
TMP_INSTALLER="/tmp/.vmnet-tun-pkg.$$"
trap 'rm -f "$TMP_INSTALLER"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || pwd)"
if [[ -f "${SCRIPT_DIR}/releases/${BIN_NAME}" ]]; then
    info "使用本地安装包: ${SCRIPT_DIR}/releases/${BIN_NAME}"
    cp -f "${SCRIPT_DIR}/releases/${BIN_NAME}" "$TMP_INSTALLER"
else
    info "正在下载 VMNet TUN (${BIN_NAME}) 安装包..."
    if ! curl -fsSL "${REPO_RAW_BASE}/releases/${BIN_NAME}" -o "$TMP_INSTALLER" 2>/dev/null; then
        curl -fsSL "${REPO_FALLBACK_BASE}/releases/${BIN_NAME}" -o "$TMP_INSTALLER"
    fi
fi

chmod 0700 "$TMP_INSTALLER"

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl stop tun.service >/dev/null 2>&1 || true
elif command -v rc-service >/dev/null 2>&1; then
    rc-service tun stop >/dev/null 2>&1 || true
fi
if [[ -f /run/tun-manager/tun.pid ]]; then
    kill "$(cat /run/tun-manager/tun.pid 2>/dev/null)" >/dev/null 2>&1 || true
    rm -f /run/tun-manager/tun.pid /run/tun-manager/tun.sock
fi

info "正在将订阅地址加密写入 /usr/local/bin/tun 二进制程序..."
"$TMP_INSTALLER" --internal-seal-url "$SUB_URL" /usr/local/bin/tun
rm -f "$TMP_INSTALLER"
chmod 0755 /usr/local/bin/tun
ok "已安装并锁定 /usr/local/bin/tun"

install -d -m 0700 /etc/tun-manager
install -d -m 0700 /var/lib/tun-manager
install -d -m 0700 /run/tun-manager

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    info "正在配置 systemd 服务 (tun.service)..."
    cat >/etc/systemd/system/tun.service <<'EOF'
[Unit]
Description=VMNet TUN — Linux VPS Global Outbound Transparent Proxy Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/tun daemon
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 0644 /etc/systemd/system/tun.service
    systemctl daemon-reload
    systemctl enable tun.service >/dev/null 2>&1 || true
    systemctl restart tun.service
    ok "systemd 服务 tun.service 已启动并设为开机自启"
elif command -v rc-service >/dev/null 2>&1; then
    info "正在配置 OpenRC 服务 (/etc/init.d/tun)..."
    cat >/etc/init.d/tun <<'EOF'
#!/sbin/openrc-run

name="VMNet TUN Daemon"
description="VMNet TUN Global Outbound Transparent Proxy Manager"
command="/usr/local/bin/tun"
command_args="daemon"
command_background="yes"
pidfile="/run/tun-manager/tun.pid"
output_log="/var/log/tun-manager.log"
error_log="/var/log/tun-manager.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --owner root:root --mode 0700 /etc/tun-manager /var/lib/tun-manager /run/tun-manager
}
EOF
    chmod 0755 /etc/init.d/tun
    rc-update add tun default >/dev/null 2>&1 || true
    rc-service tun restart
    ok "OpenRC 服务 tun 已启动并设为开机自启"
else
    info "未检测到 systemd 或 OpenRC，正在后台启动 tun daemon..."
    nohup /usr/local/bin/tun daemon >/dev/null 2>&1 &
fi

info "正在同步并解密官方订阅节点..."
if /usr/local/bin/tun update; then
    ok "订阅节点已加密缓存至本地"
else
    info "首次同步节点暂未完成，稍后可在菜单中选择 [4] 更新节点列表"
fi

echo ""
ok "VMNet TUN 安装完成！请在终端直接输入 'tun' 打开管理菜单。"
