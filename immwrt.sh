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

# --- 2. 工具函数 ---
color() {
    case "$1" in
        cr) echo -e "\e[1;31m${2}\e[0m" ;; cg) echo -e "\e[1;32m${2}\e[0m" ;;
        cy) echo -e "\e[1;33m${2}\e[0m" ;; cp) echo -e "\e[1;35m${2}\e[0m" ;;
    esac
}

status_info() {
    local task_name="$1" begin_time=$(date +%s) exit_code
    shift; "$@"; exit_code=$?
    printf "%s %-53s [ %s ] ==> 用时 %s 秒\n" "$(color cy "⏳ $task_name")" "" "$( [[ "$exit_code" -eq 0 ]] && color cg ✔ || color cr ✖ )" "$(($(date +%s) - begin_time))"
}

git_clone() {
    local repo_url=$1; local target_dir=${2:-${repo_url##*/}}
    git clone -q --depth=1 "$repo_url" "$target_dir" 2>/dev/null
    rm -rf "$target_dir"/{.git*,README*.md,LICENSE}
    mkdir -p package/A && mv -f "$target_dir" "package/A/"
}

# --- 3. 插件拉取与源码注入 ---
add_custom_packages() {
    echo "📦 正在注入极简插件与 TurboACC..."
    curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh

    git_clone https://github.com/sirpdboy/luci-app-ddns-go
    git_clone https://github.com/brvphoenix/luci-app-wrtbwmon
    git_clone https://github.com/brvphoenix/wrtbwmon
    git_clone https://github.com/jerrykuku/luci-theme-argon
    git_clone https://github.com/jerrykuku/luci-app-argon-config

    find package/A -type f -name "Makefile" | xargs sed -i \
        -e 's?\.\./\.\./\(lang\|devel\)?$(TOPDIR)/feeds/packages/\1?' \
        -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?'
}

# --- 4. 个人设置 (读取界面输入的 IP) ---
apply_custom_settings() {
    # 使用界面输入的 IP_ADDRESS，如果没有输入则默认 10.0.0.1
    local default_ip=${IP_ADDRESS:-10.0.0.1}
    echo "🌐 设置管理 IP 为: $default_ip"
    sed -i "s/192.168.1.1/$default_ip/g" package/base-files/files/bin/config_generate

    # 彻底清除 root 密码 (实现空密码登录)
    sed -i 's/root:[^:]*:/root::/' package/base-files/files/etc/shadow

    # TTYD 终端免密登录
    [ -f feeds/packages/utils/ttyd/files/ttyd.config ] && sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

    # 彻底禁用 IPv6
    echo "net.ipv6.conf.all.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
    echo "net.ipv6.conf.lo.disable_ipv6=1" >> package/base-files/files/etc/sysctl.conf
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

update_install_feeds() {
    ./scripts/feeds update -a >/dev/null
    ./scripts/feeds install -a >/dev/null
}

update_config_file() {
    # 彻底锁定 x86_64 架构，防止跑偏
    cat > .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
EOF

    # 追加配置文件
    [ -e "$GITHUB_WORKSPACE/$CONFIG_FILE" ] && cat "$GITHUB_WORKSPACE/$CONFIG_FILE" >> .config
    
    # 强制开启 TurboACC 子项
    {
        echo "CONFIG_PACKAGE_luci-app-turboacc=y"
        echo "CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING=y"
        echo "CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_BBR_CCA=y"
        echo "CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_PDNSD=y"
        echo "CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE=y"
    } >> .config
    
    # 强制 rootfs 大小 (读取界面输入的 PART_SIZE)
    local size=${PART_SIZE:-800}
    echo "💾 设置分区大小为: ${size}MB"
    sed -i "/ROOTFS_PARTSIZE/d" .config
    echo "CONFIG_TARGET_ROOTFS_PARTSIZE=$size" >> .config
    
    make defconfig >/dev/null 2>&1
}

# --- 6. 执行入口 ---
main() {
    status_info "拉取编译源码" clone_source_code
    status_info "更新&安装插件 Feeds" update_install_feeds
    status_info "添加极简插件及注入 TurboACC" add_custom_packages
    status_info "加载个人设置 (IP/密码/IPv6)" apply_custom_settings
    status_info "锁定架构并生成最终配置" update_config_file
    echo "$(color cg "✅ 固件定制脚本运行完成！")"
}

main "$@"
