#!/bin/bash

# --- 1. 插件拉取与注入 ---
add_custom_packages() {
    # 注入 TurboACC
    curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh

    # 创建插件存放目录
    mkdir -p package/custom
    
    # 拉取 DDNS-Go 和 Argon 主题
    git clone --depth=1 https://github.com/sirpdboy/luci-app-ddns-go package/custom/luci-app-ddns-go
    git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/custom/luci-theme-argon
    git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/custom/luci-app-argon-config

    # 注意：已按照要求删除了 wrtbwmon (流量监控) 的 git clone 命令
}

# --- 2. 个人设置 ---
apply_custom_settings() {
    # 使用 YAML 传递过来的 IP_ADDRESS 变量，如果没有则默认 10.0.0.1
    local TARGET_IP=${IP_ADDRESS:-10.0.0.1}
    echo "⚙️  正在将管理 IP 修改为: $TARGET_IP"
    sed -i "s/192.168.1.1/$TARGET_IP/g" package/base-files/files/bin/config_generate

    # 密码设置为空
    sed -i 's/root:[^:]*:/root::/' package/base-files/files/etc/shadow

    # TTYD 免密登录
    [ -f feeds/packages/utils/ttyd/files/ttyd.config ] && sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

    # 禁用 IPv6 (按照你的 .config 要求)
    echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
}

# --- 3. 架构锁定与分区大小 ---
update_config_file() {
    # 使用 YAML 传递过来的 PART_SIZE，默认改为 500
    local TARGET_SIZE=${PART_SIZE:-500}
    echo "💾 正在设置固件分区大小为: ${TARGET_SIZE}MB"

    # 修改 .config 中的分区大小
    sed -i "/CONFIG_TARGET_ROOTFS_PARTSIZE/d" .config
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$TARGET_SIZE" >> .config
    
    # 确保没有残留的流量监控配置
    sed -i '/CONFIG_PACKAGE_luci-app-wrtbwmon/d' .config
}

# --- 4. 主流程 (由于源码由 YAML 克隆，此处仅执行修改操作) ---
main() {
    # 脚本执行时已经在 $OPENWRT_PATH 目录下
    ./scripts/feeds update -a >/dev/null
    ./scripts/feeds install -a >/dev/null
    
    add_custom_packages
    apply_custom_settings
    update_config_file
    
    echo "✅ 动态配置完成，准备开始编译..."
}

main "$@"
