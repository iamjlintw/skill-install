#!/usr/bin/env bash
#
# AI CLI Skill 安裝工具 - 互動模式
# 透過對話方式安裝/移除 Skills
#
# 使用方式：
#   ./talk.sh [skills_directory]
#
# 預設掃描目錄：./skills 或 ~/Downloads

set -euo pipefail

# ============================================================================
# 常數定義
# ============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"

# 顏色定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# ============================================================================
# 工具函式
# ============================================================================

print_header() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║   AI CLI Skill 安裝工具 - 互動模式       ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
  echo ""
}

print_line() {
  echo -e "${CYAN}──────────────────────────────────────────────${RESET}"
}

# 顯示選單並取得選擇
select_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local selected=0
  local key=""

  # 隱藏游標
  tput civis 2>/dev/null || true

  while true; do
    # 清除選單區域並重繪
    echo -e "\n${BOLD}${prompt}${RESET}\n"

    for i in "${!options[@]}"; do
      if [[ $i -eq $selected ]]; then
        echo -e "  ${GREEN}▶ ${options[$i]}${RESET}"
      else
        echo -e "    ${options[$i]}"
      fi
    done

    echo ""
    echo -e "${BLUE}↑↓ 選擇  Enter 確認  q 取消${RESET}"

    # 讀取按鍵
    read -rsn1 key

    case "$key" in
      A|k) # 上
        ((selected--)) || true
        [[ $selected -lt 0 ]] && selected=$((${#options[@]} - 1))
        ;;
      B|j) # 下
        ((selected++)) || true
        [[ $selected -ge ${#options[@]} ]] && selected=0
        ;;
      "") # Enter
        tput cnorm 2>/dev/null || true
        return $selected
        ;;
      q|Q) # 取消
        tput cnorm 2>/dev/null || true
        return 255
        ;;
    esac

    # 清除選單（往上移動行數）
    local lines=$((${#options[@]} + 4))
    for ((i=0; i<lines; i++)); do
      tput cuu1 2>/dev/null || echo -ne "\033[1A"
      tput el 2>/dev/null || echo -ne "\033[2K"
    done
  done
}

# 簡單的數字選擇（帶選項顯示）
# 用法: select_menu "提示" "選項1" "選項2" ...
# 返回值存在 MENU_CHOICE 變數中
select_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local max=${#options[@]}
  local choice=""

  # 顯示選項
  echo ""
  local i=1
  for opt in "${options[@]}"; do
    echo -e "  ${CYAN}$i)${RESET} $opt"
    ((i++)) || true
  done
  echo ""

  while true; do
    echo -ne "${prompt} [1-${max}, q=取消]: "
    read -r choice

    if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
      MENU_CHOICE=255
      return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$max" ]]; then
      MENU_CHOICE=$((choice - 1))
      return 0
    fi

    echo -e "${RED}請輸入 1-${max} 之間的數字${RESET}"
  done
}

# 只讀取數字輸入（不顯示選項，適用於已自訂顯示的情況）
# 用法: read_choice "提示" 最大值
# 返回值存在 MENU_CHOICE 變數中
MENU_CHOICE=0
read_choice() {
  local prompt="$1"
  local max="$2"
  local choice=""

  while true; do
    echo -ne "${prompt} [1-${max}, q=取消]: "
    read -r choice

    if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
      MENU_CHOICE=255
      return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$max" ]]; then
      MENU_CHOICE=$((choice - 1))
      return 0
    fi

    echo -e "${RED}請輸入 1-${max} 之間的數字${RESET}"
  done
}

# ============================================================================
# 掃描函式
# ============================================================================

# 掃描目錄中的 skill 檔案
scan_skills() {
  local dir="$1"
  local files=()

  # 掃描各種類型的檔案
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$dir" -maxdepth 2 \( \
    -name "SKILL.md" -o \
    -name "AGENTS.md" -o \
    -name "AGENT.md" -o \
    -name "GEMINI.md" -o \
    -name "*.zip" \
  \) -type f -print0 2>/dev/null)

  printf '%s\n' "${files[@]}"
}

# 偵測檔案類型
detect_file_type() {
  local file="$1"
  local filename
  filename=$(basename "$file")

  case "$filename" in
    SKILL.md|*.skill.md)
      echo "claude"
      ;;
    AGENTS.md|AGENT.md|agents.md|agent.md)
      echo "codex"
      ;;
    GEMINI.md|gemini.md)
      echo "gemini"
      ;;
    *.zip)
      echo "zip"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# 取得類型顯示名稱
get_type_label() {
  local type="$1"
  case "$type" in
    claude) echo -e "${GREEN}[Claude]${RESET}" ;;
    codex)  echo -e "${YELLOW}[Codex]${RESET}" ;;
    gemini) echo -e "${BLUE}[Gemini]${RESET}" ;;
    zip)    echo -e "${CYAN}[ZIP]${RESET}" ;;
    *)      echo -e "[未知]" ;;
  esac
}

# ============================================================================
# 主要流程
# ============================================================================

interactive_mode() {
  local scan_dir="${1:-}"

  print_header

  # ========== 步驟 1: 選擇操作 ==========
  echo -e "${BOLD}步驟 1/4: 你想做什麼？${RESET}"
  print_line

  local actions=("安裝 Skill" "移除 Skill" "列出已安裝" "離開")

  select_menu "請選擇操作" "${actions[@]}"
  local action_idx=$MENU_CHOICE

  if [[ $action_idx -eq 255 ]]; then
    echo -e "\n${YELLOW}已取消${RESET}"
    exit 0
  fi

  echo -e "  選擇：${GREEN}${actions[$action_idx]}${RESET}\n"

  case $action_idx in
    0) do_install "$scan_dir" ;;
    1) do_remove ;;
    2) do_list ;;
    3) echo -e "${YELLOW}再見！${RESET}"; exit 0 ;;
  esac
}

# 安裝流程
do_install() {
  local scan_dir="${1:-}"

  # ========== 步驟 2: 選擇掃描目錄 ==========
  echo -e "${BOLD}步驟 2/4: 掃描哪個目錄？${RESET}"
  print_line

  # 取得腳本所在目錄
  local script_location
  script_location="$(cd "$(dirname "$0")" && pwd)"

  local dirs=()

  # 優先：腳本所在目錄的 skills 子目錄
  [[ -d "${script_location}/skills" ]] && dirs+=("${script_location}/skills (本工具)")

  # 當前工作目錄的 skills 子目錄
  [[ -d "./skills" ]] && [[ "$(pwd)/skills" != "${script_location}/skills" ]] && dirs+=("./skills (當前目錄)")

  # 命令列傳入的目錄
  [[ -n "$scan_dir" ]] && [[ -d "$scan_dir" ]] && dirs+=("$scan_dir")

  # 手動輸入
  dirs+=("手動輸入路徑")

  select_menu "請選擇目錄" "${dirs[@]}"
  local dir_idx=$MENU_CHOICE

  if [[ $dir_idx -eq 255 ]]; then
    echo -e "\n${YELLOW}已取消${RESET}"
    exit 0
  fi

  # 處理選擇的目錄（移除括號說明）
  local selected="${dirs[$dir_idx]}"
  selected="${selected%% (*}"

  if [[ "$selected" == "手動輸入路徑" ]]; then
    echo -ne "請輸入目錄路徑: "
    read -r scan_dir
  else
    scan_dir="$selected"
  fi

  if [[ ! -d "$scan_dir" ]]; then
    echo -e "${RED}目錄不存在：$scan_dir${RESET}"
    exit 1
  fi

  echo -e "  掃描：${GREEN}$scan_dir${RESET}\n"

  # ========== 步驟 3: 掃描並選擇檔案 ==========
  echo -e "${BOLD}步驟 3/4: 選擇要安裝的檔案${RESET}"
  print_line

  echo -e "${BLUE}正在掃描...${RESET}\n"

  local files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(scan_skills "$scan_dir")

  if [[ ${#files[@]} -eq 0 ]]; then
    echo -e "${YELLOW}找不到任何 Skill 檔案 (SKILL.md, AGENTS.md, GEMINI.md, *.zip)${RESET}"
    exit 0
  fi

  echo -e "找到 ${GREEN}${#files[@]}${RESET} 個檔案:\n"

  local i=1
  for file in "${files[@]}"; do
    local type
    type=$(detect_file_type "$file")
    local label
    label=$(get_type_label "$type")
    local relpath
    relpath=$(basename "$file")
    local dirname
    dirname=$(basename "$(dirname "$file")")

    echo -e "  $i) $label ${dirname}/${relpath}"
    ((i++)) || true
  done
  echo ""

  read_choice "請選擇檔案" ${#files[@]}
  local file_idx=$MENU_CHOICE

  if [[ $file_idx -eq 255 ]]; then
    echo -e "\n${YELLOW}已取消${RESET}"
    exit 0
  fi

  local selected_file="${files[$file_idx]}"
  local selected_type
  selected_type=$(detect_file_type "$selected_file")

  echo -e "  選擇：${GREEN}$(basename "$selected_file")${RESET}\n"

  # ========== 步驟 4: 選擇目標 CLI ==========
  echo -e "${BOLD}步驟 4/4: 安裝到哪個 CLI？${RESET}"
  print_line

  # 根據檔案類型建議預設選項
  local recommended_label=""
  case "$selected_type" in
    claude|zip) recommended_label="Claude Code (預設) ← 建議" ;;
    codex)  recommended_label="Codex CLI (OpenAI) ← 建議" ;;
    gemini) recommended_label="Gemini CLI (Google) ← 建議" ;;
    *)      recommended_label="Claude Code (預設) ← 建議" ;;
  esac

  local cli_options=()
  local cli_values=("claude" "codex" "gemini")

  case "$selected_type" in
    codex)
      cli_options=("Claude Code (預設)" "Codex CLI (OpenAI) ← 建議" "Gemini CLI (Google)")
      ;;
    gemini)
      cli_options=("Claude Code (預設)" "Codex CLI (OpenAI)" "Gemini CLI (Google) ← 建議")
      ;;
    *)
      cli_options=("Claude Code (預設) ← 建議" "Codex CLI (OpenAI)" "Gemini CLI (Google)")
      ;;
  esac

  select_menu "請選擇 CLI" "${cli_options[@]}"
  local cli_idx=$MENU_CHOICE

  if [[ $cli_idx -eq 255 ]]; then
    echo -e "\n${YELLOW}已取消${RESET}"
    exit 0
  fi

  local target_cli="${cli_values[$cli_idx]}"

  echo -e "  目標：${GREEN}${cli_options[$cli_idx]}${RESET}\n"

  # ========== 確認並執行 ==========
  print_line
  echo -e "${BOLD}確認安裝：${RESET}"
  echo -e "  檔案：${CYAN}$selected_file${RESET}"
  echo -e "  目標：${CYAN}${cli_options[$cli_idx]}${RESET}"
  echo ""

  echo -ne "確定要安裝嗎？[Y/n] "
  read -r confirm

  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}已取消${RESET}"
    exit 0
  fi

  echo ""
  print_line
  echo -e "${BOLD}執行安裝...${RESET}\n"

  # 執行安裝
  "$INSTALL_SCRIPT" install "$selected_file" --target "$target_cli"

  echo ""
  print_line
  echo -e "${GREEN}${BOLD}完成！${RESET}"
}

# 移除流程
do_remove() {
  # ========== 步驟 2: 選擇目標 CLI ==========
  echo -e "${BOLD}步驟 2/3: 從哪個 CLI 移除？${RESET}"
  print_line

  local cli_options=("Claude Code" "Codex CLI" "Gemini CLI")
  local cli_values=("claude" "codex" "gemini")

  select_menu "請選擇 CLI" "${cli_options[@]}"
  local cli_idx=$MENU_CHOICE

  if [[ $cli_idx -eq 255 ]]; then
    echo -e "\n${YELLOW}已取消${RESET}"
    exit 0
  fi

  local target_cli="${cli_values[$cli_idx]}"

  echo -e "  選擇：${GREEN}${cli_options[$cli_idx]}${RESET}\n"

  # ========== 步驟 3: 列出並選擇要移除的項目 ==========
  echo -e "${BOLD}步驟 3/3: 選擇要移除的項目${RESET}"
  print_line

  # 取得已安裝清單
  local items=()
  local list_dir=""

  case "$target_cli" in
    claude) list_dir="${HOME}/.claude/plugins" ;;
    codex)  list_dir="${HOME}/.codex/instructions" ;;
    gemini) list_dir="${HOME}/.gemini/extensions" ;;
  esac

  if [[ -d "$list_dir" ]]; then
    while IFS= read -r -d '' item; do
      items+=("$(basename "$item")")
    done < <(find "$list_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
  fi

  if [[ ${#items[@]} -eq 0 ]]; then
    echo -e "${YELLOW}沒有已安裝的項目${RESET}"
    exit 0
  fi

  local i=1
  for item in "${items[@]}"; do
    echo "  $i) $item"
    ((i++)) || true
  done
  echo ""

  read_choice "請選擇要移除的項目" ${#items[@]}
  local item_idx=$MENU_CHOICE

  if [[ $item_idx -eq 255 ]]; then
    echo -e "\n${YELLOW}已取消${RESET}"
    exit 0
  fi

  local selected_item="${items[$item_idx]}"

  echo -e "  選擇：${RED}$selected_item${RESET}\n"

  # ========== 確認並執行 ==========
  print_line
  echo -e "${BOLD}${RED}確認移除：${RESET}"
  echo -e "  項目：${CYAN}$selected_item${RESET}"
  echo -e "  CLI：${CYAN}${cli_options[$cli_idx]}${RESET}"
  echo ""

  echo -ne "${RED}確定要移除嗎？${RESET}[y/N] "
  read -r confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}已取消${RESET}"
    exit 0
  fi

  echo ""
  print_line
  echo -e "${BOLD}執行移除...${RESET}\n"

  # 執行移除
  echo "y" | "$INSTALL_SCRIPT" remove "$selected_item" --target "$target_cli"

  echo ""
  print_line
  echo -e "${GREEN}${BOLD}完成！${RESET}"
}

# 列出已安裝
do_list() {
  echo -e "${BOLD}步驟 2/2: 列出哪個 CLI？${RESET}"
  print_line

  local cli_options=("Claude Code" "Codex CLI" "Gemini CLI" "全部")
  local cli_values=("claude" "codex" "gemini" "all")

  select_menu "請選擇 CLI" "${cli_options[@]}"
  local cli_idx=$MENU_CHOICE

  if [[ $cli_idx -eq 255 ]]; then
    echo -e "\n${YELLOW}已取消${RESET}"
    exit 0
  fi

  local target="${cli_values[$cli_idx]}"

  echo ""
  print_line

  if [[ "$target" == "all" ]]; then
    "$INSTALL_SCRIPT" list --target claude
    echo ""
    "$INSTALL_SCRIPT" list --target codex
    echo ""
    "$INSTALL_SCRIPT" list --target gemini
  else
    "$INSTALL_SCRIPT" list --target "$target"
  fi
}

# ============================================================================
# 主程式
# ============================================================================

main() {
  # 檢查 install.sh 是否存在
  if [[ ! -x "$INSTALL_SCRIPT" ]]; then
    echo -e "${RED}找不到 install.sh：$INSTALL_SCRIPT${RESET}"
    exit 1
  fi

  interactive_mode "$@"
}

main "$@"
