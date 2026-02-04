get_latest_version() {
    case $1 in
    core)
        name=$is_core_name
        url="https://api.github.com/repos/${is_core_repo}/releases/latest?v=$RANDOM"
        ;;
    sh)
        name="$is_core_name 脚本"
        url="https://api.github.com/repos/$is_sh_repo/releases/latest?v=$RANDOM"
        ;;
    caddy)
        name="Caddy"
        url="https://api.github.com/repos/$is_caddy_repo/releases/latest?v=$RANDOM"
        ;;
    esac
    latest_ver=$(_wget -qO- $url | grep tag_name | grep -E -o 'v([0-9.]+)')
    [[ ! $latest_ver ]] && {
        err "获取 ${name} 最新版本失败."
    }
    unset name url
}
download() {
    latest_ver=$2
    [[ ! $latest_ver ]] && get_latest_version $1
    # tmp dir
    tmpdir=$(mktemp -u)
    [[ ! $tmpdir ]] && {
        tmpdir=/tmp/tmp-$RANDOM
    }
    mkdir -p $tmpdir
    case $1 in
    core)
        name=$is_core_name
        tmpfile=$tmpdir/$is_core.tar.gz
        link="https://github.com/${is_core_repo}/releases/download/${latest_ver}/${is_core}-${latest_ver:1}-linux-${is_arch}.tar.gz"
        download_type="core"
        download_file
        tar zxf $tmpfile --strip-components 1 -C $is_core_dir/bin
        chmod +x $is_core_bin
        ;;
    sh)
        name="$is_core_name 脚本"
        tmpfile=$tmpdir/sh.tar.gz
        link="https://github.com/${is_sh_repo}/releases/download/${latest_ver}/code.tar.gz"
        download_type="sh"
        download_file
        tar zxf $tmpfile -C $is_sh_dir
        chmod +x $is_sh_bin ${is_sh_bin/$is_core/sb}
        ;;
    caddy)
        name="Caddy"
        tmpfile=$tmpdir/caddy.tar.gz
        # https://github.com/caddyserver/caddy/releases/download/v2.6.4/caddy_2.6.4_linux_amd64.tar.gz
        link="https://github.com/${is_caddy_repo}/releases/download/${latest_ver}/caddy_${latest_ver:1}_linux_${is_arch}.tar.gz"
        download_type="caddy"
        download_file
        tar zxf $tmpfile -C $tmpdir
        cp -f $tmpdir/caddy $is_caddy_bin
        chmod +x $is_caddy_bin
        ;;
    esac
    rm -rf $tmpdir
    unset latest_ver
}
download_file() {
    if ! _wget -t 5 -c $link -O $tmpfile; then
        rm -rf $tmpdir
        err "\n下载 ${name} 失败.\n"
    fi
    # SHA256 完整性校验
    verify_checksum "$download_type"
}

# SHA256 完整性校验函数
verify_checksum() {
    local checksum_url=""
    local checksum_file=""

    # 根据下载类型确定校验文件 URL
    case $1 in
    core)
        checksum_url="https://github.com/${is_core_repo}/releases/download/${latest_ver}/${is_core}-${latest_ver:1}-linux-${is_arch}.tar.gz.sha256sum"
        checksum_file="${is_core}-${latest_ver:1}-linux-${is_arch}.tar.gz"
        ;;
    caddy)
        checksum_url="https://github.com/${is_caddy_repo}/releases/download/${latest_ver}/caddy_${latest_ver:1}_linux_${is_arch}.tar.gz.sha256sum"
        checksum_file="caddy_${latest_ver:1}_linux_${is_arch}.tar.gz"
        ;;
    sh)
        # 脚本文件通常没有单独的校验文件，可以跳过
        msg "脚本文件跳过 SHA256 校验"
        return 0
        ;;
    esac

    # 尝试下载校验文件
    local checksum_tmpfile="$tmpdir/checksum.txt"
    if _wget -t 3 -T 10 -q "$checksum_url" -O "$checksum_tmpfile" 2>/dev/null; then
        msg "开始验证文件完整性..."

        # 提取校验值
        local expected_checksum=$(grep -i "$checksum_file" "$checksum_tmpfile" 2>/dev/null | awk '{print $1}')

        # 如果没有找到特定文件的校验值，尝试读取整个文件内容
        if [ -z "$expected_checksum" ]; then
            expected_checksum=$(head -n 1 "$checksum_tmpfile" | awk '{print $1}')
        fi

        if [ -z "$expected_checksum" ]; then
            warn "无法从校验文件中提取校验值，跳过验证"
            return 0
        fi

        # 计算实际文件的 SHA256
        if command -v sha256sum >/dev/null 2>&1; then
            local actual_checksum=$(sha256sum "$tmpfile" | awk '{print $1}')
        elif command -v shasum >/dev/null 2>&1; then
            local actual_checksum=$(shasum -a 256 "$tmpfile" | awk '{print $1}')
        else
            warn "系统中未找到 sha256sum 或 shasum 命令，跳过校验"
            return 0
        fi

        # 比较校验值（不区分大小写）
        if [ "${actual_checksum,,}" != "${expected_checksum,,}" ]; then
            rm -rf $tmpdir
            err "\n文件完整性校验失败!\n期望: $expected_checksum\n实际: $actual_checksum\n可能原因: 文件损坏或被篡改\n"
        fi

        msg "文件完整性校验通过 ✓"
    else
        warn "无法下载校验文件，跳过 SHA256 验证 (URL: $checksum_url)"
    fi

    # 清理临时校验文件
    rm -f "$checksum_tmpfile" 2>/dev/null
}
