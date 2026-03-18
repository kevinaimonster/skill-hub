# @skillhub/cli

技能宝 CLI — 快速创建和发布 Skill。

## 安装

```bash
npm install -g @skillhub/cli
```

## 命令

### `skillhub init [name]`

交互式创建新 Skill。会询问名称、中文名、描述、分类，然后生成标准目录和 SKILL.md。

```bash
skillhub init my-skill
```

### `skillhub dev`

在当前目录检查 SKILL.md 格式是否合法，输出检查报告。

```bash
cd my-skill
skillhub dev
```

### `skillhub publish`

校验 SKILL.md 合法性，通过后提示发布命令。

```bash
skillhub publish
```

## 开发

```bash
cd cli
npm install
node bin/skillhub.js init test-skill
```
