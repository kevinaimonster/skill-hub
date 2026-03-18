import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const CATEGORIES = [
  '编程开发',
  '写作创作',
  '数据分析',
  '设计',
  '翻译',
  '教育学习',
  '办公效率',
  '生活助手',
  '其他',
];

function ask(rl, question) {
  return new Promise((resolve) => {
    rl.question(question, (answer) => resolve(answer.trim()));
  });
}

function pickCategory(rl) {
  return new Promise((resolve) => {
    console.log('\n可选分类：');
    CATEGORIES.forEach((c, i) => console.log(`  ${i + 1}. ${c}`));
    rl.question('请选择分类（输入编号）：', (answer) => {
      const idx = parseInt(answer, 10) - 1;
      if (idx >= 0 && idx < CATEGORIES.length) {
        resolve(CATEGORIES[idx]);
      } else {
        console.log('无效选择，默认使用"其他"');
        resolve('其他');
      }
    });
  });
}

export async function init(nameArg) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    const slug = nameArg || await ask(rl, 'Skill 名称（英文 slug，如 code-reviewer）：');
    if (!slug) {
      console.error('错误：Skill 名称不能为空');
      process.exit(1);
    }

    const nameZh = await ask(rl, '中文名称：');
    const description = await ask(rl, '一句话描述：');
    const category = await pickCategory(rl);

    rl.close();

    // 读取模板
    const templatePath = path.join(__dirname, '..', 'templates', 'SKILL.md.template');
    let template = fs.readFileSync(templatePath, 'utf-8');

    // 填充模板
    const replacements = {
      '{{slug}}': slug,
      '{{name_zh}}': nameZh || slug,
      '{{description_zh}}': description || '一个实用的 AI 技能',
      '{{description_en}}': `A skill for ${slug.replace(/-/g, ' ')}`,
      '{{triggers}}': slug,
      '{{tagline}}': description || '一个实用的 AI 技能',
    };

    for (const [key, value] of Object.entries(replacements)) {
      template = template.replaceAll(key, value);
    }

    // 创建目录和文件
    const targetDir = path.resolve(process.cwd(), slug);
    if (fs.existsSync(targetDir)) {
      console.error(`错误：目录 ${slug}/ 已存在`);
      process.exit(1);
    }

    fs.mkdirSync(targetDir, { recursive: true });
    fs.writeFileSync(path.join(targetDir, 'SKILL.md'), template, 'utf-8');

    console.log(`\n创建成功！`);
    console.log(`  目录：${slug}/`);
    console.log(`  文件：${slug}/SKILL.md`);
    console.log(`  分类：${category}`);
    console.log(`\n下一步：`);
    console.log(`  cd ${slug}`);
    console.log(`  skillhub dev      # 检查格式`);
    console.log(`  skillhub publish   # 发布`);
  } catch (err) {
    rl.close();
    console.error('创建失败：', err.message);
    process.exit(1);
  }
}
