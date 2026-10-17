# VMNet TUN (`tun`) — Linux VPS 全局出站代理管理器

```text
 ██╗   ██╗███╗   ███╗███╗   ██╗███████╗████████╗
 ██║   ██║████╗ ████║████╗  ██║██╔════╝╚══██╔══╝
 ██║   ██║██╔████╔██║██╔██╗ ██║█████╗     ██║   
 ╚██╗ ██╔╝██║╚██╔╝██║██║╚██╗██║██╔══╝     ██║   
  ╚████╔╝ ██║ ╚═╝ ██║██║ ╚████║███████╗   ██║   
   ╚═══╝  ╚═╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   
```

**VMNet TUN (`tun`)** 是一款面向 Linux VPS（Debian / Ubuntu / Alpine Linux，支持 `amd64` 与 `arm64` 架构）的全局出站透明代理管理器。通过 Linux `TUN` 虚拟网卡与策略路由，将 VPS 本机主动发起的出站流量透明转发至官方订阅的代理节点，同时自动保护 SSH 远程管理连接与入站公网服务不断联。

---

## 一、一键安装

本仓库直接提供预编译静态安装包（`releases/tun-linux-amd64` 与 `releases/tun-linux-arm64`），无需在服务器上编译源码。

在 Linux VPS（`root` 权限）下执行以下命令即可完成安装并在安装时锁定订阅地址：

```bash
curl -fsSL https://raw.githubusercontent.com/Grandova/vmnet-tun/main/install.sh -o install-vmnet-tun.sh && bash install-vmnet-tun.sh -TUN_SUBSCRIPTION_URL="https://your-official-domain.example.com/hk/nodes.txt"
```

---

## 二、卸载与恢复默认网络

如需彻底卸载并恢复系统原始网络状态，执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Grandova/vmnet-tun/main/uninstall.sh | bash
```
