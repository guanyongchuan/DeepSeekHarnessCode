# 06-first-plugin:验证状态说明

对应《万物皆插件》第六章 6.3-6.5 节。

## 这份代码是什么

`project-summary-plugin.ts` 是一个按官方真实导出形状(`name` / `inject` / `Config` / `apply`)
编写的 Cordis 插件,功能是读取 `project.yml` 里记录的模块负责人和状态,汇总成一段文字,
通过 `defineTool()` 注册成一个模型可以调用的工具 `project_summary`。

## 2026-08-31:端到端验证已全部完成

整条链路——模型决定调用 → Harness 调度执行插件 → 结果回到模型 → 模型给出最终回答——
已经完整跑通并留下真实输出。过程中发现并修正了**三处**这份代码原来的真实错误。三处都不是
推测出来的,都是真机跑出来的报错逼出来的。

### 修正一:`defineTool()` 的 `output` 必须有 `render()`

`tsc` 编译时直接报错:`output` 不能只给一个 `schema`,还必须提供 `render(args, value)`,
把 `execute()` 返回的、通过 schema 校验的值转换成模型真正看到的 `ContentBlock[]`
(最简单情况就是 `[{ type: 'text', text: value.summary }]`)。这是
`@deepseek-ai/dsh-tools@0.1.1-rc.2` 的真实类型声明(`lib/types/schema.d.ts` 里的
`DefineToolOptions`)直接要求的。

### 修正二:`parameters` 是扁平映射表,不要套 `{ type: 'object', properties }`

用同样的方法核对第六章 6.7 节的 Python 桥接示例时发现的:`parameters` 的真实类型是
`ParameterSchemaSpec`,即一份"属性名 → 属性定义"的扁平映射表。套一层 `type`/`properties`
会直接编译不过。

### 修正三(最隐蔽的一处):Harness 自己的包必须声明成 `peerDependencies`

前两处修好、插件也装进 Profile、`--dump-config` 确认无误之后,真正让模型调用工具时,
撞上了这条报错:

```
dsh: UNKNOWN: Cannot read properties of undefined (reading 'prepare')
```

报错信息里没有任何一个字提到插件、依赖或版本。根因是这份 `package.json` 原来把
`@deepseek-ai/dsh-tools` 写进了 `dependencies`——包管理器于是装出**第二份物理副本**。
而 `dsh-tools` 内部,工具注册表和调度器之间是靠一个模块私有的
`Symbol('@deepseek-ai/dsh-tools.scheduler')` 挂钩的,`Symbol()` 每次调用都产生一个全新的、
互不相等的值,所以副本 A 建的注册表用副本 A 的 Symbol 去取,取到 `undefined`,
下一行 `.prepare(...)` 就炸了。

对照官方插件 `@deepseek-ai/dsh-tool-fs` 的 `package.json` 就一目了然:它的 `dependencies`
只有 `diff` 和 `@deepseek-ai/schemastery` 两个,所有 `@deepseek-ai/dsh-*` 和
`@deepseek-ai/cordis` 全部在 `peerDependencies` 里。本目录的 `package.json` 已按这个规则改正。

**规则:凡是 Harness 自己的包放 `peerDependencies`,只有插件独有的第三方库放 `dependencies`。**

### 最终的真实输出

```
=== [9] 让模型真的调用一次 project_summary ===
工具返回如下:
frontend:负责人 张伟,当前状态 开发中
backend:负责人 李娜,当前状态 联调中
infra:负责人 王强,当前状态 已上线
```

## 自己跑一遍:`verify-on-your-mac.sh`

本目录的 `verify-on-your-mac.sh` 把整套流程写成了一个脚本,两种模式:

```bash
bash verify-on-your-mac.sh                            # 模式 A:不需要 key,不联外网
DEEPSEEK_API_KEY=sk-xxx bash verify-on-your-mac.sh    # 模式 B:走真实模型 API
```

**模式 A 是这次验证实际使用的方法,也推荐给所有写 Harness 插件的人**:脚本会在本机起一个
几十行的、OpenAI 兼容协议的假模型服务,通过第十二章 12.6 节讲的 Custom Provider 配置接进
`dsh`,由它返回一个写死的 tool call。这样验证"我的插件到底有没有被正确调用",不花钱、不联网,
而且出了问题一定是自己插件的问题,不会和网络、额度、模型发挥混在一起。上面那处最隐蔽的
`peerDependencies` bug,就是用这个方法在几分钟内定位到的。

模式 A 和模式 B 唯一的差别,是有没有经过真实的模型推理;工具注册、调度、执行、结果回传这
几步,两种模式走的是完全相同的代码路径。
