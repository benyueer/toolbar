const os = require('node:os')
const { getUsageLimits } = require('./src/lib/usage-limits')

// 解析命令行参数中的 --providers，例如：--providers codex,antigravity,opencodeGo
const providersArgIndex = process.argv.indexOf('--providers')
let providers = null
if (providersArgIndex !== -1 && process.argv[providersArgIndex + 1]) {
  providers = process.argv[providersArgIndex + 1]
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
}

getUsageLimits({
  home: os.homedir(),
  env: process.env,
  platform: process.platform,
  forceRefresh: process.argv.includes('--refresh'),
  providers,
}).then((result) => {
  // 输出完成后立即退出进程，避免 Node.js fetch (undici) 的 HTTP keep-alive 连接池挂起事件循环空等 5-7 秒
  process.stdout.write(JSON.stringify(result), () => {
    process.exit(0)
  })
}).catch((error) => {
  process.stderr.write(String(error?.stack || error), () => {
    process.exit(1)
  })
})
