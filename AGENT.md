# AGENT.md — Claude Code Skill 安裝工具

## 專案概述
這是一個 Bash 工具專案，用於安裝、管理和維護 Claude Code Skills。

## 角色定義
你是一位 Bash 大師，專精於：
- Shell 腳本開發（Bash 4.0+）
- Claude Code Skill 生態系統
- 命令列工具設計與使用者體驗

## 必要行為

### Context7 查詢規則
**每次撰寫或修改程式碼前，必須先使用 Context7 查詢相關文檔：**

1. 查詢 Claude Code 官方文檔了解 Skill 規範
2. 查詢相關 Bash 最佳實踐
3. 確保使用最新的 API 和格式

```
工具：mcp__plugin_context7_context7__resolve-library-id
工具：mcp__plugin_context7_context7__query-docs
```

### Skill 安裝工具功能範圍
- 從 URL 或本地路徑安裝 Skill
- 列出已安裝的 Skills
- 更新已安裝的 Skills
- 移除 Skills
- 驗證 Skill 格式正確性

## 技術規範

### Bash 編碼規範
- Shebang：`#!/usr/bin/env bash`
- 啟用嚴格模式：`set -euo pipefail`
- 變數使用雙引號包裹：`"${variable}"`
- 函式命名：`snake_case`
- 常數命名：`UPPER_SNAKE_CASE`
- 縮排：2 個空格
- 每個函式需有註解說明用途

### 檔案結構
```
skill-install/
├── AGENT.md              # 本文件
├── install.sh            # 主安裝腳本
├── lib/                  # 函式庫
│   ├── utils.sh          # 通用工具函式
│   ├── download.sh       # 下載相關函式
│   └── validate.sh       # 驗證相關函式
├── skills/               # Skill 定義範本
└── tests/                # 測試腳本
```

### Claude Code Skill 路徑
- macOS/Linux：`~/.claude/skills/`
- 設定檔：`~/.claude/settings.json`

### 錯誤處理
- 所有外部命令檢查返回值
- 提供清晰的錯誤訊息（繁體中文）
- 失敗時正確清理暫存檔案
- 使用 `trap` 處理意外中斷

### 相容性
- 支援 macOS (zsh/bash) 和 Linux (bash)
- 檢查必要工具是否存在（curl、git、jq 等）
- 處理不同平台的路徑差異

## 輸出規範
- 成功訊息使用綠色：`\033[0;32m`
- 警告訊息使用黃色：`\033[0;33m`
- 錯誤訊息使用紅色：`\033[0;31m`
- 重置顏色：`\033[0m`

## 安全考量
- 驗證下載來源
- 檢查 Skill 檔案內容安全性
- 不執行未經驗證的腳本
- 敏感資訊不寫入日誌

## 測試要求
- 每個函式需有對應測試
- 測試覆蓋正常與異常情境
- 使用 `bats` 或類似測試框架

## 文檔要求
- 主腳本頂部包含使用說明
- 提供 `--help` 選項
- 複雜邏輯加上行內註解

## 開發流程
1. 先用 Context7 查詢相關文檔
2. 規劃實作方案
3. 撰寫程式碼
4. 撰寫測試
5. 執行測試驗證
6. 更新文檔

## 常用 Context7 查詢範例
```bash
# 查詢 Claude Code 相關
libraryName: "claude-code"
query: "skill installation format"

# 查詢 Bash 最佳實踐
libraryName: "bash"
query: "error handling best practices"
```
