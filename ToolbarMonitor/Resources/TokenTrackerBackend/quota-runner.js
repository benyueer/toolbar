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
  process.stdout.write(JSON.stringify(result))
}).catch((error) => {
  process.stderr.write(String(error?.stack || error))
  process.exitCode = 1
})
