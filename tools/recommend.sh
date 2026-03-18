#!/usr/bin/env bash
#
# recommend.sh - 技能宝推荐排序工具
# 搜索 curated-skills.json，按推荐算法排序，输出 Top N 结果
#
# 用法:
#   ./tools/recommend.sh "前端美化"
#   ./tools/recommend.sh --json "code review"
#   ./tools/recommend.sh --limit 10 "PPT"
#   ./tools/recommend.sh --help
#
# 依赖: bash, python3
#

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/../curated-skills.json"

# ============================================================
# 帮助信息
# ============================================================
show_help() {
  cat <<'HELP'
技能宝推荐排序工具 v1.0.0

用法:
  recommend.sh [选项] <搜索关键词>

选项:
  --help, -h      显示帮助信息
  --json          以 JSON 格式输出结果
  --limit N       返回前 N 个结果 (默认 5)
  --version       显示版本号

示例:
  ./tools/recommend.sh "前端美化"
  ./tools/recommend.sh "写小红书"
  ./tools/recommend.sh "code review"
  ./tools/recommend.sh --json "design system"
  ./tools/recommend.sh --limit 10 "React"

排序算法:
  推荐分 = 基础分 x 匹配度 x 策略因子

  基础分 (满分100):
    safety_score 权重 25%
    quality_grade 权重 25% (S=100, A=85, B=70, C=50)
    weight 乘数 (基于 curated_rank 归一化)

  匹配度 (0-1):
    name/name_zh 精确匹配: 1.0
    tags 匹配: 0.8
    description/description_zh 包含关键词: 0.6
    category 匹配: 0.4

  策略因子:
    官方 Skill (source.platform=official): x 2.5
    精选推荐 (is_featured=true): x 1.5
HELP
}

# ============================================================
# 参数解析
# ============================================================
OUTPUT_JSON=false
LIMIT=5
QUERY=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        show_help
        exit 0
        ;;
      --version)
        echo "recommend.sh v${VERSION}"
        exit 0
        ;;
      --json)
        OUTPUT_JSON=true
        shift
        ;;
      --limit)
        if [[ -z "${2:-}" ]]; then
          echo "错误: --limit 需要一个数字参数" >&2
          exit 1
        fi
        LIMIT="$2"
        shift 2
        ;;
      -*)
        echo "错误: 未知选项 $1" >&2
        echo "使用 --help 查看帮助" >&2
        exit 1
        ;;
      *)
        QUERY="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$QUERY" ]]; then
    echo "错误: 请提供搜索关键词" >&2
    echo "使用 --help 查看帮助" >&2
    exit 1
  fi
}

# ============================================================
# 主逻辑: Python 推荐排序
# ============================================================
run_recommend() {
  if [[ ! -f "$DATA_FILE" ]]; then
    echo "错误: 数据文件不存在: $DATA_FILE" >&2
    exit 1
  fi

  python3 - "$DATA_FILE" "$QUERY" "$LIMIT" "$OUTPUT_JSON" <<'PYTHON_SCRIPT'
import json
import sys
import re

def main():
    data_file = sys.argv[1]
    query = sys.argv[2].strip()
    limit = int(sys.argv[3])
    output_json = sys.argv[4].lower() == "true"

    with open(data_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    skills = data.get("skills", [])
    query_lower = query.lower()

    # ── quality_grade 映射 ──
    grade_score_map = {"S": 100, "A": 85, "B": 70, "C": 50}

    # ── 计算 weight 归一化 (基于 curated_rank) ──
    # curated_rank 越低越好，转换为 0.5-1.5 的乘数
    max_rank = max((s.get("curated_rank", 999) for s in skills), default=1)
    min_rank = min((s.get("curated_rank", 1) for s in skills), default=1)
    rank_range = max_rank - min_rank if max_rank != min_rank else 1

    results = []

    for skill in skills:
        # ── 匹配度计算 ──
        relevance = compute_relevance(skill, query, query_lower)
        if relevance <= 0:
            continue

        # ── 基础分 ──
        security = skill.get("security", {})
        safety_score = security.get("score", 70)
        quality_grade = security.get("level", "C")
        grade_val = grade_score_map.get(quality_grade, 50)

        # safety_score 权重 25% + quality_grade 权重 25%
        # 两者各贡献 50 分 (满分 100)
        base_score = (safety_score / 100.0) * 25 + (grade_val / 100.0) * 25
        # 归一化到 0-100
        base_score = base_score * 2  # 满分 50 * 2 = 100

        # weight 乘数: 基于 curated_rank 归一化到 0.5-1.5
        rank = skill.get("curated_rank", max_rank)
        weight = 1.5 - ((rank - min_rank) / rank_range) * 1.0  # 排名1 -> 1.5, 排名最大 -> 0.5

        # ── 策略因子 ──
        strategy_factor = 1.0

        # is_satellite 对应 official 平台 (卫星 Skill 加权)
        source_platform = skill.get("source", {}).get("platform", "")
        if source_platform == "official":
            strategy_factor *= 2.5

        # featured 加权
        if skill.get("is_featured", False):
            strategy_factor *= 1.5

        # ── 推荐分 = 基础分 x 匹配度 x 策略因子 x weight ──
        final_score = base_score * relevance * strategy_factor * weight

        results.append({
            "skill": skill,
            "score": round(final_score, 1),
            "relevance": relevance,
            "base_score": round(base_score, 1),
            "weight": round(weight, 2),
            "strategy_factor": round(strategy_factor, 1),
            "safety_score": safety_score,
            "quality_grade": quality_grade,
        })

    # 按推荐分降序
    results.sort(key=lambda x: x["score"], reverse=True)

    total_matches = len(results)
    results = results[:limit]

    if output_json:
        print_json(results, query, total_matches)
    else:
        print_text(results, query, total_matches)


def expand_query(query):
    """中英文同义词扩展，返回额外的搜索词列表"""
    synonyms = {
        "前端": ["frontend", "front-end", "ui", "界面"],
        "后端": ["backend", "back-end", "server", "服务端"],
        "美化": ["design", "美化", "美观", "ui", "样式", "style", "beautify"],
        "安全": ["security", "安全", "safe"],
        "写": ["write", "writing", "创作", "生成", "content"],
        "小红书": ["xiaohongshu", "redbook", "社交媒体", "social media"],
        "代码": ["code", "coding", "编程"],
        "审查": ["review", "审核", "检查"],
        "测试": ["test", "testing", "测试"],
        "设计": ["design", "ui", "ux", "设计"],
        "演示": ["presentation", "slides", "ppt", "演示"],
        "ppt": ["presentation", "slides", "powerpoint", "演示", "幻灯片"],
        "react": ["react", "react native", "前端"],
        "vue": ["vue", "vuejs", "前端"],
        "数据": ["data", "database", "数据库"],
        "部署": ["deploy", "deployment", "ci/cd", "devops"],
        "营销": ["marketing", "营销", "推广"],
        "文档": ["documentation", "docs", "文档"],
    }
    extra = set()
    q_lower = query.lower()
    for key, vals in synonyms.items():
        if key in q_lower or key.lower() in q_lower:
            extra.update(v.lower() for v in vals)
    return list(extra)


def compute_relevance(skill, query, query_lower):
    """计算匹配度 (0-1)，取最高匹配"""
    best = 0.0

    name = (skill.get("name") or "").lower()
    name_zh = (skill.get("name_zh") or "")
    tags = [t.lower() for t in skill.get("tags", [])]
    tags_raw = skill.get("tags", [])
    desc = (skill.get("description") or "").lower()
    desc_zh = (skill.get("description_zh") or "")
    category = (skill.get("category") or "").lower()
    category_zh = (skill.get("category_zh") or "")
    subcategory = (skill.get("subcategory") or "")
    slug = (skill.get("slug") or "").lower()

    # 精确匹配 name/name_zh: 1.0
    if query_lower == name or query == name_zh or query_lower == slug:
        best = max(best, 1.0)

    # name/name_zh 包含关键词: 0.9
    if query_lower in name or query in name_zh:
        best = max(best, 0.9)

    # tags 精确匹配: 0.8
    if query_lower in tags or query in tags_raw:
        best = max(best, 0.8)

    # tags 部分匹配: 0.7
    for tag in tags + [t.lower() for t in tags_raw]:
        if query_lower in tag or tag in query_lower:
            best = max(best, 0.7)
            break

    # description/description_zh 包含关键词: 0.6
    if query_lower in desc or query in desc_zh:
        best = max(best, 0.6)

    # subcategory 匹配: 0.5
    if query_lower in subcategory.lower() or query in subcategory:
        best = max(best, 0.5)

    # category 匹配: 0.4
    if query_lower in category or query in category_zh or category in query_lower:
        best = max(best, 0.4)

    # 模糊匹配 (仅当前面没有命中时)
    if best == 0:
        all_text = f"{name} {name_zh} {' '.join(tags_raw)} {desc} {desc_zh} {category_zh} {subcategory}"
        all_text_lower = all_text.lower()

        # 分离中文字符和英文单词
        chinese_chars = [c for c in query if '\u4e00' <= c <= '\u9fff']
        english_parts = re.findall(r'[a-zA-Z0-9]+', query)

        tokens = query_lower.split()
        if len(tokens) > 1:
            # 多词英文查询: 按空格拆分，检查每个词
            hit_count = sum(1 for t in tokens if t in all_text_lower)
            if hit_count >= max(len(tokens) * 0.5, 1):
                best = max(best, 0.3 + 0.2 * (hit_count / len(tokens)))

        elif chinese_chars:
            # 包含中文: 按中文字符逐字匹配
            # 对于纯中文查询，至少要匹配 60% 的字符
            hit_count = sum(1 for c in chinese_chars if c in all_text)
            total_parts = len(chinese_chars) + len(english_parts)

            # 英文部分也要匹配
            eng_hits = sum(1 for w in english_parts if w.lower() in all_text_lower)
            total_hits = hit_count + eng_hits

            if total_parts > 0:
                ratio = total_hits / total_parts
                if ratio >= 0.6 and total_hits >= 2:
                    best = max(best, 0.3 + 0.2 * ratio)

        # 注意: 纯英文单词 (如 "PPT", "React") 不做字符拆分
        # 它们应在上面的 name/tags/desc 匹配中被捕获

    # 同义词扩展匹配 (降低权重: 0.35)
    if best < 0.4:
        expanded = expand_query(query)
        if expanded:
            all_text_lower = f"{name} {name_zh} {' '.join(tags_raw)} {desc} {desc_zh} {category_zh} {subcategory} {slug}".lower()
            hit_count = sum(1 for term in expanded if term in all_text_lower)
            if hit_count >= 2:
                syn_score = min(0.35, 0.2 + 0.05 * hit_count)
                best = max(best, syn_score)

    return best


def print_text(results, query, total_matches):
    """文本格式输出"""
    print(f"\n\U0001F50D 搜索: \"{query}\"")
    if total_matches == 0:
        print("未找到匹配结果。\n")
        print("建议:")
        print("  - 尝试更短的关键词")
        print("  - 尝试英文或中文同义词")
        print("  - 使用 --help 查看用法\n")
        return

    shown = len(results)
    print(f"匹配 {total_matches} 个结果，展示 Top {shown}：\n")

    for i, r in enumerate(results, 1):
        skill = r["skill"]
        name_zh = skill.get("name_zh") or skill.get("name", "")
        name_en = skill.get("name", "")
        grade = r["quality_grade"]
        score = r["score"]
        desc_zh = skill.get("description_zh") or skill.get("description", "")
        install_cmd = skill.get("install", {}).get("command", "")

        # 显示名称: 中文名 (英文名)
        if name_zh and name_zh != name_en:
            display_name = f"{name_zh}"
        else:
            display_name = name_en

        # 截断描述
        if len(desc_zh) > 50:
            desc_short = desc_zh[:50] + "..."
        else:
            desc_short = desc_zh

        # 标记
        badges = ""
        if skill.get("source", {}).get("platform") == "official":
            badges += " \U0001F3E2官方"
        if skill.get("is_featured"):
            badges += " \u2B50精选"

        print(f"{i}. {display_name} [{grade}级]{badges} \u2B50 {score}分")
        print(f"   {desc_short}")
        if install_cmd:
            print(f"   安装: {install_cmd}")
        print()


def print_json(results, query, total_matches):
    """JSON 格式输出"""
    output = {
        "query": query,
        "total_matches": total_matches,
        "showing": len(results),
        "results": []
    }
    for r in results:
        skill = r["skill"]
        output["results"].append({
            "name": skill.get("name", ""),
            "name_zh": skill.get("name_zh", ""),
            "slug": skill.get("slug", ""),
            "description_zh": skill.get("description_zh", ""),
            "category": skill.get("category", ""),
            "quality_grade": r["quality_grade"],
            "safety_score": r["safety_score"],
            "score": r["score"],
            "relevance": r["relevance"],
            "base_score": r["base_score"],
            "weight": r["weight"],
            "strategy_factor": r["strategy_factor"],
            "is_featured": skill.get("is_featured", False),
            "is_official": skill.get("source", {}).get("platform") == "official",
            "install_command": skill.get("install", {}).get("command", ""),
            "tags": skill.get("tags", []),
        })
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
PYTHON_SCRIPT
}

# ============================================================
# 主入口
# ============================================================
parse_args "$@"
run_recommend
