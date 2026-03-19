# 技能宝 SkillHub

> 中文社区最大的 AI 技能搜索、安装与智能推荐平台

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-50+-green.svg)](https://github.com/kevinaimonster/skill-hub/tree/main/skills)
[![Curated](https://img.shields.io/badge/Curated-5000+-purple.svg)](https://github.com/kevinaimonster/skill-hub/tree/main/registry)
[![Agents](https://img.shields.io/badge/Agents-42+-orange.svg)](#支持的-agent-平台)

**一条命令，为你的 AI 助手装上 50+ 中文技能。** 支持 Claude Code、Cursor、Windsurf、Gemini CLI 等 42 个 Agent 平台。

## 快速开始

```bash
# 安装全部 50 个技能（推荐）
npx skills add kevinaimonster/skill-hub --full-depth --skill '*' -g -y

# 只安装技能宝（搜索+推荐引擎）
npx skills add kevinaimonster/skill-hub -g -y
```

安装后，对你的 AI 助手说：

- 「帮我写一篇小红书」
- 「做个 PPT」
- 「帮我 review 代码」
- 「帮我找一个做 SEO 的技能」

## 50 个精选技能

### 🇨🇳 中国特色原创（20个）

| 技能 | 说明 | 安装 |
|------|------|------|
| **小红书** | 种草笔记、好物推荐、探店测评 | `npx skills add kevinaimonster/skill-hub@xiaohongshu -g -y` |
| **抖音脚本** | 口播、带货、剧情、分镜、Vlog | `npx skills add kevinaimonster/skill-hub@douyin-script -g -y` |
| **公众号** | 微信公众号文章、5种风格 | `npx skills add kevinaimonster/skill-hub@wechat-mp -g -y` |
| **知乎回答** | 知乎风格长文、逻辑严密 | `npx skills add kevinaimonster/skill-hub@zhihu-writer -g -y` |
| **B站文案** | 年轻化语言、弹幕友好 | `npx skills add kevinaimonster/skill-hub@bilibili-script -g -y` |
| **微博热搜** | 热搜文案、话题分析 | `npx skills add kevinaimonster/skill-hub@weibo-hot -g -y` |
| **淘宝详情** | 商品详情页、卖点提炼 | `npx skills add kevinaimonster/skill-hub@taobao-listing -g -y` |
| **微信小程序** | WXML/WXSS/JS 代码生成 | `npx skills add kevinaimonster/skill-hub@wechat-mini -g -y` |
| **中文简历** | 简历、求职信、自我介绍 | `npx skills add kevinaimonster/skill-hub@resume-zh -g -y` |
| **会议纪要** | 会议整理、待办提取 | `npx skills add kevinaimonster/skill-hub@meeting-notes -g -y` |
| **周报生成器** | 从 git log 生成周报 | `npx skills add kevinaimonster/skill-hub@weekly-report -g -y` |
| **面试官** | 模拟技术面试、评分 | `npx skills add kevinaimonster/skill-hub@interviewer -g -y` |
| **合同审查** | 风险条款、中国法律 | `npx skills add kevinaimonster/skill-hub@contract-review -g -y` |
| **高考作文** | 议论文、记叙文 | `npx skills add kevinaimonster/skill-hub@gaokao-essay -g -y` |
| **播客脚本** | 单口、对谈、访谈 | `npx skills add kevinaimonster/skill-hub@podcast-script -g -y` |
| **论文降重** | 同义替换、句式改写 | `npx skills add kevinaimonster/skill-hub@paper-reducer -g -y` |
| **取名大师** | 品牌/产品/公司起名 | `npx skills add kevinaimonster/skill-hub@naming-master -g -y` |
| **钉钉文档** | 钉钉 OKR、审批流程 | `npx skills add kevinaimonster/skill-hub@dingding-doc -g -y` |
| **小红书数据** | 账号分析、爆文规律 | `npx skills add kevinaimonster/skill-hub@redbook-analytics -g -y` |
| **去AI味** | 让 AI 文案像人写的 | `npx skills add kevinaimonster/skill-hub@chinese-copyfix -g -y` |

### 🛠 开发工具

| 技能 | 说明 | 安装 |
|------|------|------|
| **代码审查** | 结构化审查报告 | `npx skills add kevinaimonster/skill-hub@code-review -g -y` |
| **安全审计** | OWASP Top 10 检查 | `npx skills add kevinaimonster/skill-hub@security-audit -g -y` |
| **React宝典** | React 19+ / Next.js 15+ | `npx skills add kevinaimonster/skill-hub@react-best-practices -g -y` |
| **测试驱动** | TDD 红绿重构 | `npx skills add kevinaimonster/skill-hub@tdd -g -y` |
| **快速调试** | 结构化调试流程 | `npx skills add kevinaimonster/skill-hub@debugger -g -y` |
| **接口构建** | REST/GraphQL API | `npx skills add kevinaimonster/skill-hub@api-builder -g -y` |
| **Git大师** | 分支策略、合并冲突 | `npx skills add kevinaimonster/skill-hub@git-master -g -y` |
| **SQL助手** | MySQL/PostgreSQL/SQLite | `npx skills add kevinaimonster/skill-hub@sql-helper -g -y` |
| **正则大师** | 正则编写、解释、调试 | `npx skills add kevinaimonster/skill-hub@regex-helper -g -y` |
| **TypeScript** | 严格类型、泛型、类型体操 | `npx skills add kevinaimonster/skill-hub@typescript-strict -g -y` |
| **AWS助手** | S3/EC2/Lambda/CloudFormation | `npx skills add kevinaimonster/skill-hub@aws-helper -g -y` |
| **浏览器插件** | Chrome Extension MV3 | `npx skills add kevinaimonster/skill-hub@chrome-extension -g -y` |
| **系统设计** | 面试级架构设计 | `npx skills add kevinaimonster/skill-hub@system-design -g -y` |
| **性能调优** | Core Web Vitals / Lighthouse | `npx skills add kevinaimonster/skill-hub@performance-tuner -g -y` |
| **Docker部署** | Dockerfile / docker-compose | `npx skills add kevinaimonster/skill-hub@docker-deploy -g -y` |
| **CI/CD** | GitHub Actions / GitLab CI | `npx skills add kevinaimonster/skill-hub@ci-cd -g -y` |

### 🎨 设计 & 效率 & 其他

| 技能 | 说明 | 安装 |
|------|------|------|
| **前端美化** | UI/UX 增强、反 AI 审美 | `npx skills add kevinaimonster/skill-hub@frontend-design -g -y` |
| **设计大师** | 完整设计系统 Token | `npx skills add kevinaimonster/skill-hub@web-design -g -y` |
| **着陆页** | 高转化率 Landing Page | `npx skills add kevinaimonster/skill-hub@landing-page -g -y` |
| **头脑风暴** | 6种思维框架 | `npx skills add kevinaimonster/skill-hub@brainstorming -g -y` |
| **PPT大师** | Reveal.js 演示文稿 | `npx skills add kevinaimonster/skill-hub@ppt-master -g -y` |
| **项目规划** | 需求分析到排期 | `npx skills add kevinaimonster/skill-hub@project-planner -g -y` |
| **SEO大师** | 技术SEO / Core Web Vitals | `npx skills add kevinaimonster/skill-hub@seo-master -g -y` |
| **文案大师** | 广告/着陆页/邮件文案 | `npx skills add kevinaimonster/skill-hub@copywriter -g -y` |
| **数据分析** | CSV/JSON 分析、趋势 | `npx skills add kevinaimonster/skill-hub@data-analyst -g -y` |
| **文档大师** | README/API文档/Changelog | `npx skills add kevinaimonster/skill-hub@markdown-doc -g -y` |
| **教程编写** | 技术教程、学习路线 | `npx skills add kevinaimonster/skill-hub@tutorial-writer -g -y` |
| **视频脚本** | 通用视频脚本、分镜表 | `npx skills add kevinaimonster/skill-hub@video-editor -g -y` |
| **邮件营销** | Newsletter / 邮件序列 | `npx skills add kevinaimonster/skill-hub@email-marketing -g -y` |
| **Slack集成** | Slack Bot / Webhook | `npx skills add kevinaimonster/skill-hub@slack-bot -g -y` |

## 为什么选技能宝？

| 对比 | skills.sh | 腾讯 SkillHub | **技能宝** |
|------|-----------|--------------|------------|
| 中文 | 无 | 部分 | **100% 中文优先** |
| 安全 | 建设中 | 不透明 | **12重安全检测** |
| 分发 | 中心化网页 | 中心化网页 | **去中心化 Agent 直装** |
| 开发者 | 开放 | 纯搬运 | **有 CLI + 模板** |
| 价格 | 免费 | 免费 | **免费 + 开源** |

## 精选库

技能宝内置 **5,000+ 精选 Skill 索引**，覆盖 13 个分类。搜什么都能找到。

## 支持的 Agent 平台

Claude Code, Cursor, Windsurf, Gemini CLI, GitHub Copilot, Cline, Codex, Roo Code, Augment, OpenClaw, Kilo Code, Qwen Code, Trae, Goose, Continue, OpenHands, Junie, 等 42+ 个平台。

## 安全

每个技能经过 12 重安全检测：
- 禁止管道执行（curl | bash）
- 禁止凭证外泄
- 禁止关闭安全机制
- 禁止混淆代码
- 禁止改系统文件
- 禁止暗中收集数据
- 禁止 AI 越狱
- OpenSSF Scorecard 集成
- 社区举报机制

## 开发者

用 CLI 快速创建你自己的 Skill：

```bash
npx @skillhub/cli init my-skill
npx @skillhub/cli dev
npx @skillhub/cli publish
```

## License

MIT
