#!/usr/bin/env bash
# 用途: 在新机器上还原仓库内的 Cursor 配置
# 用法:
#   bash restore.sh                    # 备份现有配置 + 还原 (不安装扩展)
#   bash restore.sh --with-extensions  # 还原 + 批量安装扩展
#   bash restore.sh --no-backup        # 跳过备份现有配置 (适用于全新机器)
#   bash restore.sh --dry-run          # 仅打印将要执行的动作

set -euo pipefail

WITH_EXT=0
DO_BACKUP=1
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --with-extensions) WITH_EXT=1 ;;
    --no-backup)       DO_BACKUP=0 ;;
    --dry-run)         DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $arg" >&2
      exit 2
      ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
  Darwin)
    USER_DIR="$HOME/Library/Application Support/Cursor/User"
    CURSOR_BIN="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
    ;;
  Linux)
    USER_DIR="$HOME/.config/Cursor/User"
    CURSOR_BIN="$(command -v cursor || echo cursor)"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    USER_DIR="$APPDATA/Cursor/User"
    CURSOR_BIN="$(command -v cursor || echo cursor)"
    ;;
  *)
    echo "不支持的操作系统: $(uname -s)" >&2
    exit 1
    ;;
esac

DOT_CURSOR="$HOME/.cursor"

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

log()  { printf '\033[1;36m[restore]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

log "仓库目录: $REPO_DIR"
log "目标 ~/.cursor: $DOT_CURSOR"
log "目标 User 目录: $USER_DIR"

if pgrep -x "Cursor" >/dev/null 2>&1 || pgrep -x "cursor" >/dev/null 2>&1; then
  warn "检测到 Cursor 仍在运行, 建议先退出后再还原 (按 Ctrl+C 取消, 或 3 秒后继续覆盖)"
  sleep 3
fi

if [ "$DO_BACKUP" -eq 1 ]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  if [ -d "$DOT_CURSOR" ]; then
    log "备份现有 ~/.cursor -> $DOT_CURSOR.bak-$TS"
    run "mv \"$DOT_CURSOR\" \"$DOT_CURSOR.bak-$TS\""
  fi
  if [ -d "$USER_DIR" ]; then
    log "备份现有 User -> $USER_DIR.bak-$TS"
    run "mv \"$USER_DIR\" \"$USER_DIR.bak-$TS\""
  fi
fi

run "mkdir -p \"$DOT_CURSOR\" \"$USER_DIR\""

if [ -d "$REPO_DIR/dot-cursor" ]; then
  log "还原 dot-cursor/* -> ~/.cursor/"
  run "cp -Rp \"$REPO_DIR/dot-cursor/.\" \"$DOT_CURSOR/\""
else
  err "缺少 $REPO_DIR/dot-cursor"
  exit 1
fi

if [ -d "$REPO_DIR/Application-Support-Cursor-User" ]; then
  log "还原 Application-Support-Cursor-User/* -> User/"
  run "cp -Rp \"$REPO_DIR/Application-Support-Cursor-User/.\" \"$USER_DIR/\""
else
  err "缺少 $REPO_DIR/Application-Support-Cursor-User"
  exit 1
fi

# 还原 Cursor 自带的 .gitignore (备份时被改名以便提交根目录文件)
if [ -f "$DOT_CURSOR/cursor-managed.gitignore.orig" ] && [ ! -f "$DOT_CURSOR/.gitignore" ]; then
  log "恢复 ~/.cursor/.gitignore"
  run "mv \"$DOT_CURSOR/cursor-managed.gitignore.orig\" \"$DOT_CURSOR/.gitignore\""
fi

if [ "$WITH_EXT" -eq 1 ]; then
  EXT_LIST="$REPO_DIR/extensions.txt"
  if [ ! -f "$EXT_LIST" ]; then
    warn "未找到 extensions.txt, 跳过扩展安装"
  elif [ ! -x "$CURSOR_BIN" ] && ! command -v "$CURSOR_BIN" >/dev/null 2>&1; then
    warn "未找到 cursor CLI ($CURSOR_BIN), 跳过扩展安装"
    warn "请手动: while read l; do cursor --install-extension \"\$l\"; done < extensions.txt"
  else
    EXT_COUNT=$(grep -cv '^$' "$EXT_LIST" || true)
    log "开始安装扩展 (共 $EXT_COUNT 个)"
    FAILED=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] $CURSOR_BIN --install-extension $line"
      else
        if ! "$CURSOR_BIN" --install-extension "$line" >/dev/null 2>&1; then
          warn "安装失败: $line"
          FAILED+=("$line")
        else
          printf '.'
        fi
      fi
    done < "$EXT_LIST"
    [ "$DRY_RUN" -eq 0 ] && echo
    if [ "${#FAILED[@]}" -gt 0 ]; then
      warn "失败列表 (${#FAILED[@]} 个):"
      printf '  - %s\n' "${FAILED[@]}"
    fi
  fi
else
  log "未指定 --with-extensions, 跳过扩展安装"
  log "如需安装扩展: bash restore.sh --with-extensions"
fi

log "完成. 请打开 Cursor 并重新登录账户 (登录态故意未打包)."
