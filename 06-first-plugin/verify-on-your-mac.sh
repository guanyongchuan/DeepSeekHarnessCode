#!/bin/bash
# ============================================================================
# 《万物皆插件》第六章 06-first-plugin —— 端到端验证脚本
#
# 这个脚本做什么:
#   在一台干净的机器上安装 @deepseek-ai/dsh 0.1.1-rc.2,把第六章的示例插件装进
#   一个真实的 headless Profile,确认它出现在组合树里,最后让模型真的调用一次
#   project_summary 工具,把整条链路跑通。
#
# 两种验证模式:
#   A. 不需要任何 key、不需要外网(默认):脚本会在本机起一个假的、OpenAI 兼容的
#      模型服务,由它返回一个 tool call。这能完整验证"模型决定调用 → Harness 调度
#      执行 → 结果回到模型"这条链路,只是不经过真实的模型推理。
#   B. 用真实模型:export DEEPSEEK_API_KEY=<你的key> 之后再跑,脚本会走真实 API。
#
# 怎么用:
#   bash verify-on-your-mac.sh              # 模式 A
#   DEEPSEEK_API_KEY=sk-xxx bash verify-on-your-mac.sh   # 模式 B
#
# 前提:Node 20 或 22(建议 22 LTS)。脚本只在 ~/dsh-book-test 里干活,
#       唯一的例外是 ~/.dsh/profiles/headless/cordis.patch.yml,改动前会自动备份。
# ============================================================================
set -euo pipefail

WORK="${WORK:-$HOME/dsh-book-test}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE_DIR="$DSH_HOME/profiles/headless"
PNPM="npx --yes pnpm@latest"
FAKE_PORT=8799

echo "=== [0] 环境检查 ==="
command -v node >/dev/null || { echo "找不到 node,请先安装 Node 20/22"; exit 1; }
node --version

if [ -e "$WORK" ]; then
  echo "目录已存在:$WORK"
  echo "请先删掉它(rm -rf $WORK),或者用 WORK=<别的路径> bash $0 换一个位置。"
  exit 1
fi

echo "=== [1] 建工作目录 $WORK ==="
mkdir -p "$WORK"; cd "$WORK"

echo "=== [2] 预先放行原生模块的编译脚本 ==="
# pnpm 默认不跑第三方包的安装脚本,不预先放行会弹一个需要手动选的交互菜单;
# node-pty / koffi 这几个不编译,依赖终端能力的功能会不正常。
cat > pnpm-workspace.yaml << 'EOF'
allowBuilds:
  '@deepseek-ai/dsh-subprocess-local': true
  '@google/genai': true
  koffi: true
  node-pty: true
  protobufjs: true
EOF

echo "=== [3] 用 pnpm 安装 dsh ==="
# 注意:不要用 npm。npm 在这棵依赖树上会卡在依赖解析阶段(本书在两个独立环境
# 各复现过一次,170 秒以上没有任何包完成安装);pnpm 一两分钟内正常装完。
$PNPM add @deepseek-ai/dsh
echo "dsh 版本:$(./node_modules/.bin/dsh --version)"

echo "=== [4] 生成 headless profile 目录 ==="
DSH_HOME="$DSH_HOME" ./node_modules/.bin/dsh --profile headless --dump-config > /dev/null
ls "$PROFILE_DIR"

echo "=== [5] 准备插件包 ==="
mkdir -p "$WORK/plugin/dist"
# 关键:Harness 自己的包(@deepseek-ai/dsh-* 和 cordis)必须声明成 peerDependencies。
# 写成 dependencies 会让包管理器装出第二份 dsh-tools 副本,注册表和调度器之间那个
# 模块私有的 Symbol 就对不上,运行时报 "Cannot read properties of undefined
# (reading 'prepare')" —— 报错信息完全看不出真正的原因。详见第六章 6.3.1 节。
cat > "$WORK/plugin/package.json" << 'EOF'
{
  "name": "chapter-06-first-plugin",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "main": "./dist/index.js",
  "dependencies": {
    "@deepseek-ai/schemastery": "^3.18.1",
    "yaml": "^2.9.0"
  },
  "peerDependencies": {
    "@deepseek-ai/cordis": "^4.0.1",
    "@deepseek-ai/dsh-tools": "^0.1.1-rc.2",
    "@deepseek-ai/dsh-system-prompt": "^0.1.1-rc.2"
  }
}
EOF
cat > "$WORK/plugin/project.yml" << 'EOF'
frontend:
  owner: 张伟
  status: 开发中
backend:
  owner: 李娜
  status: 联调中
infra:
  owner: 王强
  status: 已上线
EOF
# 这份 JS 是 project-summary-plugin.ts 用 tsc 编译出来的产物(已通过类型检查)。
cat > "$WORK/plugin/dist/index.js" << 'EOF'
import z from '@deepseek-ai/schemastery';
import { defineTool } from '@deepseek-ai/dsh-tools';
import { readFile } from 'node:fs/promises';
import { parse as parseYaml } from 'yaml';
export const name = 'project-summary';
export const inject = ['tools', 'systemPrompt'];
export const Config = z.object({
    configPath: z.string().default('./project.yml'),
});
export function apply(ctx, config) {
    ctx.systemPrompt.section({
        name: 'tool:project_summary',
        order: 100,
        text: '需要了解项目当前的模块负责人和状态时,使用 project_summary 工具,不要直接猜测或编造。',
    });
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
                return [{ type: 'text', text: value.summary }];
            },
        },
        async execute(_args, _exec) {
            const raw = await readFile(config.configPath, 'utf8');
            const data = parseYaml(raw);
            const lines = Object.entries(data).map(([module, info]) => `${module}:负责人 ${info.owner},当前状态 ${info.status}`);
            return { summary: lines.join('\n') };
        },
    }));
}
EOF

echo "=== [6] 把插件装进 profile ==="
# 等价于 dsh plugin --profile headless add <path>;直接用 pnpm 是为了绕开
# dsh plugin add 要求 pnpm 必须在 PATH 里这个前提。
cd "$PROFILE_DIR"
$PNPM add "file:$WORK/plugin"

echo "=== [7] 写 cordis.patch.yml ==="
# 插入一行全新的插件,必须用 insert: 包一层(直接塞会报 patch: entry not found);
# 而改已有行的配置(下面模式 A 里的 llm-pi-ai / agent-default-model)则不用 insert。
if [ -s "$PROFILE_DIR/cordis.patch.yml" ] && ! grep -q '^\[\]' "$PROFILE_DIR/cordis.patch.yml"; then
  cp "$PROFILE_DIR/cordis.patch.yml" "$PROFILE_DIR/cordis.patch.yml.bak.$(date +%s)"
  echo "(原有的 cordis.patch.yml 已备份)"
fi

if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
  MODE="B(真实模型)"
  cat > "$PROFILE_DIR/cordis.patch.yml" << EOF
- insert:
    - id: project-summary
      name: 'chapter-06-first-plugin'
      config:
        configPath: '$WORK/plugin/project.yml'
EOF
else
  MODE="A(本机假模型,不联外网)"
  cat > "$PROFILE_DIR/cordis.patch.yml" << EOF
- id: llm-pi-ai
  config:
    providers:
      local-fake:
        api: openai-completions
        baseURL: http://127.0.0.1:$FAKE_PORT/v1
        apiKeyEnv: FAKE_API_KEY
        models:
          - id: fake-model
- id: agent-default-model
  config:
    provider: local-fake
    model: fake-model
- insert:
    - id: project-summary
      name: 'chapter-06-first-plugin'
      config:
        configPath: '$WORK/plugin/project.yml'
EOF
fi
echo "验证模式:$MODE"
cat "$PROFILE_DIR/cordis.patch.yml"

echo "=== [8] 确认组合树里真的出现了这一行 ==="
cd "$WORK"
DSH_HOME="$DSH_HOME" ./node_modules/.bin/dsh --profile headless --dump-config 2>&1 | grep -A4 "id: project-summary"

echo ""
echo "=== [9] 让模型真的调用一次 project_summary ==="

if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
  DSH_HOME="$DSH_HOME" ./node_modules/.bin/dsh --profile headless "调用 project_summary 工具,把结果原样输出给我"
else
  # 假的 OpenAI 兼容模型服务:第一次请求返回一个 project_summary 的 tool call,
  # 收到工具结果后把它原样回显。用来验证整条工具调用链路,不需要 key、不联外网。
  cat > "$WORK/fake-llm.mjs" << 'JSEOF'
import { createServer } from 'node:http'
const PORT = Number(process.env.FAKE_PORT || 8799)
const sse = (res, obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`)
const base = { id: 'chatcmpl-fake', object: 'chat.completion.chunk', created: Math.floor(Date.now()/1000), model: 'fake-model' }
createServer((req, res) => {
  let body = ''
  req.on('data', c => body += c)
  req.on('end', () => {
    if (req.url.includes('/models')) {
      res.writeHead(200, {'content-type':'application/json'})
      return res.end(JSON.stringify({ object:'list', data:[{id:'fake-model', object:'model', owned_by:'fake'}] }))
    }
    let parsed = {}
    try { parsed = JSON.parse(body) } catch {}
    const msgs = parsed.messages || []
    const sawToolResult = msgs.some(m => m.role === 'tool')
    res.writeHead(200, {'content-type':'text/event-stream','cache-control':'no-cache','connection':'keep-alive'})
    if (!sawToolResult) {
      sse(res, {...base, choices:[{index:0, delta:{role:'assistant', content:'', tool_calls:[{index:0, id:'call_fake_1', type:'function', function:{name:'project_summary', arguments:''}}]}, finish_reason:null}]})
      sse(res, {...base, choices:[{index:0, delta:{tool_calls:[{index:0, function:{arguments:'{}'}}]}, finish_reason:null}]})
      sse(res, {...base, choices:[{index:0, delta:{}, finish_reason:'tool_calls'}], usage:{prompt_tokens:10, completion_tokens:5, total_tokens:15}})
    } else {
      const t = msgs.filter(m => m.role === 'tool').pop()
      const txt = typeof t.content === 'string' ? t.content : JSON.stringify(t.content)
      sse(res, {...base, choices:[{index:0, delta:{role:'assistant', content:'工具返回如下:\n'}, finish_reason:null}]})
      sse(res, {...base, choices:[{index:0, delta:{content: txt}, finish_reason:null}]})
      sse(res, {...base, choices:[{index:0, delta:{}, finish_reason:'stop'}], usage:{prompt_tokens:20, completion_tokens:10, total_tokens:30}})
    }
    res.write('data: [DONE]\n\n')
    res.end()
  })
}).listen(PORT, '127.0.0.1', () => console.error(`fake llm on :${PORT}`))
JSEOF
  FAKE_PORT=$FAKE_PORT node "$WORK/fake-llm.mjs" 2>/dev/null &
  SRV=$!
  trap 'kill $SRV 2>/dev/null || true' EXIT
  sleep 1.5
  export FAKE_API_KEY=sk-fake-not-a-real-key
  export NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost"
  DSH_HOME="$DSH_HOME" ./node_modules/.bin/dsh --profile headless "调用 project_summary 工具,把结果原样输出给我"
  kill $SRV 2>/dev/null || true
fi

echo ""
echo "=== 全部跑完 ==="
echo "看到 frontend / backend / infra 三行负责人和状态,就说明整条链路通了:"
echo "模型决定调用 → Harness 调度执行插件 → 结果回到模型 → 模型给出最终回答。"
