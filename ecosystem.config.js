module.exports = {
  apps : [{
    name   : "openclaw",
    script : "openclaw",
    args   : "gateway --port 18789 --allow-unconfigured",
    cwd    : "/home/openclaw",
    env: {
      NODE_ENV: "production"
    }
  }]
}
