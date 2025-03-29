#!/bin/bash
# ImmortalWrt 定制编译脚本 v3.0
# 功能：支持主机名设置/固件大小定制/Docker可选

set -eo pipefail  # 启用严格错误检查

# ======================
# 1. 初始化配置
# ======================
LOGFILE="/tmp/build-$(date +%Y%m%d%H%M%S).log"
CONFIG_DIR="/home/build/immortalwrt/files/etc/config"
HOSTNAME_CONFIG="$CONFIG_DIR/hostname"

# 默认值设置
DEFAULT_PROFILE_SIZE="256"  # 默认固件大小(MB)
DEFAULT_HOSTNAME="ImmortalWrt"  # 默认主机名

# 创建日志目录
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

# ======================
# 2. 打印环境信息
# ======================
echo "=== 编译环境信息 ==="
date
echo "固件大小: ${PROFILE:-$DEFAULT_PROFILE_SIZE} MB"
echo "主机名: ${CUSTOM_HOSTNAME:-$DEFAULT_HOSTNAME}"
echo "Docker支持: ${INCLUDE_DOCKER:-no}"

# ======================
# 3. 生成主机名配置
# ======================
generate_hostname_config() {
    mkdir -p "$CONFIG_DIR"
    local hostname="${CUSTOM_HOSTNAME:-$DEFAULT_HOSTNAME}"
    
    # 写入主机名配置文件
    cat << EOF > "$HOSTNAME_CONFIG"
CUSTOM_HOSTNAME="$hostname"
EOF
    
    # 同时写入系统hostname文件
    echo "$hostname" > "$CONFIG_DIR/sys_hostname"
    
    echo "设置主机名为: $hostname"
}

# ======================
# 4. 包管理模块
# ======================
declare -a BASE_PACKAGES=(
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

declare -a DOCKER_PACKAGES=(
    "luci-i18n-dockerman-zh-cn"
    "docker-ce"
    "dockerd"
    "docker-compose"
)

build_package_list() {
    local packages=("${BASE_PACKAGES[@]}")
    
    # 判断是否添加Docker插件
    if [[ "${INCLUDE_DOCKER,,}" =~ ^(yes|true|1)$ ]]; then
        echo "检测到Docker支持已启用"
        packages+=("${DOCKER_PACKAGES[@]}")
        
        # 检查内核依赖
        if ! grep -q "CONFIG_KERNEL_CGROUP=y" .config; then
            echo "错误：内核未启用cgroup支持，无法编译Docker！" >&2
            exit 1
        fi
    fi
    
    # 去重处理
    IFS=$'\n' packages=($(sort -u <<< "${packages[*]}"))
    unset IFS
    
    echo "${packages[@]}"
}

# ======================
# 5. 固件大小验证
# ======================
validate_profile_size() {
    local size=${PROFILE:-$DEFAULT_PROFILE_SIZE}
    
    # 检查是否为数字
    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
        echo "错误：固件大小必须为整数！" >&2
        exit 1
    fi
    
    # 检查最小限制
    if [ "$size" -lt 128 ]; then
        echo "警告：固件大小 ${size}MB 可能过小，建议至少128MB" >&2
    fi
    
    # 检查最大限制
    if [ "$size" -gt 2048 ]; then
        echo "警告：固件大小超过2048MB，请确认设备支持！" >&2
    fi
    
    echo "使用固件大小: ${size}MB"
    echo $size
}

# ======================
# 6. 主编译流程
# ======================
main() {
    echo "=== 开始编译流程 ==="
    
    # 生成主机名配置
    generate_hostname_config
    
    # 验证固件大小
    local profile_size=$(validate_profile_size)
    
    # 构建包列表
    PACKAGES=$(build_package_list)
    echo "将安装的软件包:"
    printf " - %s\n" "${PACKAGES[@]}"
    
    # 编译参数
    local build_args=(
        "PROFILE=generic"
        "PACKAGES=\"${PACKAGES}\""
        "FILES=/home/build/immortalwrt/files"
        "ROOTFS_PARTSIZE=$profile_size"
    )
    
    echo "执行编译命令: make image ${build_args[*]}"
    
    # 开始编译
    local start_time=$(date +%s)
    if ! make image "${build_args[@]}"; then
        echo "!! 编译失败 !!" >&2
        exit 1
    fi
    local duration=$(( $(date +%s) - $start_time ))
    
    echo "=== 编译成功 ==="
    echo "耗时: $((duration / 60))分$((duration % 60))秒"
    
    # 显示生成镜像信息
    echo "生成镜像:"
    ls -lh bin/targets/*/*/*.img | awk '{print $5,$9}'
}

# 执行主流程
main
