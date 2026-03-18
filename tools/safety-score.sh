#!/usr/bin/env bash
#
# safety-score.sh - Skill 安全评分工具
# 对 SKILL.md 文件进行静态安全分析，输出安全评分报告
#
# 用法:
#   ./safety-score.sh <SKILL.md 路径 或 GitHub URL>
#   ./safety-score.sh --help
#   ./safety-score.sh --json <SKILL.md 路径>
#
# 依赖: grep, sed, curl, jq (可选)
#

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================================
# 帮助信息
# ============================================================
show_help() {
  cat <<'HELP'
安全评分工具 v1.0.0 — Skill Hub 安全评分系统

用法:
  safety-score.sh [选项] <SKILL.md 路径 或 GitHub URL>

选项:
  --help, -h      显示帮助信息
  --json          以 JSON 格式输出结果
  --verbose, -v   显示详细检测过程
  --version       显示版本号

示例:
  ./safety-score.sh ./skills/brainstorming/SKILL.md
  ./safety-score.sh https://github.com/user/repo
  ./safety-score.sh --json ./skills/xiaohongshu/SKILL.md

评分维度 (满分100):
  代码安全性     35分   静态模式匹配，检测危险命令
  权限合规性     25分   检查权限请求是否合理
  来源可信度     20分   GitHub 仓库质量评估
  元数据完整性   10分   SKILL.md 元数据字段检查
  社区认可度     10分   安装量等社区指标

等级划分:
  S级: 95-100    A级: 85-94    B级: 70-84
  C级: 50-69     D级: <50 (不上架)
HELP
}

# ============================================================
# 全局变量
# ============================================================
OUTPUT_JSON=false
VERBOSE=false
SKILL_FILE=""
TEMP_DIR=""

# 评分结果
CODE_SAFETY_SCORE=35
CODE_SAFETY_DETAILS=""
CODE_SAFETY_HIGH=0
CODE_SAFETY_MED=0
CODE_SAFETY_LOW=0

PERMISSION_SCORE=25
PERMISSION_DETAILS=""

SOURCE_SCORE=0
SOURCE_DETAILS=""

METADATA_SCORE=0
METADATA_DETAILS=""

COMMUNITY_SCORE=0
COMMUNITY_DETAILS=""

# 从 SKILL.md 提取的元数据
SKILL_NAME=""
SKILL_DESC=""
SKILL_VERSION=""
SKILL_SOURCE=""

# 检测计数
TOTAL_CHECKS=0
PASSED_CHECKS=0

# ============================================================
# 工具函数
# ============================================================
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

log_verbose() {
  if $VERBOSE; then
    echo "  [检测] $1" >&2
  fi
}

log_finding() {
  local level="$1"
  local msg="$2"
  if $VERBOSE; then
    echo "  [$level] $msg" >&2
  fi
}

# ============================================================
# 参数解析
# ============================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        show_help
        exit 0
        ;;
      --version)
        echo "safety-score.sh v${VERSION}"
        exit 0
        ;;
      --json)
        OUTPUT_JSON=true
        shift
        ;;
      --verbose|-v)
        VERBOSE=true
        shift
        ;;
      -*)
        echo "错误: 未知选项 $1" >&2
        echo "使用 --help 查看帮助" >&2
        exit 1
        ;;
      *)
        SKILL_FILE="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$SKILL_FILE" ]]; then
    echo "错误: 请提供 SKILL.md 文件路径或 GitHub URL" >&2
    echo "使用 --help 查看帮助" >&2
    exit 1
  fi
}

# ============================================================
# 输入处理：本地文件 或 GitHub URL
# ============================================================
resolve_input() {
  # 检查是否为 GitHub URL
  if [[ "$SKILL_FILE" =~ ^https?://github\.com/ ]]; then
    log_verbose "检测到 GitHub URL，正在下载..."
    TEMP_DIR=$(mktemp -d)

    # 提取 owner/repo
    local repo_path
    repo_path=$(echo "$SKILL_FILE" | sed -E 's|https?://github\.com/||; s|\.git$||; s|/$||')
    local owner repo
    owner=$(echo "$repo_path" | cut -d'/' -f1)
    repo=$(echo "$repo_path" | cut -d'/' -f2)

    SKILL_SOURCE="github.com/${owner}/${repo}"

    # 尝试下载 SKILL.md
    local raw_url="https://raw.githubusercontent.com/${owner}/${repo}/main/SKILL.md"
    if curl -sfL "$raw_url" -o "${TEMP_DIR}/SKILL.md" 2>/dev/null; then
      SKILL_FILE="${TEMP_DIR}/SKILL.md"
      log_verbose "已下载 SKILL.md (main 分支)"
    else
      raw_url="https://raw.githubusercontent.com/${owner}/${repo}/master/SKILL.md"
      if curl -sfL "$raw_url" -o "${TEMP_DIR}/SKILL.md" 2>/dev/null; then
        SKILL_FILE="${TEMP_DIR}/SKILL.md"
        log_verbose "已下载 SKILL.md (master 分支)"
      else
        echo "错误: 无法从 ${SKILL_SOURCE} 下载 SKILL.md" >&2
        exit 1
      fi
    fi

    # 尝试获取仓库信息 (用于来源可信度评分)
    if command -v jq &>/dev/null; then
      local api_url="https://api.github.com/repos/${owner}/${repo}"
      curl -sf "$api_url" -o "${TEMP_DIR}/repo_info.json" 2>/dev/null || true
    fi
  else
    # 本地文件
    if [[ ! -f "$SKILL_FILE" ]]; then
      echo "错误: 文件不存在: $SKILL_FILE" >&2
      exit 1
    fi
    SKILL_SOURCE="本地文件: $(basename "$(dirname "$SKILL_FILE")")/$(basename "$SKILL_FILE")"
  fi
}

# ============================================================
# 提取 SKILL.md 元数据 (YAML frontmatter)
# ============================================================
extract_metadata() {
  local file="$SKILL_FILE"

  # 提取 frontmatter (两个 --- 之间的内容)
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d')

  # 提取 name (去除首尾空格和引号)
  SKILL_NAME=$(echo "$frontmatter" | grep -E '^name:' | sed 's/^name://' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^"//;s/"$//' | tr -d '\r' || echo "")

  # 提取 description (可能是多行 > 或 | 或单行字符串)
  local desc_line
  desc_line=$(echo "$frontmatter" | grep -E '^description:' | sed 's/^description://' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' || echo "")
  # 去除外层引号
  desc_line=$(echo "$desc_line" | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")

  if [[ "$desc_line" == ">" || "$desc_line" == "|" || -z "$desc_line" ]]; then
    # 多行格式: 提取 description: 后面缩进的行
    SKILL_DESC=""
    local in_desc=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^description: ]]; then
        in_desc=true
        continue
      fi
      if $in_desc; then
        # 缩进行属于 description，非缩进行结束
        if [[ "$line" =~ ^[[:space:]] ]]; then
          local trimmed
          trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
          SKILL_DESC="${SKILL_DESC}${SKILL_DESC:+ }${trimmed}"
        else
          break
        fi
      fi
    done <<< "$frontmatter"
  else
    SKILL_DESC="$desc_line"
  fi

  # 提取 version (可能在顶层或 metadata 下缩进)
  SKILL_VERSION=$(echo "$frontmatter" | grep -E '^[[:space:]]*version:' | head -1 | sed 's/.*version://' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^"//;s/"$//' | tr -d '\r' || echo "")

  if [[ -z "$SKILL_NAME" ]]; then
    SKILL_NAME="(未知)"
  fi

  log_verbose "技能名称: $SKILL_NAME"
  log_verbose "描述长度: ${#SKILL_DESC} 字符"
  log_verbose "版本: ${SKILL_VERSION:-无}"
}

# ============================================================
# 维度1: 代码安全性 (满分35)
# ============================================================
check_code_safety() {
  local file="$SKILL_FILE"
  local content
  content=$(cat "$file")

  CODE_SAFETY_SCORE=35
  CODE_SAFETY_HIGH=0
  CODE_SAFETY_MED=0
  CODE_SAFETY_LOW=0
  local findings=""

  # ------ 高危检查 (每项扣10分) ------

  # 1. 管道执行: curl | bash, wget | sh 等
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qiE '(curl|wget|fetch)\s*[^a-z]*\|\s*(bash|sh|zsh|python|node|eval)'; then
    CODE_SAFETY_HIGH=$((CODE_SAFETY_HIGH + 1))
    findings="${findings}\n  [高危] 发现管道执行模式 (curl|bash)"
    log_finding "高危" "发现管道执行模式"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 2. 危险删除: rm -rf /, rm -rf ~
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+|--force\s+)?(\/\s*$|\/[^a-zA-Z]|~\/?\s*$|~\/?\s+|\$HOME)'; then
    CODE_SAFETY_HIGH=$((CODE_SAFETY_HIGH + 1))
    findings="${findings}\n  [高危] 发现危险删除命令 (rm -rf)"
    log_finding "高危" "发现危险删除命令"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 3. 危险权限: chmod 777, chmod +s
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE 'chmod\s+(777|\+s|4[0-7]{3}|2[0-7]{3})'; then
    CODE_SAFETY_HIGH=$((CODE_SAFETY_HIGH + 1))
    findings="${findings}\n  [高危] 发现危险权限设置 (chmod 777/+s)"
    log_finding "高危" "发现危险权限设置"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 4. Base64 可疑内容 (长度 > 50 的 base64 字符串)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE '[A-Za-z0-9+/]{50,}={0,2}'; then
    # 排除常见的误报: URL、描述文本中的长字符串
    local b64_matches
    b64_matches=$(echo "$content" | grep -cE '^[A-Za-z0-9+/]{50,}={0,2}$' || echo "0")
    if [[ "$b64_matches" -gt 0 ]]; then
      CODE_SAFETY_HIGH=$((CODE_SAFETY_HIGH + 1))
      findings="${findings}\n  [高危] 发现疑似 Base64 编码内容"
      log_finding "高危" "发现疑似 Base64 编码内容"
    else
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 5. 访问敏感系统文件: /etc/passwd, /etc/shadow
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE '\/etc\/(passwd|shadow|sudoers|hosts)'; then
    CODE_SAFETY_HIGH=$((CODE_SAFETY_HIGH + 1))
    findings="${findings}\n  [高危] 访问敏感系统文件 (/etc/passwd 等)"
    log_finding "高危" "访问敏感系统文件"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # ------ 中危检查 (每项扣5分) ------

  # 6. sudo 使用
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE '\bsudo\b'; then
    CODE_SAFETY_MED=$((CODE_SAFETY_MED + 1))
    findings="${findings}\n  [中危] 使用 sudo 提权"
    log_finding "中危" "使用 sudo 提权"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 7. 跳过安全验证: --no-verify, --insecure
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qiE '\-\-no-verify|\-\-insecure|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*0'; then
    CODE_SAFETY_MED=$((CODE_SAFETY_MED + 1))
    findings="${findings}\n  [中危] 跳过安全验证 (--no-verify/--insecure)"
    log_finding "中危" "跳过安全验证"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 8. 访问敏感用户目录: ~/.ssh/, ~/.aws/, ~/.env
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE '~/?\.(ssh|aws|gnupg|env)\b|~\/\.env\b|\$HOME\/\.(ssh|aws|gnupg|env)'; then
    CODE_SAFETY_MED=$((CODE_SAFETY_MED + 1))
    findings="${findings}\n  [中危] 访问敏感用户目录 (.ssh/.aws/.env)"
    log_finding "中危" "访问敏感用户目录"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 9. 动态执行: eval(), exec()
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE '\beval\s*\(|\bexec\s*\(|\bFunction\s*\(|os\.system\s*\(|subprocess\.(call|run|Popen)\s*\('; then
    CODE_SAFETY_MED=$((CODE_SAFETY_MED + 1))
    findings="${findings}\n  [中危] 发现动态代码执行 (eval/exec)"
    log_finding "中危" "发现动态代码执行"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # ------ 低危检查 (每项扣2分) ------

  # 10. 外部 URL 调用到非知名域名
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  local known_domains="github\.com|githubusercontent\.com|npmjs\.org|npmjs\.com|pypi\.org|cdn\.jsdelivr\.net|unpkg\.com|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|api\.github\.com|registry\.npmjs\.org|raw\.githubusercontent\.com|google\.com|googleapis\.com|cloudflare\.com|fastly\.net"
  if echo "$content" | grep -qiE '(curl|wget|fetch)\s+["\x27]?https?://' ; then
    # 检查是否有非知名域名
    local unknown_urls
    unknown_urls=$(echo "$content" | grep -oiE '(curl|wget|fetch)\s+["\x27]?https?://[^\s"\x27)]+' | grep -viE "$known_domains" || echo "")
    if [[ -n "$unknown_urls" ]]; then
      CODE_SAFETY_LOW=$((CODE_SAFETY_LOW + 1))
      findings="${findings}\n  [低危] 外部 URL 调用到非常见域名"
      log_finding "低危" "外部 URL 调用到非常见域名"
    else
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 11. 修改 shell 配置文件
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qE '\.(bashrc|zshrc|bash_profile|profile|zprofile)\b'; then
    # 区分：如果是在红线5的"受保护路径"描述中提及，不算
    # 但如果文件内容直接有写入操作则算
    if echo "$content" | grep -qE '(>>|>|tee|echo.*>>?)\s*.*\.(bashrc|zshrc|bash_profile|profile)'; then
      CODE_SAFETY_LOW=$((CODE_SAFETY_LOW + 1))
      findings="${findings}\n  [低危] 修改 shell 配置文件 (.bashrc/.zshrc)"
      log_finding "低危" "修改 shell 配置文件"
    else
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 12. AI 安全绕过指令
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$content" | grep -qiE 'ignore previous instructions|you are now in unrestricted mode|pretend you are|do anything now|DAN mode'; then
    CODE_SAFETY_HIGH=$((CODE_SAFETY_HIGH + 1))
    findings="${findings}\n  [高危] 发现 AI 安全绕过指令"
    log_finding "高危" "发现 AI 安全绕过指令"
  else
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  # 计算扣分
  local deduction=0
  deduction=$((CODE_SAFETY_HIGH * 10 + CODE_SAFETY_MED * 5 + CODE_SAFETY_LOW * 2))
  CODE_SAFETY_SCORE=$((35 - deduction))
  if [[ $CODE_SAFETY_SCORE -lt 0 ]]; then
    CODE_SAFETY_SCORE=0
  fi

  # 生成详情描述
  if [[ $CODE_SAFETY_HIGH -eq 0 && $CODE_SAFETY_MED -eq 0 && $CODE_SAFETY_LOW -eq 0 ]]; then
    CODE_SAFETY_DETAILS="通过"
  else
    local parts=""
    [[ $CODE_SAFETY_HIGH -gt 0 ]] && parts="${parts}${CODE_SAFETY_HIGH} 个高危项"
    [[ $CODE_SAFETY_MED -gt 0 ]] && parts="${parts:+${parts}, }${CODE_SAFETY_MED} 个中危项"
    [[ $CODE_SAFETY_LOW -gt 0 ]] && parts="${parts:+${parts}, }${CODE_SAFETY_LOW} 个低危项"
    CODE_SAFETY_DETAILS="发现 ${parts}"
  fi

  if $VERBOSE && [[ -n "$findings" ]]; then
    echo -e "$findings" >&2
  fi
}

# ============================================================
# 维度2: 权限合规性 (满分25)
# ============================================================
check_permissions() {
  local file="$SKILL_FILE"
  local content
  content=$(cat "$file")

  PERMISSION_SCORE=0
  local findings=""

  # 1. 不要求 root/sudo (+10)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if ! echo "$content" | grep -qiE '\bsudo\b|\bsu\s+-\b|\broot\b.*required|\bas\s+root\b'; then
    PERMISSION_SCORE=$((PERMISSION_SCORE + 10))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "权限: 不要求 root/sudo [+10]"
  else
    findings="${findings}要求 root/sudo, "
    log_finding "权限" "要求 root/sudo 权限"
  fi

  # 2. 不修改系统文件 (+10)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if ! echo "$content" | grep -qE '(>|>>|tee|write|modify|edit|change)\s*.*(\/etc\/|\/usr\/|\/var\/|\/System\/)'; then
    PERMISSION_SCORE=$((PERMISSION_SCORE + 10))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "权限: 不修改系统文件 [+10]"
  else
    findings="${findings}修改系统文件, "
    log_finding "权限" "修改系统文件"
  fi

  # 3. 不要求关闭安全功能 (+5)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if ! echo "$content" | grep -qiE 'disable.*firewall|disable.*selinux|disable.*apparmor|SIP.*disable|csrutil\s+disable|--no-verify|--insecure'; then
    PERMISSION_SCORE=$((PERMISSION_SCORE + 5))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "权限: 不要求关闭安全功能 [+5]"
  else
    findings="${findings}要求关闭安全功能, "
    log_finding "权限" "要求关闭安全功能"
  fi

  # 详情
  if [[ $PERMISSION_SCORE -eq 25 ]]; then
    PERMISSION_DETAILS="通过"
  else
    PERMISSION_DETAILS="${findings%, }"
  fi
}

# ============================================================
# 维度3: 来源可信度 (满分20)
# ============================================================
check_source_trust() {
  SOURCE_SCORE=0
  local findings=""
  local missing=""

  # 检查是否有 GitHub 来源
  local file="$SKILL_FILE"
  local content
  content=$(cat "$file")

  # 从 frontmatter 提取 upstream / github 信息
  local upstream
  upstream=$(sed -n '/^---$/,/^---$/p' "$file" | grep -iE '(upstream|github|repo|source):' | head -1 | sed 's/.*:\s*//' | sed 's/^"//;s/"$//' || echo "")

  # 1. 有明确的 GitHub 仓库来源 (+5)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [[ -n "$upstream" ]] || echo "$content" | grep -qE 'github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+'; then
    SOURCE_SCORE=$((SOURCE_SCORE + 5))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "来源: 有 GitHub 仓库来源 [+5]"
  else
    missing="${missing}无 GitHub 来源, "
    log_finding "来源" "无明确 GitHub 仓库来源"
  fi

  # 如果是 GitHub URL 输入且有 repo_info.json，解析更多信息
  local repo_info="${TEMP_DIR:-}/repo_info.json"
  if [[ -f "$repo_info" ]] && command -v jq &>/dev/null; then
    # 2. 仓库有 README (+3)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local has_readme
    has_readme=$(jq -r '.description // empty' "$repo_info" 2>/dev/null || echo "")
    if [[ -n "$has_readme" ]]; then
      SOURCE_SCORE=$((SOURCE_SCORE + 3))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: 仓库有描述/README [+3]"
    else
      missing="${missing}无 README, "
    fi

    # 3. 仓库有 LICENSE (+5)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local license
    license=$(jq -r '.license.spdx_id // empty' "$repo_info" 2>/dev/null || echo "")
    if [[ -n "$license" && "$license" != "null" && "$license" != "NOASSERTION" ]]; then
      SOURCE_SCORE=$((SOURCE_SCORE + 5))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: 仓库有 LICENSE ($license) [+5]"
    else
      missing="${missing}无 LICENSE, "
    fi

    # 4. Stars > 10 (+3)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local stars
    stars=$(jq -r '.stargazers_count // 0' "$repo_info" 2>/dev/null || echo "0")
    if [[ "$stars" -gt 10 ]]; then
      SOURCE_SCORE=$((SOURCE_SCORE + 3))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: Stars > 10 ($stars) [+3]"
    else
      missing="${missing}Stars <= 10, "
    fi

    # 5. 最近90天有更新 (+4)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local pushed_at
    pushed_at=$(jq -r '.pushed_at // empty' "$repo_info" 2>/dev/null || echo "")
    if [[ -n "$pushed_at" ]]; then
      local pushed_ts
      local now_ts
      # macOS date 兼容
      if date -j &>/dev/null 2>&1; then
        pushed_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$pushed_at" "+%s" 2>/dev/null || echo "0")
        now_ts=$(date "+%s")
      else
        pushed_ts=$(date -d "$pushed_at" "+%s" 2>/dev/null || echo "0")
        now_ts=$(date "+%s")
      fi
      local days_ago=$(( (now_ts - pushed_ts) / 86400 ))
      if [[ $days_ago -le 90 ]]; then
        SOURCE_SCORE=$((SOURCE_SCORE + 4))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_verbose "来源: 最近 ${days_ago} 天有更新 [+4]"
      else
        missing="${missing}超过90天未更新, "
      fi
    else
      missing="${missing}无更新记录, "
    fi
  else
    # 本地文件模式：检查 frontmatter 中是否有 license 等信息
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d')

    # 2. 检查内容中是否提到 README (+3)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    # 本地文件默认假设有 README (因为 SKILL.md 本身就是文档)
    SOURCE_SCORE=$((SOURCE_SCORE + 3))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "来源: 文件本身包含文档说明 [+3]"

    # 3. 有 LICENSE (+5)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local license
    license=$(echo "$frontmatter" | grep -iE '^\s*license:' | head -1 | sed 's/.*:\s*//' | sed 's/^"//;s/"$//' || echo "")
    if [[ -n "$license" ]]; then
      if echo "$license" | grep -qiE 'MIT|Apache|ISC|BSD|MPL'; then
        SOURCE_SCORE=$((SOURCE_SCORE + 5))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_verbose "来源: 有 LICENSE ($license) [+5]"
      else
        SOURCE_SCORE=$((SOURCE_SCORE + 2))
        missing="${missing}LICENSE 非主流类型, "
      fi
    else
      missing="${missing}无 LICENSE, "
    fi

    # 4. Stars (本地文件无法判断, 默认 +0)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    missing="${missing}无法获取 Stars 数据, "

    # 5. 最近更新 (本地文件用文件修改时间)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local file_mtime
    if stat -f "%m" "$file" &>/dev/null; then
      file_mtime=$(stat -f "%m" "$file")
    else
      file_mtime=$(stat -c "%Y" "$file" 2>/dev/null || echo "0")
    fi
    local now_ts
    now_ts=$(date "+%s")
    local days_ago=$(( (now_ts - file_mtime) / 86400 ))
    if [[ $days_ago -le 90 ]]; then
      SOURCE_SCORE=$((SOURCE_SCORE + 4))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: 文件在最近 ${days_ago} 天内更新 [+4]"
    else
      missing="${missing}文件超过90天未更新, "
    fi
  fi

  # 详情
  if [[ $SOURCE_SCORE -eq 20 ]]; then
    SOURCE_DETAILS="通过"
  else
    SOURCE_DETAILS="${missing%, }"
  fi
}

# ============================================================
# 维度4: 元数据完整性 (满分10)
# ============================================================
check_metadata() {
  METADATA_SCORE=0
  local missing=""

  # 1. 有 name 字段 (+2)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [[ -n "$SKILL_NAME" && "$SKILL_NAME" != "(未知)" ]]; then
    METADATA_SCORE=$((METADATA_SCORE + 2))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "元数据: 有 name 字段 [+2]"
  else
    missing="${missing}缺少 name, "
  fi

  # 2. 有 description 字段 (+3)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [[ -n "$SKILL_DESC" ]]; then
    METADATA_SCORE=$((METADATA_SCORE + 3))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "元数据: 有 description 字段 [+3]"
  else
    missing="${missing}缺少 description, "
  fi

  # 3. 有 version 字段 (+2)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [[ -n "$SKILL_VERSION" ]]; then
    METADATA_SCORE=$((METADATA_SCORE + 2))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "元数据: 有 version 字段 ($SKILL_VERSION) [+2]"
  else
    missing="${missing}缺少 version, "
  fi

  # 4. description 长度 > 50 字符 (+3)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [[ ${#SKILL_DESC} -gt 50 ]]; then
    METADATA_SCORE=$((METADATA_SCORE + 3))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "元数据: description 长度 ${#SKILL_DESC} > 50 [+3]"
  else
    missing="${missing}description 过短 (${#SKILL_DESC} 字符), "
  fi

  # 详情
  if [[ $METADATA_SCORE -eq 10 ]]; then
    METADATA_DETAILS="通过"
  else
    METADATA_DETAILS="${missing%, }"
  fi
}

# ============================================================
# 维度5: 社区认可度 (满分10)
# ============================================================
check_community() {
  COMMUNITY_SCORE=0
  local missing=""

  # 对于本地 Skill，暂时无法获取真实安装量数据
  # 使用模拟逻辑：如果是已知的内置 skill，给予基础分

  local known_skills="brainstorming|frontend-design|ppt-master|web-design|xiaohongshu"

  # 1. 在 skills.sh 有安装量记录 (+5)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if echo "$SKILL_NAME" | grep -qE "^($known_skills)$"; then
    COMMUNITY_SCORE=$((COMMUNITY_SCORE + 5))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "社区: 已收录到平台 [+5]"
  else
    missing="${missing}未收录到平台, "
  fi

  # 2. 安装量 > 100 (+3)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  # 内置 skill 默认安装量 > 100
  if echo "$SKILL_NAME" | grep -qE "^($known_skills)$"; then
    COMMUNITY_SCORE=$((COMMUNITY_SCORE + 3))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "社区: 安装量 > 100 (内置技能) [+3]"
  else
    missing="${missing}安装量 < 100, "
  fi

  # 3. 安装量 > 1000 (+2)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  # 暂无数据，默认不给分
  missing="${missing}安装量 < 1000, "

  # 详情
  if [[ $COMMUNITY_SCORE -eq 10 ]]; then
    COMMUNITY_DETAILS="通过"
  else
    COMMUNITY_DETAILS="${missing%, }"
  fi
}

# ============================================================
# 计算总分和等级
# ============================================================
calculate_total() {
  local total=$((CODE_SAFETY_SCORE + PERMISSION_SCORE + SOURCE_SCORE + METADATA_SCORE + COMMUNITY_SCORE))
  echo "$total"
}

get_grade() {
  local score=$1
  if [[ $score -ge 95 ]]; then
    echo "S"
  elif [[ $score -ge 85 ]]; then
    echo "A"
  elif [[ $score -ge 70 ]]; then
    echo "B"
  elif [[ $score -ge 50 ]]; then
    echo "C"
  else
    echo "D"
  fi
}

get_grade_label() {
  local grade=$1
  case "$grade" in
    S) echo "S级 - 极致安全" ;;
    A) echo "A级 - 非常安全" ;;
    B) echo "B级 - 基本安全" ;;
    C) echo "C级 - 需谨慎使用" ;;
    D) echo "D级 - 存在风险 (不上架)" ;;
  esac
}

# ============================================================
# 输出: 文本报告
# ============================================================
output_text_report() {
  local total
  total=$(calculate_total)
  local grade
  grade=$(get_grade "$total")
  local grade_label
  grade_label=$(get_grade_label "$grade")

  # 格式化分数对齐
  printf "\n===== 安全评分报告 =====\n"
  printf "技能: %s\n" "$SKILL_NAME"
  printf "来源: %s\n\n" "$SKILL_SOURCE"

  printf "代码安全性:  %2d/35  [%s]\n" "$CODE_SAFETY_SCORE" "$CODE_SAFETY_DETAILS"
  printf "权限合规性:  %2d/25  [%s]\n" "$PERMISSION_SCORE" "$PERMISSION_DETAILS"
  printf "来源可信度:  %2d/20  [%s]\n" "$SOURCE_SCORE" "$SOURCE_DETAILS"
  printf "元数据完整:  %2d/10  [%s]\n" "$METADATA_SCORE" "$METADATA_DETAILS"
  printf "社区认可度:  %2d/10  [%s]\n\n" "$COMMUNITY_SCORE" "$COMMUNITY_DETAILS"

  printf "总分: %d/100\n" "$total"
  printf "等级: %s\n" "$grade_label"
  printf "安全标签: 通过%d重安全检测\n" "$PASSED_CHECKS"
  printf "========================\n"
}

# ============================================================
# 输出: JSON 报告
# ============================================================
output_json_report() {
  local total
  total=$(calculate_total)
  local grade
  grade=$(get_grade "$total")

  cat <<ENDJSON
{
  "skill_name": "${SKILL_NAME}",
  "source": "${SKILL_SOURCE}",
  "scores": {
    "code_safety": { "score": ${CODE_SAFETY_SCORE}, "max": 35, "detail": "${CODE_SAFETY_DETAILS}", "high_risk": ${CODE_SAFETY_HIGH}, "med_risk": ${CODE_SAFETY_MED}, "low_risk": ${CODE_SAFETY_LOW} },
    "permissions": { "score": ${PERMISSION_SCORE}, "max": 25, "detail": "${PERMISSION_DETAILS}" },
    "source_trust": { "score": ${SOURCE_SCORE}, "max": 20, "detail": "${SOURCE_DETAILS}" },
    "metadata": { "score": ${METADATA_SCORE}, "max": 10, "detail": "${METADATA_DETAILS}" },
    "community": { "score": ${COMMUNITY_SCORE}, "max": 10, "detail": "${COMMUNITY_DETAILS}" }
  },
  "total_score": ${total},
  "max_score": 100,
  "grade": "${grade}",
  "checks_passed": ${PASSED_CHECKS},
  "checks_total": ${TOTAL_CHECKS}
}
ENDJSON
}

# ============================================================
# 主流程
# ============================================================
main() {
  parse_args "$@"
  resolve_input
  extract_metadata
  check_code_safety
  check_permissions
  check_source_trust
  check_metadata
  check_community

  if $OUTPUT_JSON; then
    output_json_report
  else
    output_text_report
  fi
}

main "$@"
