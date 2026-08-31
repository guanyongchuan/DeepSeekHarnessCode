import { Context, Service } from '@deepseek-ai/cordis'

class Counter extends Service {
  value = 0

  constructor(ctx) {
    super(ctx, 'counter')
  }

  next() {
    return ++this.value
  }
}

const greeter = Object.assign((ctx) => {
  ctx.on('app/ready', (message) => {
    console.log(message, '#' + ctx.counter.next())
  })
}, {
  inject: ['counter'],
})

const root = new Context()
await root.plugin(Counter)
await root.plugin(greeter)

root.emit('app/ready', 'started')
await root.fiber.dispose()
console.log('disposed cleanly')
