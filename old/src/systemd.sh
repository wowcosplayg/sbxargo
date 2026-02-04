# 创建专用系统用户
create_service_user() {
    local username="$1"

    # 检查用户是否已存在
    if id "$username" >/dev/null 2>&1; then
        msg "系统用户 $username 已存在"
        return 0
    fi

    # 创建系统用户（无登录shell，无家目录）
    if useradd -r -s /sbin/nologin -M "$username" 2>/dev/null; then
        msg "成功创建系统用户: $username"
    else
        warn "创建系统用户失败: $username (可能需要 root 权限)"
        return 1
    fi

    # 设置配置文件权限
    case $username in
    sing-box)
        if [ -d "$is_conf_dir" ]; then
            chown -R "$username:$username" "$is_conf_dir" 2>/dev/null
            chmod 750 "$is_conf_dir" 2>/dev/null
            msg "已设置 $is_conf_dir 权限"
        fi
        ;;
    caddy)
        if [ -f "$is_caddyfile" ]; then
            chown "$username:$username" "$is_caddyfile" 2>/dev/null
            chmod 640 "$is_caddyfile" 2>/dev/null
            msg "已设置 $is_caddyfile 权限"
        fi
        ;;
    esac
}

install_service() {
    case $1 in
    $is_core)
        # 创建 sing-box 专用用户
        create_service_user "sing-box"

        is_doc_site=https://sing-box.sagernet.org/
        cat >/lib/systemd/system/$is_core.service <<<"
[Unit]
Description=$is_core_name Service
Documentation=$is_doc_site
After=network.target nss-lookup.target

[Service]
User=sing-box
Group=sing-box
NoNewPrivileges=true
ExecStart=$is_core_bin run -c $is_config_json -C $is_conf_dir
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$is_conf_dir
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
# 允许绑定特权端口（如 80, 443）
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target"
        ;;
    caddy)
        # 创建 caddy 专用用户
        create_service_user "caddy"

        cat >/lib/systemd/system/caddy.service <<<"
#https://github.com/caddyserver/dist/blob/master/init/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=$is_caddy_bin run --environ --config $is_caddyfile --adapter caddyfile
ExecReload=$is_caddy_bin reload --config $is_caddyfile --adapter caddyfile
TimeoutStopSec=5s
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log/caddy /var/lib/caddy
ProtectHome=true
ProtectKernelTunables=true
ProtectControlGroups=true
# 允许绑定特权端口（如 80, 443）
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target"
        ;;
    esac

    # enable, reload
    systemctl enable $1
    systemctl daemon-reload
}
