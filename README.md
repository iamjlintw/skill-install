# AI CLI Skill 安裝工具

支援 **Claude Code**、**Codex CLI**、**Gemini CLI** 的統一 Skills/Plugins 安裝管理工具。

## 功能特色

- 支援三大 AI CLI 工具的統一管理
- 多種安裝來源（Git URL、本地目錄、單一檔案、zip 壓縮檔）
- 根據 `--target` 參數安裝到對應 CLI
- 自動建立完整的目錄結構
- 互動對話模式（talk.sh）
- 彩色終端輸出

## 支援的 AI CLI

| CLI | 指令檔案 | 安裝路徑 | 呼叫方式 |
|-----|---------|---------|---------|
| Claude Code | `SKILL.md` | `~/.claude/skills/` | 自動載入 |
| Codex CLI | `SKILL.md` | `~/.codex/skills/` | `$skill-name` |
| Gemini CLI | `SKILL.md` | `~/.gemini/extensions/` | 自動載入 |

> **重要**：三大 CLI 都使用相同的 `SKILL.md` 格式，透過 `--target` 參數指定安裝目標。

## 系統需求

- Bash 4.0+
- macOS 或 Linux
- 必要工具：`git`、`curl`、`jq`、`unzip`

## 安裝

```bash
git clone <repo-url> skill-install
cd skill-install
chmod +x install.sh talk.sh
```

### 全域安裝（可選）

```bash
# 方式 1：符號連結（推薦）
sudo ln -sf $(pwd)/install.sh /usr/local/bin/skill-install
sudo ln -sf $(pwd)/talk.sh /usr/local/bin/skill-talk

# 方式 2：加入 PATH
echo 'export PATH="$PATH:/path/to/skill-install"' >> ~/.zshrc

# 方式 3：建立 alias
echo 'alias skill-install="/path/to/skill-install/install.sh"' >> ~/.zshrc
echo 'alias skill-talk="/path/to/skill-install/talk.sh"' >> ~/.zshrc
```

## 使用方式

### 命令列模式（install.sh）

```bash
./install.sh <command> [arguments] [--target <cli>]
```

### 互動對話模式（talk.sh）

```bash
./talk.sh [掃描目錄]
```

## 命令列模式

### 目標 CLI

使用 `--target` 或 `-t` 指定目標 CLI：

| 選項 | 說明 |
|------|------|
| `claude` | Claude Code（預設） |
| `codex` | OpenAI Codex CLI |
| `gemini` | Google Gemini CLI |

### 命令列表

| 命令 | 說明 |
|------|------|
| `install <source>` | 安裝 skill/plugin |
| `list` | 列出已安裝的項目 |
| `update [name]` | 更新指定或全部 |
| `remove <name>` | 移除指定項目 |
| `validate <path>` | 驗證格式 |
| `help` | 顯示說明 |

### 命令列範例

```bash
# Claude Code（預設）
./install.sh install ~/Downloads/SKILL.md
./install.sh install https://github.com/user/my-skill.git
./install.sh install ~/Downloads/my-skill.zip
./install.sh list

# Codex CLI
./install.sh install ~/Downloads/SKILL.md --target codex
./install.sh install ./my-skill.zip -t codex
./install.sh list -t codex
./install.sh remove my-skill -t codex

# Gemini CLI
./install.sh install ~/Downloads/SKILL.md --target gemini
./install.sh install ./my-extension -t gemini
./install.sh list -t gemini
./install.sh remove my-extension -t gemini
```

## 互動對話模式

啟動互動式介面，透過步驟引導完成操作：

```bash
./talk.sh                    # 啟動互動模式
./talk.sh ~/my-skills        # 指定掃描目錄
```

### 互動流程示範

```
╔══════════════════════════════════════════╗
║   AI CLI Skill 安裝工具 - 互動模式       ║
╚══════════════════════════════════════════╝

步驟 1/4: 你想做什麼？
──────────────────────────────────────────────
  1) 安裝 Skill
  2) 移除 Skill
  3) 列出已安裝
  4) 離開

請選擇操作 [1-4, q=取消]: 1

步驟 2/4: 掃描哪個目錄？
──────────────────────────────────────────────
  1) ./skills
  2) 手動輸入路徑

請選擇目錄 [1-2, q=取消]: 1

步驟 3/4: 選擇要安裝的檔案
──────────────────────────────────────────────
找到 2 個檔案:

  1) verify.zip
  2) agent-browser.zip

請選擇檔案 [1-2, q=取消]: 1

步驟 4/4: 安裝到哪個 CLI？
──────────────────────────────────────────────
  1) Claude Code (預設)
  2) Codex CLI (OpenAI)
  3) Gemini CLI (Google)

請選擇 CLI [1-3, q=取消]: 2

確認安裝：
  檔案：./skills/verify.zip
  目標：Codex CLI (OpenAI)

確定要安裝嗎？[Y/n] y

執行安裝...
✓ 已安裝：verify

完成！
```

## 目錄結構

### Claude Code Skills

```
~/.claude/skills/<skill-name>/
├── SKILL.md            # Skill 定義檔（必要）
├── references/         # 參考文件（選用）
├── examples/           # 範例檔案（選用）
└── scripts/            # 工具腳本（選用）
```

### Codex CLI Skills

```
~/.codex/skills/<skill-name>/
├── SKILL.md            # Skill 定義檔（必要）
├── scripts/            # 可執行腳本（選用）
├── references/         # 參考文件（選用）
└── assets/             # 資源檔案（選用）
```

### Gemini CLI Extension

```
~/.gemini/extensions/<extension-name>/
├── gemini-extension.json
├── GEMINI.md           # 上下文指令
└── skills/
    └── <skill-name>/
        └── SKILL.md
```

## 檔案格式

### SKILL.md（通用格式）

Claude Code、Codex CLI、Gemini CLI 都使用相同的 SKILL.md 格式：

```markdown
---
name: my-skill
description: Skill 描述
allowed-tools: Bash(my-tool:*)
---

# My Skill

Skill 內容...
```

**呼叫方式：**
- Claude Code: AI 自動偵測並載入
- Codex CLI: `$my-skill`
- Gemini CLI: 自動載入到上下文

### GEMINI.md（Gemini 專用上下文）

```markdown
# Extension Context

This extension provides...

## Available Tools
- Tool 1: Description
- Tool 2: Description
```

### AGENTS.md（專案級指令）

```markdown
# Project Guidelines

## Code Style
- Use TypeScript strict mode
- Prefer async/await over callbacks
```

> **注意**：AGENTS.md 是放在專案根目錄的指令檔，由 CLI 自動讀取，非全域安裝的 skill。

## 專案結構

```
skill-install/
├── AGENT.md          # AI 開發規範
├── README.md         # 本文件
├── install.sh        # 命令列模式
├── talk.sh           # 互動對話模式
└── skills/           # 範例 skills
    ├── verify.zip
    └── agent-browser.zip
```

## 授權

MIT License
