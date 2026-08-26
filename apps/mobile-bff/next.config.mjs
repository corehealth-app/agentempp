import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const appRoot = dirname(fileURLToPath(import.meta.url))
const adminSourceRoot = resolve(appRoot, '../admin/src')
const monorepoRoot = resolve(appRoot, '../..')
const inngestClientSource = resolve(
  monorepoRoot,
  'packages/inngest-functions/src/client.ts',
)

/** @type {import('next').NextConfig} */
const nextConfig = {
  outputFileTracingRoot: monorepoRoot,
  transpilePackages: [
    '@mpp/agent',
    '@mpp/core',
    '@mpp/db',
    '@mpp/inngest-functions',
    '@mpp/providers',
  ],
  webpack: (config) => {
    config.resolve.alias = {
      ...config.resolve.alias,
      '@': adminSourceRoot,
      '@mpp/inngest-functions$': inngestClientSource,
    }
    config.resolve.extensionAlias = {
      '.js': ['.ts', '.tsx', '.js', '.jsx'],
      '.mjs': ['.mts', '.mjs'],
    }
    return config
  },
}

export default nextConfig
