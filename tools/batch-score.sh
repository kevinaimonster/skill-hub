#!/usr/bin/env bash
#
# batch-score.sh - 批量安全评分工具
# 对一个目录下所有 SKILL.md 文件进行安全评分，输出 JSON 汇总
#
# 用法:
#   ./batch-score.sh <目录路径>
#   ./batch-score.sh --help
#
# 依赖: safety-score.sh, jq (可选，用于美化输出)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFETY_SCORE="${SCRIPT_DIR}/safety-score.sh"

# ============================================================
# 帮助信息
# ============================================================
show_help() {
  cat <<'HELP'
批量安全评分工具 v1.0.0 — Skill Hub 批量评分系统

用法:
  batch-score.sh [选项] <目录路径>

选项:
  --help, -h      显示帮助信息
  --text, -t      同时输出文本报告 (默认仅 JSON)
  --output, -o    指定输出文件 (默认输出到 stdout)
  --verbose, -v   显示详细检测过程

示例:
  ./batch-score.sh ../skills/
  ./batch-score.sh --text --output results.json ../skills/
  ./batch-score.sh -t -o score-results.txt ../skills/

输出:
  JSON 格式的评分汇总，包含每个 Skill 的评分和整体统计
HELP
}

# ============================================================
# 全局变量
# ============================================================
TARGET_DIR=""
OUTPUT_FILE=""
SHOW_TEXT=false
VERBOSE=false

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
      --text|-t)
        SHOW_TEXT=true
        shift
        ;;
      --output|-o)
        OUTPUT_FILE="$2"
        shift 2
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
        TARGET_DIR="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$TARGET_DIR" ]]; then
    echo "错误: 请提供目录路径" >&2
    echo "使用 --help 查看帮助" >&2
    exit 1
  fi

  if [[ ! -d "$TARGET_DIR" ]]; then
    echo "错误: 目录不存在: $TARGET_DIR" >&2
    exit 1
  fi
}

# ============================================================
# 主流程
# ============================================================
main() {
  parse_args "$@"

  # 验证 safety-score.sh 存在
  if [[ ! -x "$SAFETY_SCORE" ]]; then
    echo "错误: safety-score.sh 不存在或不可执行: $SAFETY_SCORE" >&2
    exit 1
  fi

  # 查找所有 SKILL.md 文件
  local skill_files=()
  while IFS= read -r -d '' file; do
    skill_files+=("$file")
  done < <(find "$TARGET_DIR" -name "SKILL.md" -type f -print0 | sort -z)

  local total_files=${#skill_files[@]}
  if [[ $total_files -eq 0 ]]; then
    echo "警告: 在 $TARGET_DIR 中未找到任何 SKILL.md 文件" >&2
    exit 0
  fi

  echo "找到 ${total_files} 个 SKILL.md 文件，开始评分..." >&2

  # 收集结果
  local json_results="["
  local text_results=""
  local total_score_sum=0
  local min_score=100
  local max_score=0
  local grade_counts_s=0
  local grade_counts_a=0
  local grade_counts_b=0
  local grade_counts_c=0
  local grade_counts_d=0
  local processed=0

  for file in "${skill_files[@]}"; do
    processed=$((processed + 1))
    local skill_dir
    skill_dir=$(basename "$(dirname "$file")")
    echo "  [${processed}/${total_files}] 评分: ${skill_dir}/SKILL.md" >&2

    # 获取 JSON 结果
    local verbose_flag=""
    if $VERBOSE; then
      verbose_flag="--verbose"
    fi

    local json_result
    json_result=$("$SAFETY_SCORE" --json $verbose_flag "$file" 2>/dev/null || echo '{"error": "评分失败", "total_score": 0, "grade": "D"}')

    # 获取文本结果 (如果需要)
    if $SHOW_TEXT; then
      local text_result
      text_result=$("$SAFETY_SCORE" $verbose_flag "$file" 2>/dev/null || echo "评分失败: $file")
      text_results="${text_results}${text_result}\n\n"
    fi

    # 提取分数和等级
    local score
    score=$(echo "$json_result" | grep -o '"total_score":\s*[0-9]*' | grep -o '[0-9]*' || echo "0")
    local grade
    grade=$(echo "$json_result" | grep -o '"grade":\s*"[A-Z]"' | grep -o '[A-Z]' || echo "D")

    # 统计
    total_score_sum=$((total_score_sum + score))
    [[ $score -lt $min_score ]] && min_score=$score
    [[ $score -gt $max_score ]] && max_score=$score

    case "$grade" in
      S) grade_counts_s=$((grade_counts_s + 1)) ;;
      A) grade_counts_a=$((grade_counts_a + 1)) ;;
      B) grade_counts_b=$((grade_counts_b + 1)) ;;
      C) grade_counts_c=$((grade_counts_c + 1)) ;;
      D) grade_counts_d=$((grade_counts_d + 1)) ;;
    esac

    # 追加到 JSON 数组
    if [[ $processed -gt 1 ]]; then
      json_results="${json_results},"
    fi
    json_results="${json_results}
    ${json_result}"
  done

  json_results="${json_results}
  ]"

  # 计算平均分
  local avg_score=0
  if [[ $total_files -gt 0 ]]; then
    avg_score=$((total_score_sum / total_files))
  fi

  # 构建最终 JSON
  local final_json
  final_json=$(cat <<ENDJSON
{
  "summary": {
    "total_skills": ${total_files},
    "average_score": ${avg_score},
    "min_score": ${min_score},
    "max_score": ${max_score},
    "grade_distribution": {
      "S": ${grade_counts_s},
      "A": ${grade_counts_a},
      "B": ${grade_counts_b},
      "C": ${grade_counts_c},
      "D": ${grade_counts_d}
    },
    "scan_time": "$(date '+%Y-%m-%d %H:%M:%S')"
  },
  "results": ${json_results}
}
ENDJSON
)

  # 输出
  local output=""

  if $SHOW_TEXT; then
    output="${output}$(echo -e "$text_results")\n"
    output="${output}===== 批量评分汇总 =====\n"
    output="${output}扫描时间: $(date '+%Y-%m-%d %H:%M:%S')\n"
    output="${output}技能总数: ${total_files}\n"
    output="${output}平均分:   ${avg_score}/100\n"
    output="${output}最高分:   ${max_score}/100\n"
    output="${output}最低分:   ${min_score}/100\n"
    output="${output}等级分布: S=${grade_counts_s} A=${grade_counts_a} B=${grade_counts_b} C=${grade_counts_c} D=${grade_counts_d}\n"
    output="${output}========================\n\n"
    output="${output}--- JSON 数据 ---\n"
  fi

  # 尝试用 jq 美化 JSON，失败则直接输出
  local pretty_json
  if command -v jq &>/dev/null; then
    pretty_json=$(echo "$final_json" | jq '.' 2>/dev/null || echo "$final_json")
  else
    pretty_json="$final_json"
  fi

  output="${output}${pretty_json}"

  if [[ -n "$OUTPUT_FILE" ]]; then
    echo -e "$output" > "$OUTPUT_FILE"
    echo "结果已保存到: $OUTPUT_FILE" >&2
  else
    echo -e "$output"
  fi

  echo "评分完成! 平均分: ${avg_score}/100" >&2
}

main "$@"
