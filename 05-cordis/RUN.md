# 运行方式

```bash
npm install
node quickstart.mjs      # 官方 README quick-start 示例,已验证输出: "started #1" / "disposed cleanly"
node dispose-test.mjs    # 验证第五章 5.8 节的可逆边界:managed effect 被摘除,unmanaged 副作用不受影响
```

`dispose-test.mjs` 的预期输出:

```
plugin wrote an external file (unmanaged side effect)
managed listener fired for first call, plugin active #1
--- now disposing the plugin fiber (not the root) ---
--- checking whether the external file still exists ---
file still exists on disk: true
```

注意第二次 `root.emit('greet', ...)` 之后,"managed listener fired" 不会再打印一次——这正是第五章 5.8 节的核心论证:通过 `ctx.on()` 登记的效果被彻底摘除,而绕过 Cordis 直接执行的 `fs.writeFileSync()` 完全不受卸载影响。
