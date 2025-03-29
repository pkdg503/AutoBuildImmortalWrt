# .github/workflows/build-immortalwrt.yml
name: ImmortalWrt Build

on:
  workflow_dispatch:
    inputs:
      profile_size:
        description: '固件大小(MB) (128-2048)'
        required: true
        default: '1024'
      hostname:
        description: '设备主机名'
        required: false
        default: 'ImmortalWrt'
      enable_docker:
        description: '启用Docker支持 (yes/no)'
        required: false
        default: 'no'

env:
  REPO_URL: https://github.com/immortalwrt/immortalwrt
  BUILD_THREADS: $(nproc)
  MAX_PROFILE_SIZE: 2048

jobs:
  build:
    runs-on: ubuntu-22.04
    timeout-minutes: 120

    steps:
      - name: 1. 准备环境
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            build-essential libncurses-dev gawk git-core \
            diffstat unzip texinfo gcc-multilib chrpath socat \
            python3 python3-pip python3-dev python3-setuptools

      - name: 2. 克隆源码
        uses: actions/checkout@v4
        with:
          submodules: recursive
          path: immortalwrt

      - name: 3. 验证参数
        id: validate
        working-directory: ./immortalwrt
        run: |
          # 验证固件大小
          if [[ ${{ github.event.inputs.profile_size }} -lt 128 ]]; then
            echo "错误：固件大小不能小于128MB"
            exit 1
          fi
          if [[ ${{ github.event.inputs.profile_size }} -gt $MAX_PROFILE_SIZE ]]; then
            echo "错误：固件大小不能超过${MAX_PROFILE_SIZE}MB"
            exit 1
          fi

          # 验证主机名格式
          if ! [[ "${{ github.event.inputs.hostname }}" =~ ^[a-zA-Z0-9\-]{1,63}$ ]]; then
            echo "错误：主机名只能包含字母数字和连字符"
            exit 1
          fi

          echo "PROFILE=${{ github.event.inputs.profile_size }}" >> $GITHUB_ENV
          echo "CUSTOM_HOSTNAME=${{ github.event.inputs.hostname }}" >> $GITHUB_ENV
          echo "INCLUDE_DOCKER=${{ github.event.inputs.enable_docker }}" >> $GITHUB_ENV

      - name: 4. 更新Feeds
        working-directory: ./immortalwrt
        run: |
          ./scripts/feeds update -a
          ./scripts/feeds install -a

      - name: 5. 配置编译参数
        working-directory: ./immortalwrt
        run: |
          # 基础配置
          cat > .config <<EOF
          CONFIG_TARGET_x86=y
          CONFIG_TARGET_x86_64=y
          CONFIG_TARGET_x86_64_Generic=y
          EOF

          # 条件启用Docker
          if [[ "$INCLUDE_DOCKER" == "yes" ]]; then
            cat >> .config <<EOF
            CONFIG_PACKAGE_docker-ce=y
            CONFIG_PACKAGE_dockerd=y
            CONFIG_PACKAGE_luci-app-dockerman=y
            CONFIG_KERNEL_CGROUP=y
            CONFIG_KERNEL_CGROUP_CPUACCT=y
            CONFIG_KERNEL_CGROUP_DEVICE=y
            CONFIG_KERNEL_OVERLAY_FS=y
            EOF
          fi

          make defconfig

      - name: 6. 下载依赖
        working-directory: ./immortalwrt
        run: |
          make download -j$BUILD_THREADS
          find dl/ -size -1024c -exec rm -f {} \;

      - name: 7. 开始编译
        working-directory: ./immortalwrt
        run: |
          echo "::group::编译日志"
          make -j$BUILD_THREADS \
            PROFILE="generic" \
            PACKAGES="$(echo $PACKAGES | tr '\n' ' ')" \
            FILES="files" \
            ROOTFS_PARTSIZE="$PROFILE" \
            V=s 2>&1 | tee build.log
          echo "::endgroup::"

          # 检查编译结果
          if ! ls bin/targets/*/*/*.img 2>/dev/null; then
            echo "::error::编译失败！"
            grep -i error build.log | head -n 20
            exit 1
          fi

      - name: 8. 上传制品
        uses: actions/upload-artifact@v3
        with:
          name: immortalwrt-${{ github.run_id }}
          path: |
            immortalwrt/bin/targets/**/*.img
            immortalwrt/build.log
