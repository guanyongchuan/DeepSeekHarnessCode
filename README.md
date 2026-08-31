# 《万物皆插件》配套代码仓库

本仓库收录本书涉及的可运行代码示例,按章节分目录组织。所有示例均针对 `@deepseek-ai/cordis@4.0.1` 和 `@deepseek-ai/dsh@0.1.1-rc.2` 核实/运行,版本号见各目录内的 `package.json`。

## 兼容矩阵

| 示例 | 依赖包 | 核实版本 | 状态 |
|---|---|---|---|
| `05-cordis/quickstart.mjs` | `@deepseek-ai/cordis` | 4.0.1 | 已实际运行通过 |
| `05-cordis/dispose-test.mjs` | `@deepseek-ai/cordis` | 4.0.1 | 已实际运行通过,验证效果可逆边界 |
| `06-first-plugin/project-summary-plugin.ts` | `@deepseek-ai/cordis` 4.0.1, `@deepseek-ai/dsh-tools` 0.1.1-rc.2, `@deepseek-ai/schemastery` 3.18.1 | 对齐 `dsh-tool-fs` 的导出形状与依赖声明方式 | **端到端已跑通**:编译、装进真实 Profile、`--dump-config` 确认、模型真实调用工具并拿到结果(见 `06-first-plugin/RUN.md`)|
| `06-first-plugin/verify-on-your-mac.sh` | — | 在真机上从零跑通验证过 | 一键复现上面整条链路;默认模式不需要 API key、不联外网 |

## clean-machine 安装验证(2026-08-31,已完成)

之前这里记录过一个未闭环项:`@deepseek-ai/dsh` 完整依赖树用 `npm install` 反复卡在依赖解析阶段(几分钟过去,没有任何包完成安装),当时归因为"沙箱环境限制"。这一项本轮已经解决,记录真实过程,而不是简单地说"已修复":

- **`npm` 的问题被独立复现了两次,不是偶发的沙箱限制**:除了此前网络受限的沙箱环境,这次在管老师本地电脑连接的另一个独立环境里(网络正常、能直连 npm registry),`npm install @deepseek-ai/dsh` 依然在依赖解析阶段卡住——两次单独的 170+ 秒同步等待,终端没有任何新输出,`node_modules` 里 0 个包。这说明更可能是 `npm` 自身的解析器在这棵规模较大、多层 `@deepseek-ai/*` scoped 包嵌套的依赖树上效率很差,而不是网络或沙箱的问题。
- **换成 `pnpm` 之后,同一棵依赖树顺利装完**:`npx --yes pnpm@latest add @deepseek-ai/dsh`,504 个包完成解析下载,447 个包链接进 `node_modules`,全程不到 3 分钟。这也不是权宜之计——第四章讲过 `dsh plugin add` 命令本身对外转发的就是 `pnpm`,`pnpm` 是这套工具链原本选定的包管理器。
- **真实终端验证记录**(环境:Node v22.23.2、npm 10.9.8、pnpm 11.24.0,Linux aarch64,2026-08-31):
  ```
  $ node_modules/.bin/dsh --version
  0.1.1-rc.2
  $ node_modules/.bin/dsh --profile web --dump-config
  # (输出的组合树与第四章描述完全一致,例如 llm / session / typert-registry /
  #  agent-default-model / session-persistence-jsonl 等行)
  ```
- **版本锚点**:`@deepseek-ai/dsh@0.1.1-rc.2` 这个 npm 发布包没有附带 `gitHead`,查不到对应 Git commit SHA;改用发布包本身的 tarball 校验值作为等价锚点——`shasum 1a5112369f1c46b13a6e6f21de8af5e6afd45074` / `integrity sha512-UP1UIh6q3Gme/yXRn/QL2P8IsVlv8Shpg22TRJIZPsCRWLm4CBiA1MUvXmJAfsOEETBMLAl+xWPtFw6ICsN3wg==`,任何人都可以用 `npm view @deepseek-ai/dsh@0.1.1-rc.2 dist.shasum` 独立核对。

这意味着:

- `05-cordis/` 下的两个示例是直接对 `@deepseek-ai/cordis`(Harness 插件机制的底层引擎)编写并实际运行的,输出已经过验证,可以直接复现。
- 第三章 Quick Start 流程(3.1-3.7 节)现在有了真实的、留档的终端验证记录,不再是占位表述——详见第三章正文里对应这次验证的段落。
- `06-first-plugin/` 下的插件代码**端到端已经跑通**:编译、装进真实 `dsh` Profile、`--dump-config` 确认组合树、模型真的调用了这个工具并把结果拿了回去。这一轮一共揪出并修正了三处真实错误,全部是真机报错逼出来的,不是推测:(1) `defineTool()` 的 `output` 必须带 `render()`;(2) `parameters` 是扁平映射表,不能套 `{ type: 'object', properties }`;(3) 最隐蔽的一处——Harness 自己的包必须声明成 `peerDependencies`,写成 `dependencies` 会装出第二份 `dsh-tools` 副本,导致注册表和调度器之间那个模块私有的 `Symbol` 对不上,运行时报一句和依赖毫无关系的 `Cannot read properties of undefined (reading 'prepare')`。三处都已同步进第六章正文(新增 6.3.1、6.3.2 两节),详见 `06-first-plugin/RUN.md`。
- 验证方法本身也值得一提:最后这一步没有用真实模型 API,而是在本机起了一个 OpenAI 兼容协议的假模型服务,用第十二章 12.6 节讲的 Custom Provider 配置接进 `dsh`。不花钱、不联外网,而且排除了网络和模型发挥的干扰——顺带把 12.6 节的配置路径也真机验证了一遍。

补充说明(2026-08-30 核实):`@deepseek-ai/cordis` 当天发布了 4.0.2,经过源码比对,`src/` 与 4.0.1 完全一致,只是三个依赖的版本号上调——这次补丁发布不影响本仓库任何示例代码。`@deepseek-ai/dsh` 同一天在 `alpha` 标签下发布了 `0.1.2-alpha.2`,其中 Agent Preset 目录被移到了一个独立的 monorepo 包(`packages/preset/agent-presets`),通过新的 `dsh.configTrees` 字段挂载,不再直接打包进 CLI 的 `config/agent-presets/` 目录——但 `npm` 的 `latest` 标签目前仍指向 `0.1.1-rc.2`,本书和本仓库固定使用的版本没有受到影响,这一项作为"送印前再确认一次"的监控项记录在此。

## 目录

- `05-cordis/` — 第五章 Cordis 机制的最小可运行示例
- `06-first-plugin/` — 第六章"AI 项目助理"第一个自定义插件(含一键验证脚本 `verify-on-your-mac.sh`)
