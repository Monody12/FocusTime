module.exports = {
  apps: [{
    name: 'focus-timer-sync',
    script: 'dist/index.js',
    cwd: '/root/focus-timer-sync',
    interpreter: '/root/.nvm/versions/node/v22.22.2/bin/node',
    node_args: '--env-file=/root/focus-timer-sync/.env',
    env: {
      NODE_ENV: 'production',
      PORT: 6677
    },
    autorestart: true,
    max_restarts: 10,
    max_memory_restart: '500M',
    watch: false,
    exec_mode: 'fork',
    instances: 1,
    error_file: '/root/focus-timer-sync/logs/pm2-error.log',
    out_file: '/root/focus-timer-sync/logs/pm2-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss'
  }]
}
