#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [[ "$(id -u)" -ne 0 ]]; then
    err "请使用 root 权限执行卸载脚本 (例如: sudo bash uninstall.sh)"
    exit 1
fi

info "正在停止代理并恢复系统默认直连路由..."
if command -v tun >/dev/null 2>&1; then
    tun direct >/dev/null 2>&1 || true
elif [[ -x /usr/local/bin/tun ]]; then
    /usr/local/bin/tun direct >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl stop tun.service >/dev/null 2>&1 || true
    systemctl disable tun.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/tun.service
    systemctl daemon-reload >/dev/null 2>&1 || true
fi

if command -v rc-service >/dev/null 2>&1; then
    rc-service tun stop >/dev/null 2>&1 || true
    rc-update del tun default >/dev/null 2>&1 || true
    rm -f /etc/init.d/tun
fi

nft delete table inet vmnet_tun >/dev/null 2>&1 || true
while ip rule del pref 5010 >/dev/null 2>&1; do :; done
ip route flush table 501 >/dev/null 2>&1 || true
ip link delete tun0 >/dev/null 2>&1 || true

rm -f /usr/local/bin/tun
rm -rf /etc/tun-manager /var/lib/tun-manager /run/tun-manager

ok "VMNet TUN 已彻底卸载，VPS 已恢复默认直连网络状态。"
