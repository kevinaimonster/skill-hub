#!/usr/bin/env bash
#
# safety-score-v2.sh - Skill 安全评分工具 v2
# 在 v1 基础上新增 OpenSSF Scorecard 评估 + 社区安全反馈
#
# 用法:
#   ./safety-score-v2.sh <SKILL.md 路径 或 GitHub URL>
#   ./safety-score-v2.sh --openssf <GitHub URL>
#   ./safety-score-v2.sh --help
#   ./safety-score-v2.sh --json <SKILL.md 路径>
#
# 依赖: grep, sed, curl, jq (可选，OpenSSF 功能需要 jq)
#

set -euo pipefail

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================================
# 帮助信息
# ============================================================
show_help() {
  cat <<'HELP'
安全评分工具 v2.0.0 — Skill Hub 安全评分系统 (OpenSSF 增强版)

用法:
  safety-score-v2.sh [选项] <SKILL.md 路径 或 GitHub URL>

选项:
  --help, -h      显示帮助信息
  --json          以 JSON 格式输出结果
  --verbose, -v   显示详细检测过程
  --version       显示版本号
  --openssf       启用 OpenSSF Scorecard 查询 (默认关闭)

示例:
  ./safety-score-v2.sh ./skills/brainstorming/SKILL.md
  ./safety-score-v2.sh https://github.com/user/repo
  ./safety-score-v2.sh --openssf https://github.com/user/repo
  ./safety-score-v2.sh --openssf --json https://github.com/user/repo

评分维度 (满分100):
  代码安全性      30分   静态模式匹配，检测危险命令
  权限合规性      20分   检查权限请求是否合理
  来源可信度      15分   GitHub 仓库质量评估
  OpenSSF 评估    15分   OpenSSF Scorecard 第三方安全评估
  元数据完整性    10分   SKILL.md 元数据字段检查
  社区安全反馈    10分   社区举报 + 安全 Issue 检查

等级划分:
  S级: 95-100    A级: 85-94    B级: 70-84
  C级: 50-69     D级: <50 (不上架)

注意:
  --openssf 选项需要 jq 和网络连接。
  如果 OpenSSF API 不可用，该维度将降级，15分按比例分配到其他维度。
HELP
}

# ============================================================
# 全局变量
# ============================================================
OUTPUT_JSON=false
VERBOSE=false
ENABLE_OPENSSF=false
SKILL_FILE=""
TEMP_DIR=""

# 评分结果 (v2 权重调整)
CODE_SAFETY_SCORE=30
CODE_SAFETY_MAX=30
CODE_SAFETY_DETAILS=""
CODE_SAFETY_HIGH=0
CODE_SAFETY_MED=0
CODE_SAFETY_LOW=0

PERMISSION_SCORE=20
PERMISSION_MAX=20
PERMISSION_DETAILS=""

SOURCE_SCORE=0
SOURCE_MAX=15
SOURCE_DETAILS=""

OPENSSF_SCORE=0
OPENSSF_MAX=15
OPENSSF_DETAILS=""
OPENSSF_AVAILABLE=false
OPENSSF_RAW_SCORE=""   # 原始 OpenSSF 评分 (0-10)
OPENSSF_CHECKS=""      # 具体检查项

METADATA_SCORE=0
METADATA_MAX=10
METADATA_DETAILS=""

COMMUNITY_FEEDBACK_SCORE=0
COMMUNITY_FEEDBACK_MAX=10
COMMUNITY_FEEDBACK_DETAILS=""
SECURITY_ISSUES_COUNT=0

# 从 SKILL.md 提取的元数据
SKILL_NAME=""
SKILL_DESC=""
SKILL_VERSION=""
SKILL_SOURCE=""

# GitHub owner/repo (提取后全局可用)
GH_OWNER=""
GH_REPO=""

# 检测计数
TOTAL_CHECKS=0
PASSED_CHECKS=0

# 降级标记
DEGRADED=false
DEGRADED_MSG=""

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
        echo "safety-score-v2.sh v${VERSION}"
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
      --openssf)
        ENABLE_OPENSSF=true
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
    GH_OWNER=$(echo "$repo_path" | cut -d'/' -f1)
    GH_REPO=$(echo "$repo_path" | cut -d'/' -f2)

    SKILL_SOURCE="github.com/${GH_OWNER}/${GH_REPO}"

    # 尝试下载 SKILL.md
    local raw_url="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/main/SKILL.md"
    if curl -sfL --connect-timeout 5 "$raw_url" -o "${TEMP_DIR}/SKILL.md" 2>/dev/null; then
      SKILL_FILE="${TEMP_DIR}/SKILL.md"
      log_verbose "已下载 SKILL.md (main 分支)"
    else
      raw_url="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/master/SKILL.md"
      if curl -sfL --connect-timeout 5 "$raw_url" -o "${TEMP_DIR}/SKILL.md" 2>/dev/null; then
        SKILL_FILE="${TEMP_DIR}/SKILL.md"
        log_verbose "已下载 SKILL.md (master 分支)"
      else
        # 没有 SKILL.md 的情况下，创建一个空的占位，仍然继续评估
        echo "---" > "${TEMP_DIR}/SKILL.md"
        echo "name: ${GH_REPO}" >> "${TEMP_DIR}/SKILL.md"
        echo "---" >> "${TEMP_DIR}/SKILL.md"
        SKILL_FILE="${TEMP_DIR}/SKILL.md"
        log_verbose "仓库中未找到 SKILL.md，使用空占位文件继续评估"
      fi
    fi

    # 尝试获取仓库信息 (用于来源可信度评分)
    if command -v jq &>/dev/null; then
      local api_url="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}"
      curl -sf --connect-timeout 5 "$api_url" -o "${TEMP_DIR}/repo_info.json" 2>/dev/null || true
    fi
  else
    # 本地文件
    if [[ ! -f "$SKILL_FILE" ]]; then
      echo "错误: 文件不存在: $SKILL_FILE" >&2
      exit 1
    fi
    SKILL_SOURCE="本地文件: $(basename "$(dirname "$SKILL_FILE")")/$(basename "$SKILL_FILE")"

    # 尝试从 SKILL.md 中提取 GitHub owner/repo
    local content
    content=$(cat "$SKILL_FILE")
    local gh_url
    gh_url=$(echo "$content" | grep -oE 'github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+' | head -1 || echo "")
    if [[ -n "$gh_url" ]]; then
      GH_OWNER=$(echo "$gh_url" | cut -d'/' -f2)
      GH_REPO=$(echo "$gh_url" | cut -d'/' -f3)
      log_verbose "从文件中提取到 GitHub 来源: ${GH_OWNER}/${GH_REPO}"
    fi
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

  # 提取 version
  SKILL_VERSION=$(echo "$frontmatter" | grep -E '^[[:space:]]*version:' | head -1 | sed 's/.*version://' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^"//;s/"$//' | tr -d '\r' || echo "")

  if [[ -z "$SKILL_NAME" ]]; then
    SKILL_NAME="(未知)"
  fi

  log_verbose "技能名称: $SKILL_NAME"
  log_verbose "描述长度: ${#SKILL_DESC} 字符"
  log_verbose "版本: ${SKILL_VERSION:-无}"
}

# ============================================================
# 维度1: 代码安全性 (满分30, v2调整)
# ============================================================
check_code_safety() {
  local file="$SKILL_FILE"
  local content
  content=$(cat "$file")

  CODE_SAFETY_SCORE=30
  CODE_SAFETY_HIGH=0
  CODE_SAFETY_MED=0
  CODE_SAFETY_LOW=0
  local findings=""

  # ------ 高危检查 (每项扣8分) ------

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

  # ------ 中危检查 (每项扣4分) ------

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

  # 计算扣分 (v2: 高危扣8，中危扣4，低危扣2)
  local deduction=0
  deduction=$((CODE_SAFETY_HIGH * 8 + CODE_SAFETY_MED * 4 + CODE_SAFETY_LOW * 2))
  CODE_SAFETY_SCORE=$((30 - deduction))
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
# 维度2: 权限合规性 (满分20, v2调整)
# ============================================================
check_permissions() {
  local file="$SKILL_FILE"
  local content
  content=$(cat "$file")

  PERMISSION_SCORE=0
  local findings=""

  # 1. 不要求 root/sudo (+8)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if ! echo "$content" | grep -qiE '\bsudo\b|\bsu\s+-\b|\broot\b.*required|\bas\s+root\b'; then
    PERMISSION_SCORE=$((PERMISSION_SCORE + 8))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "权限: 不要求 root/sudo [+8]"
  else
    findings="${findings}要求 root/sudo, "
    log_finding "权限" "要求 root/sudo 权限"
  fi

  # 2. 不修改系统文件 (+8)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if ! echo "$content" | grep -qE '(>|>>|tee|write|modify|edit|change)\s*.*(\/etc\/|\/usr\/|\/var\/|\/System\/)'; then
    PERMISSION_SCORE=$((PERMISSION_SCORE + 8))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "权限: 不修改系统文件 [+8]"
  else
    findings="${findings}修改系统文件, "
    log_finding "权限" "修改系统文件"
  fi

  # 3. 不要求关闭安全功能 (+4)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if ! echo "$content" | grep -qiE 'disable.*firewall|disable.*selinux|disable.*apparmor|SIP.*disable|csrutil\s+disable|--no-verify|--insecure'; then
    PERMISSION_SCORE=$((PERMISSION_SCORE + 4))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "权限: 不要求关闭安全功能 [+4]"
  else
    findings="${findings}要求关闭安全功能, "
    log_finding "权限" "要求关闭安全功能"
  fi

  # 详情
  if [[ $PERMISSION_SCORE -eq 20 ]]; then
    PERMISSION_DETAILS="通过"
  else
    PERMISSION_DETAILS="${findings%, }"
  fi
}

# ============================================================
# 维度3: 来源可信度 (满分15, v2调整)
# ============================================================
check_source_trust() {
  SOURCE_SCORE=0
  local findings=""
  local missing=""

  local file="$SKILL_FILE"
  local content
  content=$(cat "$file")

  # 从 frontmatter 提取 upstream / github 信息
  local upstream
  upstream=$(sed -n '/^---$/,/^---$/p' "$file" | grep -iE '(upstream|github|repo|source):' | head -1 | sed 's/.*:\s*//' | sed 's/^"//;s/"$//' || echo "")

  # 1. 有明确的 GitHub 仓库来源 (+4)
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [[ -n "$upstream" ]] || echo "$content" | grep -qE 'github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+'; then
    SOURCE_SCORE=$((SOURCE_SCORE + 4))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "来源: 有 GitHub 仓库来源 [+4]"
  else
    missing="${missing}无 GitHub 来源, "
    log_finding "来源" "无明确 GitHub 仓库来源"
  fi

  # 如果是 GitHub URL 输入且有 repo_info.json
  local repo_info="${TEMP_DIR:-}/repo_info.json"
  if [[ -f "$repo_info" ]] && command -v jq &>/dev/null; then
    # 2. 仓库有描述 (+2)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local has_desc
    has_desc=$(jq -r '.description // empty' "$repo_info" 2>/dev/null || echo "")
    if [[ -n "$has_desc" ]]; then
      SOURCE_SCORE=$((SOURCE_SCORE + 2))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: 仓库有描述 [+2]"
    else
      missing="${missing}无仓库描述, "
    fi

    # 3. 仓库有 LICENSE (+4)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local license
    license=$(jq -r '.license.spdx_id // empty' "$repo_info" 2>/dev/null || echo "")
    if [[ -n "$license" && "$license" != "null" && "$license" != "NOASSERTION" ]]; then
      SOURCE_SCORE=$((SOURCE_SCORE + 4))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: 仓库有 LICENSE ($license) [+4]"
    else
      missing="${missing}无 LICENSE, "
    fi

    # 4. Stars > 10 (+2)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local stars
    stars=$(jq -r '.stargazers_count // 0' "$repo_info" 2>/dev/null || echo "0")
    if [[ "$stars" -gt 10 ]]; then
      SOURCE_SCORE=$((SOURCE_SCORE + 2))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: Stars > 10 ($stars) [+2]"
    else
      missing="${missing}Stars <= 10, "
    fi

    # 5. 最近90天有更新 (+3)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local pushed_at
    pushed_at=$(jq -r '.pushed_at // empty' "$repo_info" 2>/dev/null || echo "")
    if [[ -n "$pushed_at" ]]; then
      local pushed_ts now_ts
      if date -j &>/dev/null 2>&1; then
        pushed_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$pushed_at" "+%s" 2>/dev/null || echo "0")
        now_ts=$(date "+%s")
      else
        pushed_ts=$(date -d "$pushed_at" "+%s" 2>/dev/null || echo "0")
        now_ts=$(date "+%s")
      fi
      local days_ago=$(( (now_ts - pushed_ts) / 86400 ))
      if [[ $days_ago -le 90 ]]; then
        SOURCE_SCORE=$((SOURCE_SCORE + 3))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_verbose "来源: 最近 ${days_ago} 天有更新 [+3]"
      else
        missing="${missing}超过90天未更新, "
      fi
    else
      missing="${missing}无更新记录, "
    fi
  else
    # 本地文件模式
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d')

    # 2. 有文档说明 (+2)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    SOURCE_SCORE=$((SOURCE_SCORE + 2))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    log_verbose "来源: 文件本身包含文档说明 [+2]"

    # 3. 有 LICENSE (+4)
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    local license
    license=$(echo "$frontmatter" | grep -iE '^\s*license:' | head -1 | sed 's/.*:\s*//' | sed 's/^"//;s/"$//' || echo "")
    if [[ -n "$license" ]]; then
      if echo "$license" | grep -qiE 'MIT|Apache|ISC|BSD|MPL'; then
        SOURCE_SCORE=$((SOURCE_SCORE + 4))
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_verbose "来源: 有 LICENSE ($license) [+4]"
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
      SOURCE_SCORE=$((SOURCE_SCORE + 3))
      PASSED_CHECKS=$((PASSED_CHECKS + 1))
      log_verbose "来源: 文件在最近 ${days_ago} 天内更新 [+3]"
    else
      missing="${missing}文件超过90天未更新, "
    fi
  fi

  # 详情
  if [[ $SOURCE_SCORE -eq 15 ]]; then
    SOURCE_DETAILS="通过"
  else
    SOURCE_DETAILS="${missing%, }"
  fi
}

# ============================================================
# 维度4: OpenSSF Scorecard 评估 (满分15, v2新增)
# ============================================================
check_openssf() {
  OPENSSF_SCORE=0
  OPENSSF_AVAILABLE=false
  OPENSSF_CHECKS=""

  # 前提: 需要 --openssf 选项且有 GitHub 来源
  if ! $ENABLE_OPENSSF; then
    OPENSSF_DETAILS="未启用 (使用 --openssf 选项启用)"
    DEGRADED=true
    DEGRADED_MSG="OpenSSF 评估: 未启用，已降级评分"
    return
  fi

  if [[ -z "$GH_OWNER" || -z "$GH_REPO" ]]; then
    OPENSSF_DETAILS="不可用 (无 GitHub 来源，无法查询 OpenSSF)"
    DEGRADED=true
    DEGRADED_MSG="OpenSSF 评估: 不可用（无 GitHub 来源），已降级评分"
    return
  fi

  # 检查 jq 是否可用
  if ! command -v jq &>/dev/null; then
    OPENSSF_DETAILS="不可用 (需要 jq 解析 API 响应)"
    return
  fi

  log_verbose "正在查询 OpenSSF Scorecard API: ${GH_OWNER}/${GH_REPO} ..."

  # 调用 OpenSSF Scorecard API (超时 5 秒)
  local api_url="https://api.scorecard.dev/projects/github.com/${GH_OWNER}/${GH_REPO}"
  local scorecard_json=""
  local api_ok=false

  if [[ -z "$TEMP_DIR" ]]; then
    TEMP_DIR=$(mktemp -d)
  fi

  if curl -sf --connect-timeout 5 --max-time 10 "$api_url" -o "${TEMP_DIR}/scorecard.json" 2>/dev/null; then
    scorecard_json="${TEMP_DIR}/scorecard.json"
    # 验证 JSON 有效性
    if jq -e '.score' "$scorecard_json" &>/dev/null; then
      api_ok=true
    fi
  fi

  if ! $api_ok; then
    # API 不可用，降级处理
    OPENSSF_AVAILABLE=false
    OPENSSF_DETAILS="不可用 (API 超时或仓库未收录)，已降级评分"
    DEGRADED=true
    DEGRADED_MSG="OpenSSF 评估: 不可用（API 超时），已降级评分"
    log_verbose "OpenSSF API 不可用，启动降级模式"
    return
  fi

  # API 可用，解析评分
  OPENSSF_AVAILABLE=true
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  # 提取总分 (0-10)
  OPENSSF_RAW_SCORE=$(jq -r '.score // 0' "$scorecard_json" 2>/dev/null || echo "0")
  # 处理浮点数 -> 取整数部分进行比较
  local raw_int
  raw_int=$(printf "%.0f" "$OPENSSF_RAW_SCORE" 2>/dev/null || echo "0")

  log_verbose "OpenSSF 总分: ${OPENSSF_RAW_SCORE}/10"

  # 提取关键检查项
  local maintained_score code_review_score license_score vuln_score branch_prot_score
  maintained_score=$(jq -r '.checks[] | select(.name == "Maintained") | .score // -1' "$scorecard_json" 2>/dev/null || echo "-1")
  code_review_score=$(jq -r '.checks[] | select(.name == "Code-Review") | .score // -1' "$scorecard_json" 2>/dev/null || echo "-1")
  license_score=$(jq -r '.checks[] | select(.name == "License") | .score // -1' "$scorecard_json" 2>/dev/null || echo "-1")
  vuln_score=$(jq -r '.checks[] | select(.name == "Vulnerabilities") | .score // -1' "$scorecard_json" 2>/dev/null || echo "-1")
  branch_prot_score=$(jq -r '.checks[] | select(.name == "Branch-Protection") | .score // -1' "$scorecard_json" 2>/dev/null || echo "-1")

  # 构建检查项报告
  OPENSSF_CHECKS="Maintained=${maintained_score}/10"
  OPENSSF_CHECKS="${OPENSSF_CHECKS}, Code-Review=${code_review_score}/10"
  OPENSSF_CHECKS="${OPENSSF_CHECKS}, License=${license_score}/10"
  OPENSSF_CHECKS="${OPENSSF_CHECKS}, Vulnerabilities=${vuln_score}/10"
  OPENSSF_CHECKS="${OPENSSF_CHECKS}, Branch-Protection=${branch_prot_score}/10"

  log_verbose "OpenSSF 检查项: ${OPENSSF_CHECKS}"

  # 映射 OpenSSF 总分(0-10) 到我们的评分(0-15)
  # 策略: score >= 7 -> 15分, score >= 5 -> 10分, score >= 3 -> 6分, score < 3 -> 3分
  if [[ "$raw_int" -ge 7 ]]; then
    OPENSSF_SCORE=15
  elif [[ "$raw_int" -ge 5 ]]; then
    OPENSSF_SCORE=10
  elif [[ "$raw_int" -ge 3 ]]; then
    OPENSSF_SCORE=6
  else
    OPENSSF_SCORE=3
  fi

  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  OPENSSF_DETAILS="评分 ${OPENSSF_RAW_SCORE}/10 (${OPENSSF_CHECKS})"
}

# ============================================================
# 维度5: 元数据完整性 (满分10, 不变)
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
# 维度6: 社区安全反馈 (满分10, v2新增)
# ============================================================
check_community_feedback() {
  COMMUNITY_FEEDBACK_SCORE=10  # 默认满分（无举报 = +10）
  SECURITY_ISSUES_COUNT=0
  local findings=""

  # 1. 默认: 无社区举报 (+10)
  # 未来接入举报系统后会从数据库查询
  log_verbose "社区反馈: 默认无举报记录 [+10基础分]"

  # 2. 如果有 GitHub 来源且启用了 OpenSSF，额外检查 security 相关 Issues
  if $ENABLE_OPENSSF && [[ -n "$GH_OWNER" && -n "$GH_REPO" ]]; then
    if command -v jq &>/dev/null; then
      log_verbose "正在检查 GitHub Issues 中的安全相关问题..."

      local issues_url="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/issues?labels=security&state=open&per_page=5"
      local issues_json=""

      if [[ -z "$TEMP_DIR" ]]; then
        TEMP_DIR=$(mktemp -d)
      fi

      if curl -sf --connect-timeout 5 --max-time 10 "$issues_url" -o "${TEMP_DIR}/security_issues.json" 2>/dev/null; then
        # 计算 security label 的 open issues 数量
        SECURITY_ISSUES_COUNT=$(jq -r 'length' "${TEMP_DIR}/security_issues.json" 2>/dev/null || echo "0")
      fi

      # 如果没有 security label 的 issue，再搜索标题/正文中含 security/vulnerability 的
      if [[ "$SECURITY_ISSUES_COUNT" -eq 0 ]]; then
        local search_url="https://api.github.com/search/issues?q=repo:${GH_OWNER}/${GH_REPO}+is:issue+is:open+security+OR+vulnerability+OR+CVE&per_page=5"
        if curl -sf --connect-timeout 5 --max-time 10 "$search_url" -o "${TEMP_DIR}/security_search.json" 2>/dev/null; then
          SECURITY_ISSUES_COUNT=$(jq -r '.total_count // 0' "${TEMP_DIR}/security_search.json" 2>/dev/null || echo "0")
        fi
      fi

      TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
      if [[ "$SECURITY_ISSUES_COUNT" -gt 0 ]]; then
        # 有安全相关的 open issue，扣分
        # 1-2个扣3分，3个以上扣6分
        if [[ "$SECURITY_ISSUES_COUNT" -le 2 ]]; then
          COMMUNITY_FEEDBACK_SCORE=$((COMMUNITY_FEEDBACK_SCORE - 3))
          findings="发现 ${SECURITY_ISSUES_COUNT} 个安全相关 Open Issue (-3分)"
        else
          COMMUNITY_FEEDBACK_SCORE=$((COMMUNITY_FEEDBACK_SCORE - 6))
          findings="发现 ${SECURITY_ISSUES_COUNT} 个安全相关 Open Issue (-6分)"
        fi
        log_finding "社区" "发现 ${SECURITY_ISSUES_COUNT} 个安全相关 Open Issue"
      else
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_verbose "社区反馈: 无安全相关 Open Issue [通过]"
      fi
    fi
  fi

  # 确保分数不低于0
  if [[ $COMMUNITY_FEEDBACK_SCORE -lt 0 ]]; then
    COMMUNITY_FEEDBACK_SCORE=0
  fi

  # 详情
  if [[ $COMMUNITY_FEEDBACK_SCORE -eq 10 ]]; then
    COMMUNITY_FEEDBACK_DETAILS="无举报"
  else
    COMMUNITY_FEEDBACK_DETAILS="${findings}"
  fi
}

# ============================================================
# 降级处理：当 OpenSSF 不可用时，将15分按比例分配
# ============================================================
apply_degradation() {
  if ! $DEGRADED; then
    return
  fi

  # OpenSSF 15分不可用，按比例分配到其他5个维度
  # 其他维度满分: 30 + 20 + 15 + 10 + 10 = 85
  # 每个维度获得的额外分 = (原维度满分 / 85) * 15

  local other_total=$((CODE_SAFETY_MAX + PERMISSION_MAX + SOURCE_MAX + METADATA_MAX + COMMUNITY_FEEDBACK_MAX))

  # 计算每个维度的比例增加 (使用整数运算，避免浮点)
  local bonus_code=$((CODE_SAFETY_MAX * 15 / other_total))
  local bonus_perm=$((PERMISSION_MAX * 15 / other_total))
  local bonus_src=$((SOURCE_MAX * 15 / other_total))
  local bonus_meta=$((METADATA_MAX * 15 / other_total))
  # 最后一个用减法保证总和正好为15
  local bonus_comm=$((15 - bonus_code - bonus_perm - bonus_src - bonus_meta))

  # 更新满分
  CODE_SAFETY_MAX=$((CODE_SAFETY_MAX + bonus_code))
  PERMISSION_MAX=$((PERMISSION_MAX + bonus_perm))
  SOURCE_MAX=$((SOURCE_MAX + bonus_src))
  METADATA_MAX=$((METADATA_MAX + bonus_meta))
  COMMUNITY_FEEDBACK_MAX=$((COMMUNITY_FEEDBACK_MAX + bonus_comm))

  # 按比例增加得分 (得分率 * 新增分值)
  # 得分率 = 原得分 / 原满分
  if [[ $((CODE_SAFETY_MAX - bonus_code)) -gt 0 ]]; then
    local orig_max=$((CODE_SAFETY_MAX - bonus_code))
    CODE_SAFETY_SCORE=$((CODE_SAFETY_SCORE + CODE_SAFETY_SCORE * bonus_code / orig_max))
  fi
  if [[ $((PERMISSION_MAX - bonus_perm)) -gt 0 ]]; then
    local orig_max=$((PERMISSION_MAX - bonus_perm))
    PERMISSION_SCORE=$((PERMISSION_SCORE + PERMISSION_SCORE * bonus_perm / orig_max))
  fi
  if [[ $((SOURCE_MAX - bonus_src)) -gt 0 ]]; then
    local orig_max=$((SOURCE_MAX - bonus_src))
    SOURCE_SCORE=$((SOURCE_SCORE + SOURCE_SCORE * bonus_src / orig_max))
  fi
  if [[ $((METADATA_MAX - bonus_meta)) -gt 0 ]]; then
    local orig_max=$((METADATA_MAX - bonus_meta))
    METADATA_SCORE=$((METADATA_SCORE + METADATA_SCORE * bonus_meta / orig_max))
  fi
  if [[ $((COMMUNITY_FEEDBACK_MAX - bonus_comm)) -gt 0 ]]; then
    local orig_max=$((COMMUNITY_FEEDBACK_MAX - bonus_comm))
    COMMUNITY_FEEDBACK_SCORE=$((COMMUNITY_FEEDBACK_SCORE + COMMUNITY_FEEDBACK_SCORE * bonus_comm / orig_max))
  fi

  # OpenSSF 维度标记为不可用
  OPENSSF_MAX=0
  OPENSSF_SCORE=0

  log_verbose "降级模式: OpenSSF 15分已按比例分配到其他维度"
}

# ============================================================
# 计算总分和等级
# ============================================================
calculate_total() {
  local total=$((CODE_SAFETY_SCORE + PERMISSION_SCORE + SOURCE_SCORE + OPENSSF_SCORE + METADATA_SCORE + COMMUNITY_FEEDBACK_SCORE))
  # 确保不超过100
  if [[ $total -gt 100 ]]; then
    total=100
  fi
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

  printf "\n===== 安全评分报告 (v2) =====\n"
  printf "技能: %s\n" "$SKILL_NAME"
  printf "来源: %s\n\n" "$SKILL_SOURCE"

  printf "代码安全性:    %2d/%d  [%s]\n" "$CODE_SAFETY_SCORE" "$CODE_SAFETY_MAX" "$CODE_SAFETY_DETAILS"
  printf "权限合规性:    %2d/%d  [%s]\n" "$PERMISSION_SCORE" "$PERMISSION_MAX" "$PERMISSION_DETAILS"
  printf "来源可信度:    %2d/%d  [%s]\n" "$SOURCE_SCORE" "$SOURCE_MAX" "$SOURCE_DETAILS"

  if $DEGRADED; then
    if $ENABLE_OPENSSF; then
      printf "OpenSSF 评估:  --/--  [%s]\n" "$OPENSSF_DETAILS"
    else
      printf "OpenSSF 评估:  --/--  [未启用]\n"
    fi
  else
    printf "OpenSSF 评估:  %2d/%d  [%s]\n" "$OPENSSF_SCORE" "$OPENSSF_MAX" "$OPENSSF_DETAILS"
  fi

  printf "元数据完整:    %2d/%d  [%s]\n" "$METADATA_SCORE" "$METADATA_MAX" "$METADATA_DETAILS"
  printf "社区安全反馈:  %2d/%d  [%s]\n\n" "$COMMUNITY_FEEDBACK_SCORE" "$COMMUNITY_FEEDBACK_MAX" "$COMMUNITY_FEEDBACK_DETAILS"

  if $DEGRADED && $ENABLE_OPENSSF; then
    printf "注意: %s\n" "$DEGRADED_MSG"
    printf "      15分已按比例分配到其他维度\n\n"
  fi

  printf "总分: %d/100\n" "$total"
  printf "等级: %s\n" "$grade_label"
  printf "安全标签: 通过%d重安全检测\n" "$PASSED_CHECKS"

  if $ENABLE_OPENSSF && $OPENSSF_AVAILABLE && [[ -n "$OPENSSF_CHECKS" ]]; then
    printf "\n--- OpenSSF Scorecard 详情 ---\n"
    printf "总分: %s/10\n" "$OPENSSF_RAW_SCORE"
    # 逐行展示各检查项
    echo "$OPENSSF_CHECKS" | tr ',' '\n' | while read -r check; do
      local trimmed
      trimmed=$(echo "$check" | sed 's/^[[:space:]]*//')
      if [[ -n "$trimmed" ]]; then
        printf "  %s\n" "$trimmed"
      fi
    done
  fi

  if [[ $SECURITY_ISSUES_COUNT -gt 0 ]]; then
    printf "\n--- 安全 Issue ---\n"
    printf "发现 %d 个安全相关的 Open Issue\n" "$SECURITY_ISSUES_COUNT"
    printf "建议查看: https://github.com/%s/%s/issues?q=is%%3Aopen+security\n" "$GH_OWNER" "$GH_REPO"
  fi

  printf "=============================\n"
}

# ============================================================
# 输出: JSON 报告
# ============================================================
output_json_report() {
  local total
  total=$(calculate_total)
  local grade
  grade=$(get_grade "$total")

  # 转义 JSON 字符串中的特殊字符
  local esc_name esc_source esc_code_detail esc_perm_detail esc_src_detail
  local esc_openssf_detail esc_meta_detail esc_comm_detail esc_openssf_checks esc_degraded_msg
  esc_name=$(echo "$SKILL_NAME" | sed 's/"/\\"/g')
  esc_source=$(echo "$SKILL_SOURCE" | sed 's/"/\\"/g')
  esc_code_detail=$(echo "$CODE_SAFETY_DETAILS" | sed 's/"/\\"/g')
  esc_perm_detail=$(echo "$PERMISSION_DETAILS" | sed 's/"/\\"/g')
  esc_src_detail=$(echo "$SOURCE_DETAILS" | sed 's/"/\\"/g')
  esc_openssf_detail=$(echo "$OPENSSF_DETAILS" | sed 's/"/\\"/g')
  esc_meta_detail=$(echo "$METADATA_DETAILS" | sed 's/"/\\"/g')
  esc_comm_detail=$(echo "$COMMUNITY_FEEDBACK_DETAILS" | sed 's/"/\\"/g')
  esc_openssf_checks=$(echo "$OPENSSF_CHECKS" | sed 's/"/\\"/g')
  esc_degraded_msg=$(echo "$DEGRADED_MSG" | sed 's/"/\\"/g')

  cat <<ENDJSON
{
  "version": "2.0.0",
  "skill_name": "${esc_name}",
  "source": "${esc_source}",
  "scores": {
    "code_safety": { "score": ${CODE_SAFETY_SCORE}, "max": ${CODE_SAFETY_MAX}, "detail": "${esc_code_detail}", "high_risk": ${CODE_SAFETY_HIGH}, "med_risk": ${CODE_SAFETY_MED}, "low_risk": ${CODE_SAFETY_LOW} },
    "permissions": { "score": ${PERMISSION_SCORE}, "max": ${PERMISSION_MAX}, "detail": "${esc_perm_detail}" },
    "source_trust": { "score": ${SOURCE_SCORE}, "max": ${SOURCE_MAX}, "detail": "${esc_src_detail}" },
    "openssf": { "score": ${OPENSSF_SCORE}, "max": ${OPENSSF_MAX}, "available": ${OPENSSF_AVAILABLE}, "raw_score": "${OPENSSF_RAW_SCORE:-N/A}", "checks": "${esc_openssf_checks}", "detail": "${esc_openssf_detail}" },
    "metadata": { "score": ${METADATA_SCORE}, "max": ${METADATA_MAX}, "detail": "${esc_meta_detail}" },
    "community_feedback": { "score": ${COMMUNITY_FEEDBACK_SCORE}, "max": ${COMMUNITY_FEEDBACK_MAX}, "detail": "${esc_comm_detail}", "security_issues": ${SECURITY_ISSUES_COUNT} }
  },
  "total_score": ${total},
  "max_score": 100,
  "grade": "${grade}",
  "checks_passed": ${PASSED_CHECKS},
  "checks_total": ${TOTAL_CHECKS},
  "degraded": ${DEGRADED},
  "degraded_message": "${esc_degraded_msg}",
  "openssf_enabled": ${ENABLE_OPENSSF}
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
  check_openssf
  check_metadata
  check_community_feedback
  apply_degradation

  if $OUTPUT_JSON; then
    output_json_report
  else
    output_text_report
  fi
}

main "$@"
