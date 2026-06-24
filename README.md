# Server 初始化脚本

Ubuntu / Debian 服务器一键初始化，安装基础环境与常用代理/Web 服务。

## 一行安装

```bash
curl -fsSL https://raw.githubusercontent.com/dw763j/server/main/init.sh | sudo bash
```

## 做了什么

| 步骤 | 内容 |
|------|------|
| 1 | `apt-get update && upgrade` |
| 2 | 安装基础软件：ufw fail2ban curl wget htop vim zsh git net-tools dnsutils |
| 3 | 安装 Oh My Zsh + 设置默认 shell 为 zsh |
| 4 | 安装 Docker（官方 apt 仓库）|
| 5 | 安装 Caddy（官方 apt 仓库）|
| 6 | 安装 Xray（官方脚本，以 caddy:caddy 用户运行）|
| 7 | 安装 Hysteria 2（官方脚本）|
| 8 | 配置 journald 最大日志 500M |
| 9 | 配置 ufw 防火墙 + fail2ban（自动检测 sshd 日志来源）|
| 10 | 安装 wgcf（Cloudflare WARP），下载最新版自动 register + generate |

## ufw 放行端口

- SSH（自动检测端口，默认 22）/tcp
- 80/tcp（Caddy HTTP）
- 443/tcp（Caddy HTTPS）
- 443/udp（Hysteria 2 QUIC）

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SSH_PORT` | 自动检测 | SSH 端口，ufw 放行使用 |
| `ENABLE_UFW` | `true` | 是否启用 ufw |
| `INSTALL_OHMYZSH` | `true` | 是否安装 Oh My Zsh |
| `INSTALL_WGCF` | `true` | 是否安装 wgcf（Cloudflare WARP）|
| `JOURNAL_MAX_USE` | `500M` | journald 日志上限 |

## 用法示例

```bash
# 默认安装
curl -fsSL https://raw.githubusercontent.com/dw763j/server/main/init.sh | sudo bash

# 自定义 SSH 端口
sudo SSH_PORT=2222 bash init.sh

# 先看脚本再执行
curl -fsSL https://raw.githubusercontent.com/dw763j/server/main/init.sh -o init.sh
less init.sh
sudo bash init.sh

# 不启用 ufw（先人工核对规则）
sudo ENABLE_UFW=false bash init.sh

# 跳过 wgcf
sudo INSTALL_WGCF=false bash init.sh
```

## 安装后配置

| 组件 | 配置文件 | 重启/重载 |
|------|---------|-----------|
| Docker | — | 已自动启动 |
| Hysteria 2 | `/etc/hysteria/config.yaml` | `systemctl restart hysteria-server` |
| Xray | `/usr/local/etc/xray/config.json` | `systemctl restart xray` |
| Caddy | `/etc/caddy/Caddyfile` | `systemctl reload caddy` |
| fail2ban | `/etc/fail2ban/jail.local` | `systemctl restart fail2ban` |
| wgcf | `wgcf-profile.conf`（当前目录）| 通过 WireGuard 接入，见下 |
| ufw | 脚本已配置 | `ufw status verbose` 查看 |

### wgcf (WARP) 使用

安装后会在当前目录生成 `wgcf-profile.conf`，直接接入 WireGuard：

```bash
# 安装 WireGuard 工具
apt install wireguard-tools

# 应用配置
wg-quick up wgcf-profile.conf
```

## 兼容性

- Ubuntu 22.04+ / Debian 12+
- 仅支持 amd64 / arm64