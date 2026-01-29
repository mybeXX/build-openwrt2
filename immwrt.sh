#!/bin/bash

# --- 1. 插件拉取 ---
add_custom_packages() {
    # 注入 TurboACC
    curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh

    # 拉取其他插件 (已删除 wrtbwmon 流量监控)
    mkdir -p package/custom
    git clone --depth=1 https://github.com/sirpdboy/luci-app-ddns-go package/custom/luci-app-ddns-go
    git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/custom/luci-theme-argon
    git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/custom/luci-app-argon-config
}

# --- 2. 基础设置 ---
apply_custom_settings() {
    # 修改管理 IP (从 YAML 传递)
    local TARGET_IP=${IP_ADDRESS:-10.0.0.1}
    echo "⚙️  正在修改管理 IP 为: $TARGET_IP"
    sed -i "s/192.168.1.1/$TARGET_IP/g" package/base-files/files/bin/config_generate

    # 密码设置为空
    sed -i 's/root:[^:]*:/root::/' package/base-files/files/etc/shadow

    # TTYD 免密登录
    [ -f feeds/packages/utils/ttyd/files/ttyd.config ] && sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

    # 禁用 IPv6
    echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
}

# --- 3. 配置文件修正 ---
update_config_file() {
    # 设置分区大小 (从 YAML 传递，默认 500)
    local TARGET_SIZE=${PART_SIZE:-500}
    echo "💾 设置固件分区为: ${TARGET_SIZE}MB"
    sed -i "/CONFIG_TARGET_ROOTFS_PARTSIZE/d" .config
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$TARGET_SIZE" >> .config

    # 彻底删除流量监控配置 (双重保险)
    sed -i '/CONFIG_PACKAGE_luci-app-wrtbwmon/d' .config
}

# --- 4. 主流程 ---
# 注意：此时脚本已经在 /workdir/openwrt 目录下运行
./scripts/feeds update -a >/dev/null
./scripts/feeds install -a >/dev/null

add_custom_packages
apply_custom_settings
update_config_file

echo "✅ 脚本执行完成"
