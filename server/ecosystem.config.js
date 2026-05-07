module.exports = {
  apps: [{
    name: 'focus-timer-sync',
    script: 'dist/index.js',
    cwd: '/root/focus-timer-sync',
    env: {
      NODE_ENV: 'production',
      PORT: 6677
    },
    autorestart: true,
    max_restarts: 10,
    max_memory_restart: '500M',
    watch: false,
    instances: 1,
    error_file: '/root/focus-timer-sync/logs/pm2-error.log',
    out_file: '/root/focus-timer-sync/logs/pm2-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss'
  }]
}