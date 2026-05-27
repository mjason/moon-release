#!/bin/bash
set -euo pipefail

# Moon installer
# Usage: curl -fsSL https://raw.githubusercontent.com/mjason/moon-release/main/install.sh | bash

INSTALL_DIR="${MOON_INSTALL_DIR:-$HOME/.moon}"
REPO="mjason/moon-release"

info()  { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || error "需要安装 curl"
command -v openssl >/dev/null 2>&1 || error "需要安装 openssl"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
  darwin) PLATFORM="macos" ;;
  linux)  PLATFORM="linux" ;;
  *)      error "不支持的平台: $OS（仅支持 macOS / Linux）" ;;
esac

case "$ARCH" in
  arm64|aarch64) ARCH_NORM="arm64" ;;
  x86_64|amd64)  ARCH_NORM="x86_64" ;;
  *)             error "不支持的架构: $ARCH" ;;
esac

case "${PLATFORM}-${ARCH_NORM}" in
  macos-arm64|linux-x86_64) ;;
  *) error "未发布的组合: ${PLATFORM}-${ARCH_NORM}（目前仅 macos-arm64 / linux-x86_64）" ;;
esac

info "检测到平台: ${PLATFORM}-${ARCH_NORM}"

info "获取最新版本..."
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
[[ -n "${TAG:-}" ]] || error "未找到发布版本"
VERSION=${TAG#v}
TARBALL="moon-${VERSION}-${PLATFORM}-${ARCH_NORM}.tar.gz"

info "下载 ${TAG}..."
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT
curl -fSL --progress-bar \
  -o "${TMP_DIR}/${TARBALL}" \
  "https://github.com/${REPO}/releases/download/${TAG}/${TARBALL}"

info "解压到 ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
tar xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"

# 只替换 release 自身的目录，保留 env 配置和数据库
for sub in bin lib releases; do
  rm -rf "${INSTALL_DIR}/${sub}"
  cp -R "${TMP_DIR}/moon/${sub}" "${INSTALL_DIR}/"
done
# erts-* 版本号会变，匹配通配符
rm -rf "${INSTALL_DIR}"/erts-*
cp -R "${TMP_DIR}"/moon/erts-* "${INSTALL_DIR}/"

# 首次安装：生成 env + run
if [[ ! -f "${INSTALL_DIR}/env" ]]; then
  info "首次安装，生成配置文件 ${INSTALL_DIR}/env ..."
  SECRET=$(openssl rand -base64 48 | tr -d '\n')
  cat > "${INSTALL_DIR}/env" <<EOF
# Moon 配置 — 编辑后用 ~/.moon/run 启动

# 必填：Python 项目目录（含 .venv），用于跑 fusion / rocket 等内核
PYTHON_PROJECT_DIR=

# SQLite 数据库路径（保存所有 Ash 配置，升级时保留）
DATABASE_PATH=${INSTALL_DIR}/moon.db

# 内部用，首次安装自动生成
SECRET_KEY_BASE=${SECRET}

# 监听端口和主机
PORT=4000
PHX_HOST=localhost
EOF

  cat > "${INSTALL_DIR}/run" <<'EOF'
#!/bin/bash
set -a
source "$(dirname "$0")/env"
set +a
exec "$(dirname "$0")/bin/moon" start
EOF
  chmod +x "${INSTALL_DIR}/run"

  info ""
  info "安装完成。下一步："
  info "  1. 编辑 ${INSTALL_DIR}/env 填好 PYTHON_PROJECT_DIR"
  info "  2. ${INSTALL_DIR}/run"
  info "  3. 浏览器打开 http://localhost:4000"
else
  info ""
  info "升级完成，已保留 env 配置和数据库。重启服务："
  info "  ${INSTALL_DIR}/run"
fi
