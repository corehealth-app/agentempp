/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    typedRoutes: false,
    // View Transitions API — fade suave entre rotas no Chrome/Edge
    // (degrada gracefully em browsers sem suporte)
    viewTransition: true,
  },
  transpilePackages: [
    '@mpp/agent',
    '@mpp/core',
    '@mpp/db',
    '@mpp/inngest-functions',
    '@mpp/providers',
  ],
  webpack: (config) => {
    // Permite imports com .js apontando para arquivos .ts (ESM-style nos packages workspace)
    config.resolve.extensionAlias = {
      '.js': ['.ts', '.tsx', '.js', '.jsx'],
      '.mjs': ['.mts', '.mjs'],
    }
    return config
  },
}

export default nextConfig
