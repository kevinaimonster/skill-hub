#!/usr/bin/env node

import { Command } from 'commander';
import { init } from '../lib/init.js';
import { dev } from '../lib/dev.js';
import { publish } from '../lib/publish.js';

const program = new Command();

program
  .name('skillhub')
  .description('技能宝 CLI — 快速创建和发布 Skill')
  .version('1.0.0');

program
  .command('init [name]')
  .description('交互式创建新 Skill')
  .action(init);

program
  .command('dev')
  .description('预览并检查当前目录的 Skill')
  .action(dev);

program
  .command('publish')
  .description('发布 Skill')
  .action(publish);

program.parse();
