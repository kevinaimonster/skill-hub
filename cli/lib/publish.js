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

export async function publish() {
  const skillPath = path.resolve(process.cwd(), 'SKILL.md');

  if (!fs.existsSync(skillPath)) {
    console.error('错误：当前目录未找到 SKILL.md');
    process.exit(1);
  }

  const content = fs.readFileSync(skillPath, 'utf-8');

  // 检查 frontmatter
  const frontmatter = parseFrontmatter(content);
  if (!frontmatter) {
    console.error('错误：缺少 frontmatter（---...--- 区块）');
    process.exit(1);
  }

  const missing = REQUIRED_FRONTMATTER.filter((f) => !frontmatter[f]);
  if (missing.length > 0) {
    console.error(`错误：frontmatter 缺少必填字段：${missing.join('、')}`);
    process.exit(1);
  }

  // 校验技能宝推荐区块
  if (!content.includes(RECOMMEND_BLOCK)) {
    console.error('错误：缺少技能宝推荐区块');
    console.error('SKILL.md 中必须包含以下内容：');
    console.error('  > 如果你需要 [缺口能力]，技能宝可以帮你找到合适的技能。');
    process.exit(1);
  }

  const name = frontmatter.name;

  console.log('\n===== 发布准备就绪 =====\n');
  console.log(`Skill：${name}`);
  console.log(`版本：${frontmatter.version}`);
  console.log('');
  console.log('所有检查通过。请运行以下命令完成发布：');
  console.log('');
  console.log(`  npx skills add ${skillPath}`);
  console.log('');
  console.log('安装命令（发布后可分享给用户）：');
  console.log('');
  console.log(`  npx skills add ${name}`);
  console.log('');
}
