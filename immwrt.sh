#!/bin/bash

# --- 1. 工具链缓存处理 ---
if [[ "$REBUILD_TOOLCHAIN" = 'true' ]]; then
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    [ -d ".ccache" ] && ccache_dir=".ccache"
    tar -I zstdmt -cf "$GITHUB_WORKSPACE/output/$CACHE_NAME.tzst" staging_dir/host* staging_dir/tool* $ccache_dir
    exit 0
fi

[ -d "$GITHUB_WORKSPACE/output" ] || mkdir -p "$GITHUB_WORKSPACE/output"

# --- 2. 插件拉取与注入 ---
add_custom_packages() {
    # 注入 TurboACC
    curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh

    # 拉取其他插件函数 (为了简洁，直接列出核心逻辑)
    mkdir -p package/A
    git clone --depth=1 https://github.com/sirpdboy/luci-app-ddns-go package/A/luci-app-ddns-go
    git clone --depth=1 https://github.com/brvphoenix/luci-app-wrtbwmon package/A/luci-app-wrtbwmon
    git clone --depth=1 https://github.com/brvphoenix/wrtbwmon package/A/wrtbwmon
    git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/A/luci-theme-argon
    git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/A/luci-app-argon-config
}

# --- 3. 个人设置 (动态读取界面输入) ---
apply_custom_settings() {
    # 读取界面上的 "设置默认IP地址" (变量名通常对应 workflow 中的 input id)
    # 如果读取不到界面输入，则默认使用 10.0.0.1
    local TARGET_IP=${IP_ADDR:-10.0.0.1}
    echo "⚙️  正在将管理 IP 修改为: $TARGET_IP"
    sed -i "s/192.168.1.1/$TARGET_IP/g" package/base-files/files/bin/config_generate

    # 密码设置为空
    sed -i 's/root:[^:]*:/root::/' package/base-files/files/etc/shadow

    # TTYD 免密登录
    [ -f feeds/packages/utils/ttyd/files/ttyd.config ] && sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

    # 禁用 IPv6
    echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
}

# --- 4. 架构锁定与分区大小 ---
update_config_file() {
    # 彻底清空并重写架构配置，防止选错机型
    cat > .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
EOF

    # 合并你上传的配置文件
    [ -e "$GITHUB_WORKSPACE/$CONFIG_FILE" ] && cat "$GITHUB_WORKSPACE/$CONFIG_FILE" >> .config
    
    # 强制注入 TurboACC 子项
    {
        echo "CONFIG_PACKAGE_luci-app-turboacc=y"
        echo "CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING=y"
        echo "CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_BBR_CCA=y"
    } >> .config

    # 读取界面上的 "设置rootfs大小" (PART_SIZE)
    # 注意：这里需要确保它是纯数字
    local TARGET_SIZE=${PART_SIZE:-800}
    echo "💾 正在设置固件分区大小为: ${TARGET_SIZE}MB"
    sed -i "/ROOTFS_PARTSIZE/d" .config
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$TARGET_SIZE" >> .config

    make defconfig >/dev/null 2>&1
}

# --- 5. 编译环境主流程 ---
clone_source_code() {
    REPO_URL="https://github.com/immortalwrt/immortalwrt"
    REPO_BRANCH="openwrt-24.10"
    cd /workdir
    git clone -q -b "$REPO_BRANCH" --single-branch "$REPO_URL" openwrt
    ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
    cd openwrt || exit
    echo "OPENWRT_PATH=$PWD" >>$GITHUB_ENV
}

main() {
    clone_source_code
    ./scripts/feeds update -a >/dev/null
    ./scripts/feeds install -a >/dev/null
    add_custom_packages
    apply_custom_settings
    update_config_file
    echo "✅ 动态配置完成，准备开始编译..."
}

main "$@"
