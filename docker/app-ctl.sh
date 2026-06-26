#!/bin/bash
# 多应用安装/状态控制（面板经 docker exec --user abc 调用）：
#   app-ctl.sh <appType> <install|update|status>
# 设计：微信完全委托给原 wechat-ctl.sh（逻辑零改动）；其它应用各自实现，状态 JSON 复用同一格式与文件，
# 故面板的轮询逻辑无需区分应用类型。状态文件：/config/.woc-state/status.json。
set -u

APP="${1:-wechat}"
ACTION="${2:-status}"

# 微信：原样委托，保持既有行为不变（向后兼容老实例与旧面板调用路径）
if [ "$APP" = "wechat" ]; then exec /woc/wechat-ctl.sh "$ACTION"; fi

# shellcheck source=/dev/null
. /woc/app-defs.sh
woc_app_def "$APP"

STATE_DIR="${WOC_STATE_DIR:-/config/.woc-state}"
STATUS_FILE="$STATE_DIR/status.json"

is_installed() { [ -n "${APP_BIN:-}" ] && [ -x "$APP_BIN" ]; }

write_status() {
  local phase="$1" percent="$2" message="$3" installed=false
  is_installed && installed=true
  mkdir -p "$STATE_DIR"
  cat > "$STATUS_FILE.tmp" <<EOF
{"phase":"$phase","percent":$percent,"installed":$installed,"version":"","message":"$message","updatedAt":$(date +%s)}
EOF
  mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"
}

print_status() {
  if [ -f "$STATUS_FILE" ]; then
    cat "$STATUS_FILE"
  elif is_installed; then
    echo "{\"phase\":\"done\",\"percent\":100,\"installed\":true,\"version\":\"\",\"message\":\"已就绪\",\"updatedAt\":$(date +%s)}"
  else
    echo "{\"phase\":\"idle\",\"percent\":0,\"installed\":false,\"version\":\"\",\"message\":\"未安装\",\"updatedAt\":$(date +%s)}"
  fi
}

install_telegram() {
  case "$(dpkg --print-architecture 2>/dev/null)" in
    amd64) ;;
    *) write_status error 0 "Telegram 官方仅提供 x86_64 版本，当前架构（$(dpkg --print-architecture 2>/dev/null)）不支持"; return ;;
  esac
  local work=/config/.woc-dl tmp
  tmp="$work/tg.tar.xz"
  rm -rf "$work"; mkdir -p "$work"
  write_status downloading -1 "正在下载 Telegram"
  if ! curl -fSL --retry 3 -A "Mozilla/5.0" -o "$tmp" "https://telegram.org/dl/desktop/linux"; then
    write_status error 0 "下载失败，请检查网络后重试"; rm -rf "$work"; return
  fi
  write_status extracting 92 "正在解压安装"
  local newdir="$work/x"; mkdir -p "$newdir"
  # 官方包内顶层是 Telegram/ 目录，strip 掉一层 → newdir 下直接是 Telegram + Updater
  if ! tar -xJf "$tmp" -C "$newdir" --strip-components=1 2>/dev/null; then
    write_status error 0 "解压失败，安装包可能损坏"; rm -rf "$work"; return
  fi
  if [ ! -x "$newdir/Telegram" ]; then
    write_status error 0 "解压后未找到 Telegram 可执行文件"; rm -rf "$work"; return
  fi
  write_status installing 96 "正在安装"
  rm -rf /config/telegram.old
  [ -e /config/telegram ] && mv /config/telegram /config/telegram.old
  mv "$newdir" /config/telegram
  rm -rf /config/telegram.old "$work"
  write_status done 100 "安装完成"
  pkill -f "/config/telegram/Telegram" 2>/dev/null || true
}

install_qq() {
  case "$(dpkg --print-architecture 2>/dev/null)" in
    amd64) ;;
    *) write_status error 0 "QQ 官方目前主要提供 x86_64 版本，当前架构（$(dpkg --print-architecture 2>/dev/null)）暂不支持"; return ;;
  esac
  local url="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.31/release/00e6a3e7/QQ_3.2.29_260528_amd64_01.deb"
  local work=/config/.woc-dl tmp pid total cur pct rc=1
  tmp="$work/qq.deb"
  rm -rf "$work"; mkdir -p "$work"
  
  total="$(curl -fsSLI -A "Mozilla/5.0" "$url" 2>/dev/null | tr -d '\r' | awk 'tolower($1)=="content-length:"{v=$2} END{print v}')"
  : "${total:=0}"

  write_status downloading 0 "正在下载 QQ 安装包"
  curl -fSL --retry 3 -A "Mozilla/5.0" -o "$tmp" "$url" & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "${total:-0}" -gt 0 ] 2>/dev/null; then
      cur="$(stat -c%s "$tmp" 2>/dev/null || echo 0)"
      pct=$(( cur * 90 / total ))
      [ "$pct" -gt 90 ] && pct=90
      write_status downloading "$pct" "正在下载 QQ 安装包"
    else
      write_status downloading -1 "正在下载 QQ 安装包"
    fi
    sleep 1
  done
  wait "$pid"; rc=$?
  if [ "$rc" -ne 0 ]; then
    write_status error 0 "下载失败，请检查网络后重试"
    rm -rf "$work"; return
  fi

  write_status extracting 92 "正在解压安装"
  local newroot="$work/new"
  rm -rf "$newroot"; mkdir -p "$newroot"
  if ! dpkg-deb -x "$tmp" "$newroot" 2>/dev/null; then
    write_status error 0 "解压失败，安装包可能损坏"
    rm -rf "$work"; return
  fi

  if [ ! -x "$newroot/opt/QQ/qq" ]; then
    write_status error 0 "解压后未找到 QQ 可执行文件"
    rm -rf "$work"; return
  fi

  write_status installing 96 "正在安装"
  rm -rf /config/qq.old
  [ -e /config/qq ] && mv /config/qq /config/qq.old
  mv "$newroot" /config/qq
  rm -rf /config/qq.old "$work"

  write_status done 100 "安装完成"
  pkill -f "/config/qq/opt/QQ/qq" 2>/dev/null || true
}

case "$ACTION" in
  status) print_status ;;
  install | update)
    case "$APP" in
      telegram) install_telegram ;;
      qq) install_qq ;;
      chromium) write_status done 100 "Chromium 随镜像就绪" ;; # 后续：apt 烤进镜像后即就绪
      custom)
        if is_installed; then write_status done 100 "就绪"; else write_status error 0 "请先在「数据卷」上传并配置自定义应用"; fi ;;
      *) echo "未知应用: $APP" >&2; exit 1 ;;
    esac ;;
  *) echo "用法: $0 <appType> {install|update|status}" >&2; exit 1 ;;
esac
