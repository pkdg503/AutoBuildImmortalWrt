#!/bin/bash
# ImmortalWrt 定制编译脚本 v3.1
# 功能：支持主机名设置/固件大小定制/Docker可选
# 特点：完整错误检查/日志记录/参数验证

set -eo pipefail  # 启用严格错误检查模式

# ======================
# 1. 全局配置
# ======================
LOGFILE="/tmp/build-$(date +%Y%m%d%H%M%S).log"
CONFIG_DIR="/home/build/immortalwrt/files/etc/config"
HOSTNAME_CONFIG="$CONFIG_DIR/hostname"
SYS_HOSTNAME_FILE="$CONFIG_DIR/sys_hostname"

# 默认参数设置
DEFAULT_PROFILE_SIZE="256"         # 默认固件大小(MB)
DEFAULT_HOSTNAME="ImmortalWrt"     # 默认主机名
MIN_PROFILE_SIZE="128"             # 最小固件大小
MAX_PROFILE_SIZE="2048"            # 最大固件大小

# 环境变量默认值
export PROFILE=${PROFILE:-$DEFAULT_PROFILE_SIZE}
export CUSTOM_HOSTNAME=${CUSTOM_HOSTNAME:-$DEFAULT_HOSTNAME}
export INCLUDE_DOCKER=${INCLUDE_DOCKER:-"no"}

# ======================
# 2. 初始化设置
# ======================
function init_logging() {
    mkdir -p "$(dirname "$LOGFILE")" || {
        echo "错误：无法创建日志目录" >&2
        exit 1
    }
    exec > >(tee -a "$LOGFILE") 2>&1
}

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ======================
# 3. 依赖检查
# ======================
function check_dependencies() {
    local required_commands=(
        make
        grep
        sort
        awk
        date
    )

    log "检查系统依赖..."
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log "错误：缺少必要命令 '$cmd'"
            exit 1
        fi
        log "已安装: $($cmd --version 2>&1 | head -n1)"
    done

    # 检查源码目录
    if [[ ! -f "feeds.conf.default" ]]; then
        log "错误：必须在ImmortalWrt源码根目录执行"
        exit 1
    fi
}

# ======================
# 4. 主机名配置
# ======================
function validate_hostname() {
    local hostname="$1"
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9\-]{1,63}$ ]]; then
        log "错误：无效主机名格式 - 只能包含字母数字和连字符"
        return 1
    fi
    return 0
}

function generate_hostname_config() {
    local hostname="${CUSTOM_HOSTNAME}"
    
    log "验证主机名配置..."
    if ! validate_hostname "$hostname"; then
        exit 1
    fi

    mkdir -p "$CONFIG_DIR" || {
        log "错误：无法创建配置目录 $CONFIG_DIR"
        exit 1
    }

    log "设置主机名为: $hostname"
    
    # 写入配置文件
    cat << EOF > "$HOSTNAME_CONFIG"
CUSTOM_HOSTNAME="$hostname"
EOF

    # 写入系统hostname文件
    echo "$hostname" > "$SYS_HOSTNAME_FILE" || {
        log "错误：无法写入hostname文件"
        exit 1
    }
}

# ======================
# 5. 软件包管理
# ======================
function initialize_packages() {
    declare -g -a BASE_PACKAGES=(
        "curl"
        "luci-i18n-diskman-zh-cn"
        "luci-i18n-firewall-zh-cn"
        "luci-i18n-filebrowser-zh-cn"
        "luci-app-argon-config"
        "luci-i18n-argon-config-zh-cn"
        "luci-i18n-opkg-zh-cn"
        "luci-i18n-ttyd-zh-cn"
        "openssh-sftp-server"
        "fdisk"
        "script-utils"
        "luci-i18n-samba4-zh-cn"
    )

    declare -g -a DOCKER_PACKAGES=(
        "luci-i18n-dockerman-zh-cn"
        "docker-ce"
        "dockerd"
        "docker-compose"
    )
}

function check_docker_dependencies() {
    log "检查Docker内核支持..."
    if ! grep -q "CONFIG_KERNEL_CGROUP=y" .config; then
        log "错误：内核未启用cgroup支持，无法编译Docker！"
        return 1
    fi
    
    if ! grep -q "CONFIG_OVERLAY_FS=y" .config; then
        log "警告：内核未启用OverlayFS支持，Docker存储驱动可能受限"
    fi
    return 0
}

function build_package_list() {
    local packages=("${BASE_PACKAGES[@]}")
    
    if [[ "${INCLUDE_DOCKER,,}" =~ ^(yes|true|1)$ ]]; then
        log "包含Docker支持..."
        if ! check_docker_dependencies; then
            exit 1
        fi
        packages+=("${DOCKER_PACKAGES[@]}")
    fi

    # 去重处理
    mapfile -t packages < <(printf "%s\n" "${packages[@]}" | sort -u)
    echo "${packages[@]}"
}

# ======================
# 6. 固件大小验证
# ======================
function validate_profile_size() {
    local size="$1"
    
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        log "错误：固件大小必须为整数"
        return 1
    fi
    
    if (( size < MIN_PROFILE_SIZE )); then
        log "警告：固件大小 ${size}MB 小于推荐最小值 ${MIN_PROFILE_SIZE}MB"
    fi
    
    if (( size > MAX_PROFILE_SIZE )); then
        log "错误：固件大小超过最大值 ${MAX_PROFILE_SIZE}MB"
        return 1
    fi
    
    log "验证通过：使用固件大小 ${size}MB"
    echo "$size"
}

# ======================
# 7. 编译流程
# ======================
function run_compilation() {
    local profile_size="$1"
    local packages=("${@:2}")
    
    log "准备编译参数..."
    local start_time=$(date +%s)
    
    log "编译命令:"
    log "  make image \\"
    log "    PROFILE=generic \\"
    log "    PACKAGES=\"${packages[*]}\" \\"
    log "    FILES=/home/build/immortalwrt/files \\"
    log "    ROOTFS_PARTSIZE=$profile_size"
    
    log "开始编译..."
    if ! make image \
        PROFILE=generic \
        PACKAGES="${packages[*]}" \
        FILES=/home/build/immortalwrt/files \
        ROOTFS_PARTSIZE="$profile_size"; then
        log "!! 编译失败 !!"
        return 1
    fi
    
    local duration=$(( $(date +%s) - start_time ))
    log "编译成功，耗时: $((duration / 60))分$((duration % 60))秒"
    
    log "生成镜像信息:"
    ls -lh bin/targets/*/*/*.img | while read -r line; do
        log "  $line"
    done
    
    return 0
}

# ======================
# 8. 主执行流程
# ======================
function main() {
    init_logging
    
    log "=== ImmortalWrt 定制编译开始 ==="
    log "版本: v3.1"
    log "当前目录: $(pwd)"
    log "主机名: ${CUSTOM_HOSTNAME}"
    log "固件大小: ${PROFILE}MB"
    log "Docker支持: ${INCLUDE_DOCKER}"
    
    check_dependencies
    initialize_packages
    
    log "验证固件大小..."
    validated_size=$(validate_profile_size "$PROFILE") || exit 1
    
    generate_hostname_config
    
    log "构建软件包列表..."
    package_list=($(build_package_list))
    log "将安装 ${#package_list[@]} 个软件包:"
    for pkg in "${package_list[@]}"; do
        log "  - $pkg"
    done
    
    if ! run_compilation "$validated_size" "${package_list[@]}"; then
        log "编译过程出现错误，请检查日志: $LOGFILE"
        exit 1
    fi
    
    log "=== 编译成功完成 ==="
    log "详细日志已保存至: $LOGFILE"
    exit 0
}

# 启动主流程
main
