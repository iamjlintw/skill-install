#!/usr/bin/env bash
#
# AI CLI Skill 安裝工具
# 支援 Claude Code、Codex CLI、Gemini CLI 的 Skills/Plugins 安裝管理
#
# 使用方式：
#   ./install.sh install <url|path> [--target <cli>]  安裝 skill/plugin
#   ./install.sh list [--target <cli>]                列出已安裝的 skills
#   ./install.sh update [name] [--target <cli>]       更新 skills
#   ./install.sh remove <name> [--target <cli>]       移除 skill/plugin
#   ./install.sh validate <path>                      驗證格式
#   ./install.sh help                                 顯示說明
#
# 支援的 CLI：claude (預設)、codex、gemini
#
# 作者：AI CLI Skill Install Tool
# 版本：2.0.0

set -euo pipefail

# ============================================================================
# 常數定義
# ============================================================================
readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly TEMP_DIR="${TMPDIR:-/tmp}/ai-skill-install"

# Claude Code 路徑
readonly CLAUDE_DIR="${HOME}/.claude"
readonly CLAUDE_PLUGINS_DIR="${CLAUDE_DIR}/plugins"
readonly CLAUDE_COMMANDS_DIR="${CLAUDE_DIR}/commands"

# Codex CLI 路徑
readonly CODEX_DIR="${HOME}/.codex"
readonly CODEX_SKILLS_DIR="${CODEX_DIR}/skills"

# Gemini CLI 路徑
readonly GEMINI_DIR="${HOME}/.gemini"
readonly GEMINI_EXTENSIONS_DIR="${GEMINI_DIR}/extensions"

# 預設目標 CLI
TARGET_CLI="claude"

# 顏色定義
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

# ============================================================================
# 工具函式
# ============================================================================

# 輸出成功訊息
log_success() {
  echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

# 輸出警告訊息
log_warn() {
  echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1" >&2
}

# 輸出錯誤訊息
log_error() {
  echo -e "${COLOR_RED}✗${COLOR_RESET} $1" >&2
}

# 輸出資訊
log_info() {
  echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $1"
}

# 清理暫存目錄
cleanup() {
  if [[ -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

# 設定 trap 清理
trap cleanup EXIT

# 檢查必要工具是否存在
check_dependencies() {
  local missing=()

  for cmd in git curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "缺少必要工具：${missing[*]}"
    log_info "請先安裝這些工具後再執行"
    exit 1
  fi
}

# 確保目錄存在
ensure_directories() {
  mkdir -p "${TEMP_DIR}"

  case "$TARGET_CLI" in
    claude)
      mkdir -p "${CLAUDE_PLUGINS_DIR}"
      mkdir -p "${CLAUDE_COMMANDS_DIR}"
      ;;
    codex)
      mkdir -p "${CODEX_DIR}"
      mkdir -p "${CODEX_SKILLS_DIR}"
      ;;
    gemini)
      mkdir -p "${GEMINI_DIR}"
      mkdir -p "${GEMINI_EXTENSIONS_DIR}"
      ;;
  esac
}

# 解析 --target 參數
parse_target() {
  local args=("$@")
  local i=0

  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --target|-t)
        if [[ $((i + 1)) -lt ${#args[@]} ]]; then
          TARGET_CLI="${args[$((i + 1))]}"
          # 驗證目標 CLI
          case "$TARGET_CLI" in
            claude|codex|gemini) ;;
            *)
              log_error "不支援的 CLI：$TARGET_CLI"
              log_info "支援的選項：claude, codex, gemini"
              exit 1
              ;;
          esac
        fi
        ;;
    esac
    ((i++)) || true
  done
}

# 移除 --target 參數，返回其他參數
filter_args() {
  local args=("$@")
  local result=()
  local i=0

  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --target|-t)
        ((i++)) || true  # 跳過下一個參數（值）
        ;;
      *)
        result+=("${args[$i]}")
        ;;
    esac
    ((i++)) || true
  done

  echo "${result[@]:-}"
}

# 驗證是否為有效的 Git URL
is_git_url() {
  local url="$1"
  [[ "$url" =~ ^(https?://|git@|git://) ]] || [[ "$url" =~ \.git$ ]]
}

# 從 URL 取得 plugin 名稱
get_name_from_url() {
  local url="$1"
  basename "$url" .git
}

# 從路徑取得 plugin 名稱
get_name_from_path() {
  local path="$1"
  basename "$path"
}

# 從 SKILL.md 或 command.md 檔案讀取 name
get_name_from_frontmatter() {
  local file="$1"
  local name=""

  # 檢查檔案是否存在
  if [[ ! -f "$file" ]]; then
    return 1
  fi

  # 讀取 frontmatter 中的 name 欄位
  # frontmatter 格式: ---\nkey: value\n---
  if head -1 "$file" | grep -q "^---"; then
    name=$(sed -n '/^---$/,/^---$/p' "$file" | grep -E "^name:" | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '\r')
  fi

  # 如果沒有 name，嘗試用檔案名稱（不含副檔名）
  if [[ -z "$name" ]]; then
    name=$(basename "$file" .md)
    # 如果是 SKILL.md，使用父目錄名稱或提示使用者
    if [[ "$name" == "SKILL" ]]; then
      return 1
    fi
  fi

  echo "$name"
}

# 檢查是否為 SKILL.md 檔案
is_skill_file() {
  local file="$1"
  [[ -f "$file" ]] && [[ "$(basename "$file")" == "SKILL.md" ]]
}

# 檢查是否為 command markdown 檔案
is_command_file() {
  local file="$1"
  [[ -f "$file" ]] && [[ "$file" == *.md ]] && [[ "$(basename "$file")" != "SKILL.md" ]]
}

# 檢查是否為 zip 檔案
is_zip_file() {
  local file="$1"
  [[ -f "$file" ]] && [[ "$file" == *.zip ]]
}

# ============================================================================
# 驗證函式
# ============================================================================

# 驗證 plugin 結構
validate_plugin() {
  local path="$1"
  local errors=()

  # 檢查是否為目錄
  if [[ ! -d "$path" ]]; then
    log_error "路徑不是目錄：$path"
    return 1
  fi

  # 檢查 plugin.json（可選但建議有）
  if [[ -f "${path}/.claude-plugin/plugin.json" ]]; then
    if ! jq empty "${path}/.claude-plugin/plugin.json" 2>/dev/null; then
      errors+=("plugin.json 格式無效")
    fi
  fi

  # 檢查是否有任何有效的組件
  local has_components=false

  # 檢查 commands 目錄
  if [[ -d "${path}/commands" ]]; then
    local cmd_count
    cmd_count=$(find "${path}/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$cmd_count" -gt 0 ]]; then
      has_components=true
      log_info "找到 ${cmd_count} 個命令"
    fi
  fi

  # 檢查 skills 目錄
  if [[ -d "${path}/skills" ]]; then
    local skill_count
    skill_count=$(find "${path}/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$skill_count" -gt 0 ]]; then
      has_components=true
      log_info "找到 ${skill_count} 個 skill"
    fi
  fi

  # 檢查 agents 目錄
  if [[ -d "${path}/agents" ]]; then
    local agent_count
    agent_count=$(find "${path}/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$agent_count" -gt 0 ]]; then
      has_components=true
      log_info "找到 ${agent_count} 個 agent"
    fi
  fi

  # 檢查獨立的 markdown 命令檔案（根目錄）
  local root_md_count
  root_md_count=$(find "${path}" -maxdepth 1 -name "*.md" ! -name "README.md" ! -name "CHANGELOG.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$root_md_count" -gt 0 ]]; then
    has_components=true
    log_info "找到 ${root_md_count} 個根目錄命令檔案"
  fi

  if [[ "$has_components" == false ]]; then
    errors+=("找不到任何有效的 skill/command/agent 組件")
  fi

  # 輸出錯誤
  if [[ ${#errors[@]} -gt 0 ]]; then
    log_error "驗證失敗："
    for err in "${errors[@]}"; do
      echo "  - $err"
    done
    return 1
  fi

  log_success "驗證通過"
  return 0
}

# ============================================================================
# 安裝函式
# ============================================================================

# 從 Git URL 安裝
install_from_git() {
  local url="$1"
  local name
  name=$(get_name_from_url "$url")
  local target_dir="${CLAUDE_PLUGINS_DIR}/${name}"

  log_info "正在從 Git 安裝：$url"

  # 檢查是否已安裝
  if [[ -d "$target_dir" ]]; then
    log_warn "已存在同名 plugin：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$target_dir"
  fi

  # Clone 到暫存目錄
  local temp_clone="${TEMP_DIR}/${name}"
  if ! git clone --depth 1 "$url" "$temp_clone" 2>/dev/null; then
    log_error "Git clone 失敗"
    return 1
  fi

  # 驗證結構
  if ! validate_plugin "$temp_clone"; then
    log_error "Plugin 驗證失敗，取消安裝"
    return 1
  fi

  # 移動到目標目錄
  mv "$temp_clone" "$target_dir"

  log_success "已安裝：$name"
  log_info "路徑：$target_dir"
}

# 從本地路徑安裝
install_from_local() {
  local source_path="$1"
  local name
  name=$(get_name_from_path "$source_path")
  local target_dir="${CLAUDE_PLUGINS_DIR}/${name}"

  # 轉換為絕對路徑
  source_path=$(cd "$source_path" && pwd)

  log_info "正在從本地路徑安裝：$source_path"

  # 驗證結構
  if ! validate_plugin "$source_path"; then
    log_error "Plugin 驗證失敗，取消安裝"
    return 1
  fi

  # 檢查是否已安裝
  if [[ -d "$target_dir" ]]; then
    log_warn "已存在同名 plugin：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$target_dir"
  fi

  # 複製到目標目錄
  cp -R "$source_path" "$target_dir"

  log_success "已安裝：$name"
  log_info "路徑：$target_dir"
}

# ============================================================================
# 檔案類型偵測函式
# ============================================================================

# 檢查是否為 AGENTS.md (Codex CLI)
is_agents_file() {
  local file="$1"
  [[ -f "$file" ]] && [[ "$(basename "$file")" =~ ^[Aa][Gg][Ee][Nn][Tt][Ss]?\.[Mm][Dd]$ ]]
}

# 檢查是否為 GEMINI.md (Gemini CLI)
is_gemini_file() {
  local file="$1"
  [[ -f "$file" ]] && [[ "$(basename "$file")" == "GEMINI.md" ]]
}

# 檢查是否為 gemini-extension.json
is_gemini_extension() {
  local path="$1"
  [[ -f "${path}/gemini-extension.json" ]]
}

# 自動偵測檔案/目錄屬於哪個 CLI
detect_cli_type() {
  local path="$1"

  # 檔案偵測
  if [[ -f "$path" ]]; then
    local filename
    filename=$(basename "$path")

    case "$filename" in
      SKILL.md|*.skill.md)
        echo "claude"
        return
        ;;
      AGENTS.md|agents.md|AGENT.md|agent.md)
        echo "codex"
        return
        ;;
      GEMINI.md|gemini.md)
        echo "gemini"
        return
        ;;
    esac
  fi

  # 目錄偵測
  if [[ -d "$path" ]]; then
    # Claude Code: 有 .claude-plugin/ 或 skills/*/SKILL.md
    if [[ -d "${path}/.claude-plugin" ]] || [[ -f "${path}/SKILL.md" ]]; then
      echo "claude"
      return
    fi
    if find "$path" -name "SKILL.md" -type f 2>/dev/null | grep -q .; then
      echo "claude"
      return
    fi

    # Gemini CLI: 有 gemini-extension.json
    if [[ -f "${path}/gemini-extension.json" ]]; then
      echo "gemini"
      return
    fi

    # Codex CLI: 有 AGENTS.md
    if [[ -f "${path}/AGENTS.md" ]] || [[ -f "${path}/agents.md" ]]; then
      echo "codex"
      return
    fi
  fi

  # 預設返回目標 CLI
  echo "$TARGET_CLI"
}

# ============================================================================
# Codex CLI 安裝函式
# ============================================================================

# 從 SKILL.md 安裝到 Codex（與 Claude Code 格式相同）
install_codex_skill() {
  local file="$1"
  local name=""

  log_info "${COLOR_CYAN}[Codex CLI]${COLOR_RESET} 正在安裝 SKILL.md：$file"

  # 從 frontmatter 取得 name
  name=$(get_name_from_frontmatter "$file")

  if [[ -z "$name" ]]; then
    log_warn "無法從 frontmatter 取得 name，請輸入 skill 名稱："
    read -r name
    if [[ -z "$name" ]]; then
      log_error "必須提供 skill 名稱"
      return 1
    fi
  fi

  log_info "Skill 名稱：$name"

  local target_dir="${CODEX_SKILLS_DIR}/${name}"

  # 檢查是否已存在
  if [[ -d "$target_dir" ]]; then
    log_warn "已存在同名 skill：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$target_dir"
  fi

  mkdir -p "$target_dir"
  cp "$file" "${target_dir}/SKILL.md"

  # 複製同目錄下的其他資源（scripts/, references/, assets/）
  local source_dir
  source_dir=$(dirname "$file")
  for subdir in scripts references assets; do
    if [[ -d "${source_dir}/${subdir}" ]]; then
      cp -R "${source_dir}/${subdir}" "${target_dir}/"
      log_info "已複製：${subdir}/"
    fi
  done

  log_success "已安裝：$name"
  log_info "路徑：$target_dir"
  log_info "使用方式：在 Codex CLI 中輸入 \$${name} 來呼叫此 skill"
}

# 從目錄安裝到 Codex
install_codex_directory() {
  local source_dir="$1"
  local name=""

  # 嘗試從 SKILL.md 取得名稱
  if [[ -f "${source_dir}/SKILL.md" ]]; then
    name=$(get_name_from_frontmatter "${source_dir}/SKILL.md")
  fi

  # 如果沒有，使用目錄名稱
  if [[ -z "$name" ]]; then
    name=$(basename "$source_dir")
  fi

  log_info "${COLOR_CYAN}[Codex CLI]${COLOR_RESET} 正在安裝目錄：$source_dir"

  local target_dir="${CODEX_SKILLS_DIR}/${name}"

  if [[ -d "$target_dir" ]]; then
    log_warn "已存在同名 skill：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$target_dir"
  fi

  cp -R "$source_dir" "$target_dir"

  log_success "已安裝：$name"
  log_info "路徑：$target_dir"
  log_info "使用方式：在 Codex CLI 中輸入 \$${name} 來呼叫此 skill"
}

# ============================================================================
# Gemini CLI 安裝函式
# ============================================================================

# 從 GEMINI.md 安裝到 Gemini
install_gemini_context() {
  local file="$1"
  local name=""

  log_info "${COLOR_CYAN}[Gemini CLI]${COLOR_RESET} 正在安裝 GEMINI.md：$file"

  log_warn "請輸入擴展名稱："
  read -r name
  if [[ -z "$name" ]]; then
    name="custom-context"
  fi

  local target_dir="${GEMINI_EXTENSIONS_DIR}/${name}"

  if [[ -d "$target_dir" ]]; then
    log_warn "已存在同名擴展：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$target_dir"
  fi

  mkdir -p "$target_dir"
  cp "$file" "${target_dir}/GEMINI.md"

  # 建立 gemini-extension.json
  cat > "${target_dir}/gemini-extension.json" << EOF
{
  "name": "${name}",
  "version": "1.0.0",
  "contextFileName": "GEMINI.md"
}
EOF

  log_success "已安裝：$name"
  log_info "路徑：$target_dir"
  log_info "結構："
  echo "  ${target_dir}/"
  echo "  ├── gemini-extension.json"
  echo "  └── GEMINI.md"
}

# 從 SKILL.md 安裝到 Gemini（轉換格式）
install_gemini_skill() {
  local file="$1"
  local name=""

  log_info "${COLOR_CYAN}[Gemini CLI]${COLOR_RESET} 正在安裝 SKILL.md：$file"

  # 從 frontmatter 取得 name
  name=$(get_name_from_frontmatter "$file")

  if [[ -z "$name" ]]; then
    log_warn "無法從 frontmatter 取得 name，請輸入 skill 名稱："
    read -r name
    if [[ -z "$name" ]]; then
      log_error "必須提供 skill 名稱"
      return 1
    fi
  fi

  log_info "Skill 名稱：$name"

  local target_dir="${GEMINI_EXTENSIONS_DIR}/${name}"

  if [[ -d "$target_dir" ]]; then
    log_warn "已存在同名擴展：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$target_dir"
  fi

  mkdir -p "${target_dir}/skills/${name}"

  # 複製 SKILL.md 到 skills 目錄
  cp "$file" "${target_dir}/skills/${name}/SKILL.md"

  # 從 SKILL.md 讀取 description
  local desc=""
  if head -1 "$file" | grep -q "^---"; then
    desc=$(sed -n '/^---$/,/^---$/p' "$file" | grep -E "^description:" | head -1 | sed 's/^description:[[:space:]]*//' | tr -d '\r')
  fi

  # 建立 gemini-extension.json
  cat > "${target_dir}/gemini-extension.json" << EOF
{
  "name": "${name}",
  "version": "1.0.0",
  "description": "${desc:-Skill installed from SKILL.md}"
}
EOF

  # 建立 GEMINI.md（簡易上下文檔）
  cat > "${target_dir}/GEMINI.md" << EOF
# ${name}

${desc:-This extension provides the ${name} skill.}

## Skills

- \`${name}\`: See skills/${name}/SKILL.md for details.
EOF

  log_success "已安裝：$name"
  log_info "路徑：$target_dir"
  log_info "結構："
  echo "  ${target_dir}/"
  echo "  ├── gemini-extension.json"
  echo "  ├── GEMINI.md"
  echo "  └── skills/"
  echo "      └── ${name}/"
  echo "          └── SKILL.md"
}

# 從完整擴展目錄安裝到 Gemini
install_gemini_extension() {
  local source_dir="$1"
  local name
  name=$(basename "$source_dir")

  # 嘗試從 gemini-extension.json 讀取名稱
  if [[ -f "${source_dir}/gemini-extension.json" ]]; then
    local json_name
    json_name=$(jq -r '.name // ""' "${source_dir}/gemini-extension.json" 2>/dev/null || echo "")
    if [[ -n "$json_name" ]]; then
      name="$json_name"
    fi
  fi

  log_info "${COLOR_CYAN}[Gemini CLI]${COLOR_RESET} 正在安裝擴展：$name"

  local target_dir="${GEMINI_EXTENSIONS_DIR}/${name}"

  if [[ -d "$target_dir" ]]; then
    log_warn "已存在同名擴展：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$target_dir"
  fi

  cp -R "$source_dir" "$target_dir"

  log_success "已安裝：$name"
  log_info "路徑：$target_dir"
}

# ============================================================================
# Claude Code 安裝函式（原有函式重構）
# ============================================================================

# 從單一 SKILL.md 檔案安裝
install_from_skill_file() {
  local file="$1"
  local name=""

  log_info "正在安裝 SKILL.md 檔案：$file"

  # 從 frontmatter 取得 name
  name=$(get_name_from_frontmatter "$file")

  if [[ -z "$name" ]]; then
    log_warn "無法從 frontmatter 取得 name，請輸入 skill 名稱："
    read -r name
    if [[ -z "$name" ]]; then
      log_error "必須提供 skill 名稱"
      return 1
    fi
  fi

  log_info "Skill 名稱：$name"

  # 建立目標目錄結構
  local plugin_dir="${CLAUDE_PLUGINS_DIR}/${name}"
  local skill_dir="${plugin_dir}/skills/${name}"

  # 檢查是否已安裝
  if [[ -d "$plugin_dir" ]]; then
    log_warn "已存在同名 plugin：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$plugin_dir"
  fi

  # 建立目錄結構
  mkdir -p "$skill_dir"
  mkdir -p "${plugin_dir}/.claude-plugin"

  # 複製 SKILL.md
  cp "$file" "${skill_dir}/SKILL.md"

  # 從 SKILL.md 讀取 description
  local desc=""
  if head -1 "$file" | grep -q "^---"; then
    desc=$(sed -n '/^---$/,/^---$/p' "$file" | grep -E "^description:" | head -1 | sed 's/^description:[[:space:]]*//' | tr -d '\r')
  fi

  # 建立 plugin.json
  cat > "${plugin_dir}/.claude-plugin/plugin.json" << EOF
{
  "name": "${name}",
  "version": "1.0.0",
  "description": "${desc:-Skill installed from single SKILL.md file}"
}
EOF

  log_success "已安裝：$name"
  log_info "路徑：$plugin_dir"
  log_info "結構："
  echo "  ${plugin_dir}/"
  echo "  ├── .claude-plugin/"
  echo "  │   └── plugin.json"
  echo "  └── skills/"
  echo "      └── ${name}/"
  echo "          └── SKILL.md"
}

# 從單一 command.md 檔案安裝
install_from_command_file() {
  local file="$1"
  local name=""

  log_info "正在安裝 command 檔案：$file"

  # 從檔案名稱取得 name
  name=$(basename "$file" .md)

  log_info "Command 名稱：$name"

  # 目標路徑
  local target_file="${CLAUDE_COMMANDS_DIR}/${name}.md"

  # 檢查是否已存在
  if [[ -f "$target_file" ]]; then
    log_warn "已存在同名 command：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
  fi

  # 複製檔案
  cp "$file" "$target_file"

  log_success "已安裝：$name"
  log_info "路徑：$target_file"
}

# 根據 TARGET_CLI 安裝 SKILL.md 檔案
install_skill_by_target() {
  local file="$1"

  case "$TARGET_CLI" in
    claude)
      install_from_skill_file "$file"
      ;;
    codex)
      install_codex_skill "$file"
      ;;
    gemini)
      install_gemini_skill "$file"
      ;;
  esac
}

# 根據 TARGET_CLI 安裝目錄
install_directory_by_target() {
  local source_dir="$1"

  case "$TARGET_CLI" in
    claude)
      install_from_local "$source_dir"
      ;;
    codex)
      install_codex_directory "$source_dir"
      ;;
    gemini)
      if is_gemini_extension "$source_dir"; then
        install_gemini_extension "$source_dir"
      else
        install_gemini_extension "$source_dir"
      fi
      ;;
  esac
}

# 根據 TARGET_CLI 安裝簡單 skill 目錄
install_skill_dir_by_target() {
  local source_dir="$1"
  local skill_name="$2"

  case "$TARGET_CLI" in
    claude)
      install_skill_directory "$source_dir" "$skill_name"
      ;;
    codex)
      install_codex_directory "$source_dir"
      ;;
    gemini)
      # 對於簡單目錄，直接安裝 SKILL.md
      if [[ -f "${source_dir}/SKILL.md" ]]; then
        install_gemini_skill "${source_dir}/SKILL.md"
      else
        install_gemini_extension "$source_dir"
      fi
      ;;
  esac
}

# 從 zip 檔案安裝
install_from_zip() {
  local zip_file="$1"
  local zip_name
  zip_name=$(basename "$zip_file" .zip)

  log_info "正在解壓縮：$zip_file"

  # 檢查 unzip 是否存在
  if ! command -v unzip &>/dev/null; then
    log_error "缺少 unzip 工具，請先安裝"
    return 1
  fi

  # 建立暫存目錄
  local extract_dir="${TEMP_DIR}/zip_extract_$$"
  mkdir -p "$extract_dir"

  # 解壓縮
  if ! unzip -q "$zip_file" -d "$extract_dir"; then
    log_error "解壓縮失敗"
    rm -rf "$extract_dir"
    return 1
  fi

  # 分析解壓縮後的結構
  local content_count
  content_count=$(find "$extract_dir" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')

  if [[ "$content_count" -eq 0 ]]; then
    log_error "zip 檔案是空的"
    rm -rf "$extract_dir"
    return 1
  fi

  # 檢查結構類型
  local first_item
  first_item=$(find "$extract_dir" -maxdepth 1 -mindepth 1 | head -1)

  # 情況 1：zip 內只有一個目錄（例如 verify.zip -> verify/SKILL.md）
  if [[ "$content_count" -eq 1 ]] && [[ -d "$first_item" ]]; then
    log_info "偵測到目錄結構：$(basename "$first_item")/"

    # 檢查目錄內是否有 SKILL.md
    if [[ -f "${first_item}/SKILL.md" ]]; then
      # 檢查是否為完整的 plugin 結構（Claude 特有）
      if [[ -d "${first_item}/.claude-plugin" ]] || [[ -d "${first_item}/commands" ]] || [[ -d "${first_item}/skills" ]]; then
        # 完整 plugin 結構，使用目錄安裝
        install_directory_by_target "$first_item"
      else
        # 簡單的 skill 目錄（只有 SKILL.md），建立完整結構
        local skill_name
        skill_name=$(get_name_from_frontmatter "${first_item}/SKILL.md")
        if [[ -z "$skill_name" ]]; then
          skill_name=$(basename "$first_item")
        fi
        install_skill_dir_by_target "$first_item" "$skill_name"
      fi
    else
      # 一般目錄，嘗試當作 plugin 安裝
      install_directory_by_target "$first_item"
    fi

  # 情況 2：zip 內只有一個 SKILL.md 檔案
  elif [[ "$content_count" -eq 1 ]] && [[ -f "$first_item" ]] && [[ "$(basename "$first_item")" == "SKILL.md" ]]; then
    log_info "偵測到單一 SKILL.md 檔案"
    install_skill_by_target "$first_item"

  # 情況 3：zip 內有多個檔案，檢查是否有 SKILL.md
  elif [[ -f "${extract_dir}/SKILL.md" ]]; then
    log_info "偵測到根目錄 SKILL.md"
    install_skill_by_target "${extract_dir}/SKILL.md"

  # 情況 4：zip 內有多個檔案但沒有 SKILL.md，當作 plugin 目錄
  else
    log_info "偵測到 plugin 目錄結構"
    # 重新命名 extract_dir 為 zip 檔案名稱
    local plugin_dir="${TEMP_DIR}/${zip_name}"
    mv "$extract_dir" "$plugin_dir"
    install_directory_by_target "$plugin_dir"
    extract_dir="$plugin_dir"  # 更新變數以便清理
  fi

  # 清理
  rm -rf "$extract_dir"
}

# 從簡單 skill 目錄安裝（只有 SKILL.md 的目錄）
install_skill_directory() {
  local source_dir="$1"
  local name="$2"

  log_info "正在安裝 skill 目錄：$name"

  # 建立目標目錄結構
  local plugin_dir="${CLAUDE_PLUGINS_DIR}/${name}"
  local skill_dir="${plugin_dir}/skills/${name}"

  # 檢查是否已安裝
  if [[ -d "$plugin_dir" ]]; then
    log_warn "已存在同名 plugin：$name"
    read -r -p "是否覆蓋？[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "已取消安裝"
      return 0
    fi
    rm -rf "$plugin_dir"
  fi

  # 建立目錄結構
  mkdir -p "$skill_dir"
  mkdir -p "${plugin_dir}/.claude-plugin"

  # 複製所有檔案
  cp -R "${source_dir}/"* "$skill_dir/"

  # 從 SKILL.md 讀取 description
  local desc=""
  if [[ -f "${skill_dir}/SKILL.md" ]] && head -1 "${skill_dir}/SKILL.md" | grep -q "^---"; then
    desc=$(sed -n '/^---$/,/^---$/p' "${skill_dir}/SKILL.md" | grep -E "^description:" | head -1 | sed 's/^description:[[:space:]]*//' | tr -d '\r')
  fi

  # 建立 plugin.json
  cat > "${plugin_dir}/.claude-plugin/plugin.json" << EOF
{
  "name": "${name}",
  "version": "1.0.0",
  "description": "${desc:-Skill installed from directory}"
}
EOF

  log_success "已安裝：$name"
  log_info "路徑：$plugin_dir"
}

# 主安裝函式
cmd_install() {
  local source="$1"

  if [[ -z "$source" ]]; then
    log_error "請提供安裝來源（Git URL、本地路徑、.md 檔案或 .zip 檔案）"
    return 1
  fi

  # 自動偵測 CLI 類型（如果沒有手動指定）
  local detected_cli
  detected_cli=$(detect_cli_type "$source")

  log_info "目標 CLI：${COLOR_CYAN}${TARGET_CLI}${COLOR_RESET}（偵測到：${detected_cli}）"

  # Git URL 安裝
  if is_git_url "$source"; then
    install_from_git "$source"
    return
  fi

  # Zip 檔案安裝
  if is_zip_file "$source"; then
    install_from_zip "$source"
    return
  fi

  # 目錄安裝
  if [[ -d "$source" ]]; then
    case "$TARGET_CLI" in
      claude)
        install_from_local "$source"
        ;;
      codex)
        install_codex_directory "$source"
        ;;
      gemini)
        if is_gemini_extension "$source"; then
          install_gemini_extension "$source"
        else
          install_gemini_extension "$source"
        fi
        ;;
    esac
    return
  fi

  # 單一檔案安裝
  if [[ -f "$source" ]]; then
    local filename
    filename=$(basename "$source")

    # SKILL.md -> Claude Code 或 Codex CLI（兩者都使用 SKILL.md 格式）
    if is_skill_file "$source"; then
      case "$TARGET_CLI" in
        claude)
          install_from_skill_file "$source"
          ;;
        codex)
          install_codex_skill "$source"
          ;;
        gemini)
          # Gemini 也可以安裝 SKILL.md
          install_gemini_context "$source"
          ;;
      esac
      return
    fi

    # AGENTS.md -> 專案指令（放在專案目錄，非全域安裝）
    if is_agents_file "$source"; then
      log_warn "AGENTS.md 是專案級指令檔，應放在專案根目錄，非全域 skill"
      log_info "如果要安裝為 Codex skill，請改用 SKILL.md 格式"
      return 1
    fi

    # GEMINI.md -> Gemini CLI
    if is_gemini_file "$source"; then
      install_gemini_context "$source"
      return
    fi

    # 一般 .md 檔案 -> 根據目標 CLI 安裝
    if is_command_file "$source"; then
      case "$TARGET_CLI" in
        claude)
          install_from_command_file "$source"
          ;;
        codex)
          log_info "將 .md 檔案轉為 Codex skill 安裝"
          # 建立臨時 SKILL.md
          local temp_skill="${TEMP_DIR}/$(basename "$source" .md)"
          mkdir -p "$temp_skill"
          cp "$source" "${temp_skill}/SKILL.md"
          install_codex_skill "${temp_skill}/SKILL.md"
          ;;
        gemini)
          install_gemini_context "$source"
          ;;
      esac
      return
    fi
  fi

  log_error "無效的安裝來源：$source"
  log_info "請提供有效的 Git URL、本地目錄、.md 或 .zip 檔案路徑"
  return 1
}

# ============================================================================
# 列表函式
# ============================================================================

# 列出 Claude Code plugins
list_claude() {
  echo -e "${COLOR_CYAN}[Claude Code]${COLOR_RESET} ${CLAUDE_PLUGINS_DIR}"
  echo ""

  if [[ ! -d "$CLAUDE_PLUGINS_DIR" ]] || [[ -z "$(ls -A "$CLAUDE_PLUGINS_DIR" 2>/dev/null)" ]]; then
    echo "  （尚未安裝任何 plugin）"
    echo ""
    return 0
  fi

  for plugin_dir in "${CLAUDE_PLUGINS_DIR}"/*; do
    if [[ -d "$plugin_dir" ]]; then
      local name
      name=$(basename "$plugin_dir")
      local desc=""

      if [[ -f "${plugin_dir}/.claude-plugin/plugin.json" ]]; then
        desc=$(jq -r '.description // ""' "${plugin_dir}/.claude-plugin/plugin.json" 2>/dev/null || echo "")
      fi

      local cmd_count=0 skill_count=0 agent_count=0

      if [[ -d "${plugin_dir}/commands" ]]; then
        cmd_count=$(find "${plugin_dir}/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      fi

      if [[ -d "${plugin_dir}/skills" ]]; then
        skill_count=$(find "${plugin_dir}/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
      fi

      if [[ -d "${plugin_dir}/agents" ]]; then
        agent_count=$(find "${plugin_dir}/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      fi

      echo -e "  ${COLOR_GREEN}${name}${COLOR_RESET}"
      if [[ -n "$desc" ]]; then
        echo "    描述：$desc"
      fi
      echo "    組件：commands($cmd_count) skills($skill_count) agents($agent_count)"
      echo "    路徑：$plugin_dir"
      echo ""
    fi
  done
}

# 列出 Codex CLI skills
list_codex() {
  echo -e "${COLOR_CYAN}[Codex CLI]${COLOR_RESET} ${CODEX_SKILLS_DIR}"
  echo ""

  if [[ ! -d "$CODEX_SKILLS_DIR" ]] || [[ -z "$(ls -A "$CODEX_SKILLS_DIR" 2>/dev/null)" ]]; then
    echo "  （尚未安裝任何 skill）"
    echo ""
    return 0
  fi

  for skill_dir in "${CODEX_SKILLS_DIR}"/*; do
    if [[ -d "$skill_dir" ]]; then
      local name
      name=$(basename "$skill_dir")
      local desc=""

      # 從 SKILL.md 取得 description
      if [[ -f "${skill_dir}/SKILL.md" ]] && head -1 "${skill_dir}/SKILL.md" | grep -q "^---"; then
        desc=$(sed -n '/^---$/,/^---$/p' "${skill_dir}/SKILL.md" | grep -E "^description:" | head -1 | sed 's/^description:[[:space:]]*//' | tr -d '\r')
      fi

      echo -e "  ${COLOR_GREEN}${name}${COLOR_RESET}"

      if [[ -n "$desc" ]]; then
        echo "    描述：$desc"
      fi

      # 檢查 SKILL.md
      if [[ -f "${skill_dir}/SKILL.md" ]]; then
        echo "    檔案：SKILL.md"
      fi

      # 檢查附加資源
      local resources=""
      [[ -d "${skill_dir}/scripts" ]] && resources+="scripts/ "
      [[ -d "${skill_dir}/references" ]] && resources+="references/ "
      [[ -d "${skill_dir}/assets" ]] && resources+="assets/ "
      [[ -n "$resources" ]] && echo "    資源：$resources"

      echo "    路徑：$skill_dir"
      echo "    呼叫：\$${name}"
      echo ""
    fi
  done
}

# 列出 Gemini CLI extensions
list_gemini() {
  echo -e "${COLOR_CYAN}[Gemini CLI]${COLOR_RESET} ${GEMINI_EXTENSIONS_DIR}"
  echo ""

  if [[ ! -d "$GEMINI_EXTENSIONS_DIR" ]] || [[ -z "$(ls -A "$GEMINI_EXTENSIONS_DIR" 2>/dev/null)" ]]; then
    echo "  （尚未安裝任何擴展）"
    echo ""
    return 0
  fi

  for ext_dir in "${GEMINI_EXTENSIONS_DIR}"/*; do
    if [[ -d "$ext_dir" ]]; then
      local name
      name=$(basename "$ext_dir")
      local version=""

      if [[ -f "${ext_dir}/gemini-extension.json" ]]; then
        version=$(jq -r '.version // ""' "${ext_dir}/gemini-extension.json" 2>/dev/null || echo "")
      fi

      echo -e "  ${COLOR_GREEN}${name}${COLOR_RESET}"
      if [[ -n "$version" ]]; then
        echo "    版本：$version"
      fi

      # 檢查組件
      local has_context="" has_commands="" has_skills=""
      [[ -f "${ext_dir}/GEMINI.md" ]] && has_context="GEMINI.md"
      [[ -d "${ext_dir}/commands" ]] && has_commands="commands/"
      [[ -d "${ext_dir}/skills" ]] && has_skills="skills/"

      local components="${has_context} ${has_commands} ${has_skills}"
      components=$(echo "$components" | xargs)
      [[ -n "$components" ]] && echo "    組件：$components"

      echo "    路徑：$ext_dir"
      echo ""
    fi
  done
}

cmd_list() {
  case "$TARGET_CLI" in
    claude)
      list_claude
      ;;
    codex)
      list_codex
      ;;
    gemini)
      list_gemini
      ;;
    all)
      list_claude
      list_codex
      list_gemini
      ;;
  esac
}

# ============================================================================
# 更新函式
# ============================================================================

# 取得目標目錄
get_target_dir() {
  local name="$1"

  case "$TARGET_CLI" in
    claude)
      echo "${CLAUDE_PLUGINS_DIR}/${name}"
      ;;
    codex)
      echo "${CODEX_SKILLS_DIR}/${name}"
      ;;
    gemini)
      echo "${GEMINI_EXTENSIONS_DIR}/${name}"
      ;;
  esac
}

# 取得所有目標目錄的父目錄
get_target_parent_dir() {
  case "$TARGET_CLI" in
    claude)
      echo "${CLAUDE_PLUGINS_DIR}"
      ;;
    codex)
      echo "${CODEX_SKILLS_DIR}"
      ;;
    gemini)
      echo "${GEMINI_EXTENSIONS_DIR}"
      ;;
  esac
}

cmd_update() {
  local name="${1:-}"
  local parent_dir
  parent_dir=$(get_target_parent_dir)

  log_info "${COLOR_CYAN}[${TARGET_CLI}]${COLOR_RESET} 更新模式"

  if [[ -n "$name" ]]; then
    local target_dir
    target_dir=$(get_target_dir "$name")

    if [[ ! -d "$target_dir" ]]; then
      log_error "找不到：$name"
      return 1
    fi

    if [[ ! -d "${target_dir}/.git" ]]; then
      log_warn "此項目不是從 Git 安裝的，無法更新"
      return 1
    fi

    log_info "正在更新：$name"

    if (cd "$target_dir" && git pull --ff-only); then
      log_success "已更新：$name"
    else
      log_error "更新失敗：$name"
      return 1
    fi
  else
    log_info "正在更新所有項目..."

    local updated=0
    local failed=0

    if [[ -d "$parent_dir" ]]; then
      for item_dir in "${parent_dir}"/*; do
        if [[ -d "$item_dir" ]] && [[ -d "${item_dir}/.git" ]]; then
          local item_name
          item_name=$(basename "$item_dir")

          if (cd "$item_dir" && git pull --ff-only 2>/dev/null); then
            log_success "已更新：$item_name"
            ((updated++)) || true
          else
            log_error "更新失敗：$item_name"
            ((failed++)) || true
          fi
        fi
      done
    fi

    echo ""
    log_info "更新完成：成功 $updated 個，失敗 $failed 個"
  fi
}

# ============================================================================
# 移除函式
# ============================================================================

cmd_remove() {
  local name="$1"

  if [[ -z "$name" ]]; then
    log_error "請提供要移除的名稱"
    return 1
  fi

  local target_dir
  target_dir=$(get_target_dir "$name")

  if [[ ! -d "$target_dir" ]]; then
    log_error "找不到：$name"
    return 1
  fi

  log_warn "${COLOR_CYAN}[${TARGET_CLI}]${COLOR_RESET} 即將移除：$name"
  log_info "路徑：$target_dir"
  read -r -p "確定要移除嗎？[y/N] " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "已取消"
    return 0
  fi

  rm -rf "$target_dir"
  log_success "已移除：$name"
}

# ============================================================================
# 驗證命令
# ============================================================================

cmd_validate() {
  local path="$1"

  if [[ -z "$path" ]]; then
    log_error "請提供要驗證的路徑"
    return 1
  fi

  if [[ ! -d "$path" ]]; then
    log_error "路徑不存在或不是目錄：$path"
    return 1
  fi

  log_info "正在驗證：$path"
  validate_plugin "$path"
}

# ============================================================================
# 說明函式
# ============================================================================

show_help() {
  cat << EOF
AI CLI Skill 安裝工具 v${VERSION}

支援 Claude Code、Codex CLI、Gemini CLI 的統一安裝管理工具

使用方式：
  ${SCRIPT_NAME} <command> [arguments] [--target <cli>]

目標 CLI（--target 或 -t）：
  claude    Claude Code（預設）
  codex     OpenAI Codex CLI
  gemini    Google Gemini CLI

命令：
  install <source>      安裝 skill/plugin，支援多種來源：
                        - Git URL (https://github.com/user/repo.git)
                        - 本地目錄 (./my-plugin)
                        - 單一檔案 (SKILL.md, AGENTS.md, GEMINI.md)
                        - zip 壓縮檔 (*.zip)
  list                  列出已安裝的 skills/plugins
  update [name]         更新指定或全部（僅限 Git 安裝）
  remove <name>         移除指定的 skill/plugin
  validate <path>       驗證格式是否正確
  help                  顯示此說明

自動偵測檔案類型：
  SKILL.md              → Claude Code 或 Codex CLI（依 --target）
  GEMINI.md             → Gemini CLI
  AGENTS.md             → 專案級指令（非全域 skill）

範例：
  # Claude Code（預設）
  ${SCRIPT_NAME} install ~/Downloads/SKILL.md
  ${SCRIPT_NAME} install https://github.com/user/my-skill.git
  ${SCRIPT_NAME} install ./my-plugin.zip

  # Codex CLI
  ${SCRIPT_NAME} install ~/Downloads/AGENTS.md
  ${SCRIPT_NAME} install ./my-agents --target codex
  ${SCRIPT_NAME} list -t codex

  # Gemini CLI
  ${SCRIPT_NAME} install ~/Downloads/GEMINI.md
  ${SCRIPT_NAME} install ./my-extension --target gemini
  ${SCRIPT_NAME} list -t gemini

  # 其他操作
  ${SCRIPT_NAME} list                    # 列出 Claude Code
  ${SCRIPT_NAME} list -t codex           # 列出 Codex CLI
  ${SCRIPT_NAME} list -t gemini          # 列出 Gemini CLI
  ${SCRIPT_NAME} update my-skill
  ${SCRIPT_NAME} remove my-skill -t codex

安裝路徑：
  Claude Code:  ${CLAUDE_PLUGINS_DIR}
  Codex CLI:    ${CODEX_SKILLS_DIR}
  Gemini CLI:   ${GEMINI_EXTENSIONS_DIR}

EOF
}

# ============================================================================
# 主程式
# ============================================================================

main() {
  # 先解析 --target 參數
  parse_target "$@"

  # 過濾掉 --target 參數，取得其餘參數
  local args=()
  local skip_next=false

  for arg in "$@"; do
    if [[ "$skip_next" == true ]]; then
      skip_next=false
      continue
    fi
    case "$arg" in
      --target|-t)
        skip_next=true
        ;;
      *)
        args+=("$arg")
        ;;
    esac
  done

  local command="${args[0]:-help}"
  local arg1="${args[1]:-}"

  # 檢查相依性
  check_dependencies

  # 確保目錄存在
  ensure_directories

  case "$command" in
    install)
      cmd_install "$arg1"
      ;;
    list|ls)
      cmd_list
      ;;
    update|upgrade)
      cmd_update "$arg1"
      ;;
    remove|rm|uninstall)
      cmd_remove "$arg1"
      ;;
    validate|check)
      cmd_validate "$arg1"
      ;;
    help|--help|-h)
      show_help
      ;;
    version|--version|-v)
      echo "v${VERSION}"
      ;;
    *)
      log_error "未知命令：$command"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

main "$@"
