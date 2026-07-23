{{flutter_js}}
{{flutter_build_config}}

const loading = document.getElementById('app-loading');
const loadingStatus = document.getElementById('loading-status');
const retryButton = document.getElementById('loading-retry');
const flutterConfig = {
  fontFallbackBaseUrl: new URL('font-fallback/', document.baseURI).toString()
};

let appStarted = false;
const startupTimeout = window.setTimeout(() => {
  showStartupFailure('加载时间过长，请检查网络后重试。');
}, 30000);

function showStartupFailure(message, error) {
  if (appStarted || !loading || !loading.isConnected) return;
  window.clearTimeout(startupTimeout);
  loading.classList.add('failed');
  loading.setAttribute('role', 'alert');
  loadingStatus.textContent = message;
  if (error) console.error('FocusMyTime startup failed:', error);
}

retryButton?.addEventListener('click', () => window.location.reload());
window.addEventListener('error', (event) => {
  showStartupFailure('应用加载失败，请重新加载。', event.error || event.message);
});
window.addEventListener('unhandledrejection', (event) => {
  showStartupFailure('应用初始化失败，请重新加载。', event.reason);
});

async function acquireDatabaseTabLock() {
  if (!navigator.locks?.request) return true;

  return new Promise((resolve) => {
    navigator.locks.request(
      'focus-my-time-indexeddb',
      { mode: 'exclusive', ifAvailable: true },
      (lock) => {
        if (!lock) {
          resolve(false);
          return;
        }
        resolve(true);
        // Keep the lock for this tab's lifetime. The browser releases it when
        // the page is closed or reloaded.
        return new Promise(() => {});
      }
    ).catch((error) => {
      console.warn('Web Locks API unavailable; continuing without a tab lock.', error);
      resolve(true);
    });
  });
}

async function startApplication() {
  const hasDatabaseLock = await acquireDatabaseTabLock();
  if (!hasDatabaseLock) {
    showStartupFailure('FocusMyTime 已在另一个标签页中打开。请关闭另一个标签页后重新加载。');
    return;
  }

  _flutter.loader.load({
    config: flutterConfig,
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}}
    },
    onEntrypointLoaded: async function(engineInitializer) {
      try {
        loadingStatus.textContent = '正在初始化本地数据...';
        const appRunner = await engineInitializer.initializeEngine(flutterConfig);
        await appRunner.runApp();
        appStarted = true;
        window.clearTimeout(startupTimeout);
        loading?.remove();
      } catch (error) {
        showStartupFailure('应用初始化失败，请重新加载。', error);
      }
    }
  }).catch((error) => {
    showStartupFailure('应用加载失败，请重新加载。', error);
  });
}

startApplication();
