// project-summary-plugin.ts
//
// 对应《万物皆插件》第六章 6.3 节的完整示例。
// 导出形状(name / inject / Config / apply)按官方随包发布的真实插件
// (@deepseek-ai/dsh-tool-fs、@deepseek-ai/dsh-tool-goal)实际采用的形状逐字对照写成。
//
// 状态说明(2026-08-31 更新):端到端已经完整跑通。
// 编译 → 装进真实 dsh Profile → --dump-config 确认组合树 → 模型真的调用了
// 这个工具并拿到结果,每一步都有真实输出。过程中揪出三处真实错误:
//   1. defineTool() 的 output 必须有 render(args, value)(tsc 直接报错);
//   2. parameters 是扁平映射表,不能套 { type: 'object', properties };
//   3. 最隐蔽的一处:本包 package.json 里,@deepseek-ai/* 必须声明成
//      peerDependencies。写成 dependencies 会装出第二份 dsh-tools 副本,
//      注册表和调度器之间那个模块私有的 Symbol 就对不上,运行时报一句
//      "Cannot read properties of undefined (reading 'prepare')"。
// 详见本目录 RUN.md,以及第六章 6.3.1 节。跑一遍:bash verify-on-your-mac.sh

import type { Context } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'
import { readFile } from 'node:fs/promises'
import { parse as parseYaml } from 'yaml'

export const name = 'project-summary'

// 这个插件需要 Harness 已经提供的 tools 注册表和 systemPrompt 拼装服务。
export const inject = ['tools', 'systemPrompt']

export interface Config {
  configPath?: string
}

export const Config: z<Config> = z.object({
  configPath: z.string().default('./project.yml'),
})

export function apply(ctx: Context, config: Config) {
  // 给模型一句提示,告诉它什么时候该用这个工具,而不是自己瞎猜配置格式。
  ctx.systemPrompt.section({
    name: 'tool:project_summary',
    order: 100,
    text: '需要了解项目当前的模块负责人和状态时,使用 project_summary 工具,不要直接猜测或编造。',
  })

  ctx.tools.register(defineTool({
    name: 'project_summary',
    description: '读取项目配置文件,汇总模块负责人和当前状态。',
    parameters: {},
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          summary: { type: 'string', required: true },
        },
      },
      render(_args, value) {
        return [{ type: 'text', text: value.summary }]
      },
    },
    async execute(_args, _exec) {
      const raw = await readFile(config.configPath, 'utf8')
      const data = parseYaml(raw) as Record<string, { owner: string; status: string }>
      const lines = Object.entries(data).map(
        ([module, info]) => `${module}:负责人 ${info.owner},当前状态 ${info.status}`,
      )
      return { summary: lines.join('\n') }
    },
  }))
}
