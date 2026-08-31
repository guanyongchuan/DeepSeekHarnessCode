import { Context, Service } from '@deepseek-ai/cordis'
import fs from 'node:fs'

class Counter extends Service {
  value = 0
  constructor(ctx) {
    super(ctx, 'counter')
  }
  next() {
    return ++this.value
  }
}

let fileWasWritten = false

const myPlugin = Object.assign((ctx) => {
  // A managed effect: registered through ctx.on(), tracked by the fiber.
  ctx.on('greet', (name) => {
    console.log('managed listener fired for', name, '#' + ctx.counter.next())
  })

  // An UNMANAGED side effect: happens outside Cordis's effect tracking.
  // Cordis has no way to know this happened, let alone undo it.
  fs.writeFileSync('/tmp/unmanaged-side-effect.txt', 'plugin wrote this file directly, bypassing ctx.effect()')
  fileWasWritten = true
  console.log('plugin wrote an external file (unmanaged side effect)')
}, {
  inject: ['counter'],
})

const root = new Context()
await root.plugin(Counter)
const fiber = root.plugin(myPlugin)
await fiber.await()

root.emit('greet', 'first call, plugin active')

console.log('--- now disposing the plugin fiber (not the root) ---')
await fiber.dispose()

// Try emitting the same event again after disposal.
root.emit('greet', 'second call, plugin disposed')

console.log('--- checking whether the external file still exists ---')
console.log('file still exists on disk:', fs.existsSync('/tmp/unmanaged-side-effect.txt'))

await root.fiber.dispose()
