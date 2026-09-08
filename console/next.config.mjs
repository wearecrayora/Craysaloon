/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // The token package is TypeScript source, shared verbatim with the Flutter
  // side's schema. Consuming the source rather than a build artifact is the
  // point: the operator's preview and the customer's app resolve the same
  // tokens from the same code (ADR-22), so there is no build step where they
  // could drift apart.
  transpilePackages: ['@cray/design-tokens'],

  webpack: (config) => {
    // Its internal imports are written as `./color.js` (correct ESM), but the
    // files on disk are .ts. Without this, webpack looks for a .js that does
    // not exist.
    config.resolve.extensionAlias = {
      ...config.resolve.extensionAlias,
      '.js': ['.ts', '.tsx', '.js'],
    };
    return config;
  },

  // The console handles per-salon credentials and can create tenants. None of
  // that should ever be framed, sniffed, or referred onward.
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'no-referrer' },
          { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
          {
            key: 'Strict-Transport-Security',
            value: 'max-age=63072000; includeSubDomains; preload',
          },
        ],
      },
    ];
  },
};

export default nextConfig;
