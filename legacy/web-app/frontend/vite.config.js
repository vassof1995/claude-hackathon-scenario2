import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// In production, nginx serves dist/ and proxies /api to web-api.
// In local `npm run dev`, proxy /api to the web-api container/port.
export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      '/api': 'http://localhost:8081'
    }
  }
})
