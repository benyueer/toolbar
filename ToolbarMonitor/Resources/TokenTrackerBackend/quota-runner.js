const os = require("node:os");
const { getUsageLimits } = require("./src/lib/usage-limits");

getUsageLimits({
  home: os.homedir(),
  env: process.env,
  platform: process.platform,
  forceRefresh: process.argv.includes("--refresh"),
}).then((result) => {
  process.stdout.write(JSON.stringify(result));
}).catch((error) => {
  process.stderr.write(String(error?.stack || error));
  process.exitCode = 1;
});
