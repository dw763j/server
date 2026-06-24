#!/usr/bin/env bash
#
# Ubuntu / Debian 系统初始化配置脚本
#
# 功能：
#   1. apt-get update / upgrade
#   2. 安装基础软件：ufw fail2ban curl wget htop vim zsh git net-tools dnsutils
#   3. 安装 Oh My Zsh（调用用户 或 root）+ 设置默认 shell 为 zsh
#   4. 安装 Docker（官方 apt 仓库）
#      https://docs.docker.com/engine/install/ubuntu/  或  /debian/
#   5. 安装 Hysteria 2（官方脚本）
#      https://v2.hysteria.network/zh/docs/getting-started/Installation/
#   6. 安装 Xray（官方脚本）
#      https://github.com/XTLS/Xray-install
#   7. 安装 Caddy（官方 apt 仓库）
#      https://caddyserver.com/docs/install#debian-ubuntu-raspbian
#   8. 配置 journald 最大日志大小为 500M
#   9. 配置 ufw 防火墙与 fail2ban
#   10. 安装 wgcf（Cloudflare WARP）→ register → generate
#
# 用法（以 root 运行）：
#   sudo bash init.sh
#
# 可通过环境变量调整行为：
#   SSH_PORT=22           指定 SSH 端口（留空则自动读取 sshd_config，默认 22）
#   ENABLE_UFW=true       是否启用 ufw（已先放行 SSH/80/443，避免自锁）
#   INSTALL_OHMYZSH=true  是否为调用用户安装 Oh My Zsh（默认 true）
#   INSTALL_WGCF=true     是否安装 wgcf（Cloudflare WARP）（默认 true）
#   JOURNAL_MAX_USE=500M  journald 最大日志大小
# 例如：
#   sudo SSH_PORT=2222 bash init.sh
#

set -euo pipefail

#==============================================================
# 可配置项
#==============================================================
SSH_PORT="${SSH_PORT:-}"                    # 留空则自动检测 sshd 端口，默认 22
ENABLE_UFW="${ENABLE_UFW:-true}"            # 是否启用 ufw 防火墙
INSTALL_OHMYZSH="${INSTALL_OHMYZSH:-true}"  # 是否为调用用户安装 Oh My Zsh
INSTALL_WGCF="${INSTALL_WGCF:-true}"        # 是否安装 wgcf（Cloudflare WARP）
JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-500M}"  # journald 最大日志大小

#==============================================================
# 颜色与日志
#==============================================================
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m';  C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'; C_BLUE=$'\033[1;34m'
else
    C_RESET=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi

log()  { echo "${C_BLUE}[*]${C_RESET} $*"; }
ok()   { echo "${C_GREEN}[✓]${C_RESET} $*"; }
warn() { echo "${C_YELLOW}[!]${C_RESET} $*"; }
die()  { echo "${C_RED}[x]${C_RESET} $*" >&2; exit 1; }
step() { echo; echo "${C_GREEN}====> $*${C_RESET}"; }

#==============================================================
# 前置检查
#==============================================================
[[ $EUID -eq 0 ]] || die "请使用 root 运行：sudo bash $0"
export DEBIAN_FRONTEND=noninteractive

# 检测发行版（用于区分 Docker 仓库 URL 与 codename）
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
else
    die "无法读取 /etc/os-release，仅支持 Ubuntu / Debian"
fi

OS_ID="${ID:-}"
VERSION_CODENAME_VAL="${VERSION_CODENAME:-}"
UBUNTU_CODENAME_VAL="${UBUNTU_CODENAME:-}"
ARCH="$(dpkg --print-architecture)"

case "$OS_ID" in
    ubuntu)
        DOCKER_URL="https://download.docker.com/linux/ubuntu"
        DOCKER_SUITE="${UBUNTU_CODENAME_VAL:-$VERSION_CODENAME_VAL}"
        ;;
    debian)
        DOCKER_URL="https://download.docker.com/linux/debian"
        DOCKER_SUITE="$VERSION_CODENAME_VAL"
        ;;
    *)
        die "不支持的发行版：$OS_ID（仅支持 ubuntu / debian）"
        ;;
esac

log "检测到系统：$OS_ID ${VERSION_CODENAME_VAL:-} ($ARCH)，Docker suite=$DOCKER_SUITE"

#==============================================================
# 1. apt update / upgrade
#==============================================================
step "1/10 更新软件包索引并升级系统"
apt-get update -y
apt-get upgrade -y

#==============================================================
# 2. 安装基础软件
#==============================================================
step "2/10 安装基础软件"
BASE_PACKAGES=(
    ufw fail2ban curl wget htop vim zsh git net-tools dnsutils
    ca-certificates gnupg apt-transport-https        # 后续添加第三方源所需
    debian-keyring debian-archive-keyring            # Caddy 官方文档要求
)
apt-get install -y "${BASE_PACKAGES[@]}"
ok "基础软件安装完成"

#---------------------------------
# 3 安装 Oh My Zsh（以调用用户身份，或 root）
#---------------------------------
if [[ "${INSTALL_OHMYZSH}" == "true" ]]; then
    _ohmyzsh_target="${SUDO_USER:-root}"

    if [[ "${_ohmyzsh_target}" == "root" ]]; then
        _home="/root"
    else
        _home="$(getent passwd "${_ohmyzsh_target}" | cut -d: -f6)"
    fi

    step "3/10 为 ${_ohmyzsh_target} 安装 Oh My Zsh（家目录：${_home}）"

    if [[ ! -d "${_home}/.oh-my-zsh" ]]; then
        if [[ "${_ohmyzsh_target}" == "root" ]]; then
            # 直接以 root 安装
            RUNZSH=no KEEP_ZSHRC=yes bash -c \
                "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
                || warn "Oh My Zsh 安装失败（已继续）"
        else
            sudo -u "${_ohmyzsh_target}" bash -c \
                'RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' \
                || warn "Oh My Zsh 安装失败（已继续）"
        fi
        ok "Oh My Zsh 安装完成"
    else
        log "Oh My Zsh 已存在，跳过安装"
    fi

    # 将目标用户的 shell 改为 zsh
    if [[ "${_ohmyzsh_target}" == "root" ]]; then
        _current_shell=$(getent passwd root | cut -d: -f7)
    else
        _current_shell=$(getent passwd "${_ohmyzsh_target}" | cut -d: -f7)
    fi
    _zsh_path="$(which zsh)"
    if [[ "${_current_shell}" != "${_zsh_path}" ]]; then
        chsh -s "${_zsh_path}" "${_ohmyzsh_target}"
        ok "已将 ${_ohmyzsh_target} 的默认 shell 改为 zsh"
    else
        log "${_ohmyzsh_target} 的默认 shell 已是 zsh"
    fi
else
    warn "INSTALL_OHMYZSH=false，跳过 Oh My Zsh 安装"
fi

#==============================================================
# 3. 安装 Docker（官方 apt 仓库）
#==============================================================
step "4/10 安装 Docker（官方 apt 仓库）"

# 移除可能冲突的旧版本包（与官方文档一致）
log "检查并移除可能冲突的旧版本 Docker 相关包"
_conflict=$(dpkg --get-selections \
    docker.io docker-compose docker-compose-v2 docker-doc \
    podman-docker containerd runc 2>/dev/null | cut -f1 || true)
if [[ -n "$_conflict" ]]; then
    # shellcheck disable=SC2086
    apt-get remove -y $_conflict || true
fi

# 清理旧的 Docker 源文件和 GPG key（避免 Signed-By 冲突）
log "清理旧的 Docker 源文件"
rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources
rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc

# 添加 Docker 官方 GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "${DOCKER_URL}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# 添加 apt 源（deb822 格式）
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: ${DOCKER_URL}
Suites: ${DOCKER_SUITE}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
ok "Docker 安装完成"

# 将调用用户加入 docker 组（免 sudo 使用 docker）
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    if ! id -nG "${SUDO_USER}" | grep -qw docker; then
        usermod -aG docker "${SUDO_USER}"
        warn "已将 ${SUDO_USER} 加入 docker 组，重新登录后生效"
    fi
fi

#==============================================================
# 4. 安装 Hysteria 2（官方脚本）
#==============================================================
step "5/10 安装 Hysteria 2（官方脚本）"
curl -fsSL https://get.hy2.sh/ -o /tmp/hy2_install.sh \
    || die "下载 Hysteria 2 安装脚本失败"
bash /tmp/hy2_install.sh || die "Hysteria 2 安装失败"
rm -f /tmp/hy2_install.sh
ok "Hysteria 2 安装完成"

#==============================================================
# 5. 安装 Xray（官方脚本）
#==============================================================
step "6/10 安装 Xray（官方脚本）"
curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
    -o /tmp/xray_install.sh || die "下载 Xray 安装脚本失败"
bash /tmp/xray_install.sh install || die "Xray 安装失败"
rm -f /tmp/xray_install.sh
ok "Xray 安装完成"

#==============================================================
# 6. 安装 Caddy（官方 apt 仓库）
#==============================================================
step "7/10 安装 Caddy（官方 apt 仓库）"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    -o /etc/apt/sources.list.d/caddy-stable.list
chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod o+r /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy
ok "Caddy 安装完成"

#==============================================================
# 7. 配置 journald 日志大小限制
#==============================================================
step "8/10 配置 journald 最大日志大小为 ${JOURNAL_MAX_USE}"
install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-limit.conf <<EOF
# 由 init.sh 生成 —— 限制 journal 最大占用
[Journal]
SystemMaxUse=${JOURNAL_MAX_USE}
RuntimeMaxUse=${JOURNAL_MAX_USE}
EOF
systemctl restart systemd-journald
ok "journald 日志大小限制已配置为 ${JOURNAL_MAX_USE}"

#==============================================================
# 8. 配置 ufw 与 fail2ban
#==============================================================
step "9/10 配置 ufw 与 fail2ban"

# fail2ban：检测 sshd 日志来源，配置正确的 backend
log "检测 sshd 日志来源..."
# 现代 Debian/Ubuntu sshd 默认只写 journald，fail2ban 默认从 /var/log/auth.log
# 读日志，两者不匹配会导致 sshd jail 失效。这里自动检测并写入 /etc/fail2ban/jail.local。
if journalctl -u ssh --no-pager -n 1 &>/dev/null; then
    log "sshd 日志来自 journald，配置 fail2ban backend = systemd"
    cat > /etc/fail2ban/jail.local <<'FAIL2BAN_EOF'
# 由 init.sh 生成 —— 从 systemd journal 读取 sshd 日志
[sshd]
backend = systemd
enabled = true
FAIL2BAN_EOF
else
    log "sshd 日志来自 syslog/auth.log，使用 fail2ban 默认 backend (auto)"
fi

systemctl enable --now fail2ban
ok "fail2ban 已启用（sshd 防护）"

# 自动检测 SSH 端口，避免 ufw 启用后自锁
if [[ -z "$SSH_PORT" ]]; then
    SSH_PORT=$(grep -iE '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null \
        | tail -1 | awk '{print $2}' || true)
    SSH_PORT="${SSH_PORT:-22}"
fi
log "SSH 端口：$SSH_PORT（ufw 将放行该端口）"

# 仅添加规则，不重置已有规则
# 如果是首次启用 ufw 才设置默认策略
if ! ufw status | grep -q "^Status: active"; then
    ufw default deny incoming
    ufw default allow outgoing
fi

ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw allow 80/tcp   comment 'Caddy HTTP'
ufw allow 443/tcp  comment 'Caddy HTTPS'
ufw allow 443/udp  comment 'Hysteria 2 QUIC'

if [[ "${ENABLE_UFW}" == "true" ]]; then
    ufw --force enable
    ok "ufw 已启用（已放行 SSH ${SSH_PORT}/tcp、80/tcp、443/tcp、443/udp）"
else
    warn "ENABLE_UFW=false，ufw 规则已配置但未启用；准备好后运行：ufw enable"
fi

#==============================================================
# 10. 安装 wgcf（WARP 客户端，Cloudflare WARP 转 WireGuard）
#==============================================================
if [[ "${INSTALL_WGCF}" == "true" ]]; then
    step "10/10 安装 wgcf（Cloudflare WARP）"

    # 映射 dpkg 架构到 wgcf 命名
    case "$ARCH" in
        amd64)  WGCF_ARCH="amd64"  ;;
        arm64)  WGCF_ARCH="arm64"  ;;
        *)      warn "wgcf 不支持该架构：$ARCH，跳过安装"
                WGCF_ARCH="" ;;
    esac

    if [[ -n "$WGCF_ARCH" ]]; then
        # 通过 GitHub API 获取最新版本号
        WGCF_VERSION=$(curl -fsSL https://api.github.com/repos/ViRb3/wgcf/releases/latest \
            | grep -oP '"tag_name":\s*"\K[^"]+' || true)
        if [[ -z "$WGCF_VERSION" ]]; then
            warn "无法获取 wgcf 最新版本，跳过安装"
        else
            WGCF_DOWNLOAD_URL="https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_${WGCF_ARCH}"
            log "下载 wgcf ${WGCF_VERSION} (linux/${WGCF_ARCH})..."
            curl -fsSL "$WGCF_DOWNLOAD_URL" -o /usr/local/bin/wgcf \
                || die "下载 wgcf 失败"
            chmod +x /usr/local/bin/wgcf
            ok "wgcf 已安装到 /usr/local/bin/wgcf"

            # 注册并生成 WireGuard 配置
            log "运行 wgcf register --accept-tos..."
            wgcf register --accept-tos || warn "wgcf register 失败（已继续）"

            log "运行 wgcf generate..."
            wgcf generate || warn "wgcf generate 失败（已继续）"

            if [[ -f wgcf-profile.conf ]]; then
                ok "wgcf-profile.conf 已生成于当前目录 $(pwd)/wgcf-profile.conf"
            fi
        fi
    fi
else
    warn "INSTALL_WGCF=false，跳过 wgcf 安装"
fi

#==============================================================
# 收尾清理
#==============================================================
apt-get autoremove -y || true

#==============================================================
# 完成
#==============================================================
echo
ok "初始化完成！"
cat <<EOF

${C_YELLOW}后续提醒：${C_RESET}
  1. Docker：若已加入 docker 组，请重新登录以免 sudo 使用 docker。
  2. Hysteria 2：编辑 /etc/hysteria/config.yaml 后
        systemctl restart hysteria-server
     （443/udp 已在 ufw 放行，如果用其他端口需自行放行）
  3. Xray：编辑 /usr/local/etc/xray/config.json 后
        systemctl restart xray
     并在 ufw 放行对应端口。
  4. Caddy：编辑 /etc/caddy/Caddyfile 后  systemctl reload caddy
     （80/443 端口已在 ufw 放行）。
  5. fail2ban：默认启用 sshd 防护，可在 /etc/fail2ban/jail.local 自定义。
  6. Oh My Zsh：已安装，重新登录后自动生效。配置文件 ~/.zshrc
  7. wgcf：已安装，配置文件 wgcf-profile.conf 在 $(pwd)/，可接入 WireGuard 使用。
EOF
