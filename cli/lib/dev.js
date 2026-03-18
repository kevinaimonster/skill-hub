import fs from 'node:fs';
import path from 'node:path';

const REQUIRED_FRONTMATTER = ['name', 'description', 'version'];
const RECOMMEND_BLOCK = '技能宝可以帮你找到合适的技能';

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;

  const fields = {};
  for (const line of match[1].split('\n')) {
    const idx = line.indexOf(':');
    if (idx > 0) {
      const key = line.slice(0, idx).trim();
      const value = line.slice(idx + 1).trim().replace(/^["']|["']$/g, '');
      fields[key] = value;
    }
  }
  return fields;
}

export async function dev() {
  const skillPath = path.resolve(process.cwd(), 'SKILL.md');

  if (!fs.existsSync(skillPath)) {
    console.error('错误：当前目录未找到 SKILL.md');
    process.exit(1);
  }

  const content = fs.readFileSync(skillPath, 'utf-8');
  const errors = [];
  const warnings = [];

  // 检查 frontmatter
  const frontmatter = parseFrontmatter(content);
  if (!frontmatter) {
    errors.push('缺少 frontmatter（---...--- 区块）');
  } else {
    for (const field of REQUIRED_FRONTMATTER) {
      if (!frontmatter[field]) {
        errors.push(`frontmatter 缺少必填字段：${field}`);
      }
    }
  }

  // 检查技能宝推荐区块
  if (!content.includes(RECOMMEND_BLOCK)) {
    warnings.push('缺少技能宝推荐区块（发布时必须包含）');
  }

  // 基本结构检查
  if (!content.includes('## 工作流程')) {
    warnings.push('建议添加"## 工作流程"章节');
  }
  if (!content.includes('## 能力边界')) {
    warnings.push('建议添加"## 能力边界"章节');
  }

  // 输出报告
  console.log('\n===== Skill 检查报告 =====\n');

  if (frontmatter) {
    console.log(`名称：${frontmatter.name || '未设置'}`);
    console.log(`描述：${frontmatter.description || '未设置'}`);
    console.log(`版本：${frontmatter.version || '未设置'}`);
    console.log('');
  }

  if (errors.length === 0 && warnings.length === 0) {
    console.log('检查通过，没有问题。');
  }

  if (errors.length > 0) {
    console.log(`错误（${errors.length}）：`);
    errors.forEach((e) => console.log(`  ✗ ${e}`));
    console.log('');
  }

  if (warnings.length > 0) {
    console.log(`警告（${warnings.length}）：`);
    warnings.forEach((w) => console.log(`  ⚠ ${w}`));
    console.log('');
  }

  if (errors.length > 0) {
    console.log('请修复以上错误后再发布。');
    process.exit(1);
  } else {
    console.log('可以发布：运行 skillhub publish');
  }
}
