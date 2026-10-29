import { createHash } from 'node:crypto'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import nextConfig from '../next.config.mjs'

const require = createRequire(import.meta.url)
const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const repositoryRoot = resolve(appRoot, '../..')
const webpackModule = require('next/dist/compiled/webpack/webpack')
webpackModule.init()
const { webpack } = webpackModule
const { getNextPublicEnvironmentVariables } = require('next/dist/lib/static-env')
const firstOrigin = 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co'
const original = process.env.NEXT_PUBLIC_SUPABASE_URL
const temporary = await mkdtemp(resolve(tmpdir(), 'performe-billing-env-'))
let result
try {
  process.env.NEXT_PUBLIC_SUPABASE_URL = firstOrigin
  const values = getNextPublicEnvironmentVariables()
  const loader = resolve(temporary, 'typescript-loader.cjs')
  await writeFile(
    loader,
    `const ts = require(${JSON.stringify(require.resolve('typescript'))});
module.exports = function (source) {
  return ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.ESNext,
    target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX}}).outputText;
};`,
  )
  const entry = resolve(temporary, 'entry.ts')
  await writeFile(
    entry,
    `export { mobileBillingCapability } from ${JSON.stringify(
      resolve(repositoryRoot, 'apps/admin/src/lib/billing/revenuecat-configuration.ts'),
    )}; export function compiledPublicOriginControl() { return process.env.NEXT_PUBLIC_SUPABASE_URL; }`,
  )
  const compiler = webpack(
    nextConfig.webpack({
      context: appRoot,
      mode: 'production',
      target: 'node',
      entry,
      output: { path: temporary, filename: 'probe.cjs', library: { type: 'commonjs2' } },
      resolve: {
        extensions: ['.ts', '.tsx', '.js', '.json'],
      },
      optimization: { minimize: false },
      module: { rules: [{ test: /\.tsx?$/, use: [{ loader }] }] },
      plugins: [
        new webpack.DefinePlugin({
          'process.env.NEXT_PUBLIC_SUPABASE_URL': JSON.stringify(
            values['process.env.NEXT_PUBLIC_SUPABASE_URL'],
          ),
        }),
      ],
    }),
  )
  await new Promise((accept, reject) => {
    compiler.run((error, stats) => {
      compiler.close((closeError) => {
        if (error || closeError) return reject(error ?? closeError)
        if (stats.hasErrors())
          return reject(new Error(stats.toString({ all: false, errors: true })))
        accept()
      })
    })
  })
  const output = resolve(temporary, 'probe.cjs')
  const emitted = await readFile(output)
  const { mobileBillingCapability, compiledPublicOriginControl } = require(output)
  process.env.MOBILE_REVENUECAT_BILLING_PROJECT_REF = 'aaaaaaaaaaaaaaaaaaaa'
  process.env.REVENUECAT_WEBHOOK_SIGNING_SECRET = 'synthetic-signing-secret-for-compiled-probe'
  process.env.REVENUECAT_WEBHOOK_ENVIRONMENT = 'sandbox'
  process.env.REVENUECAT_PRODUCT_PLAN_MAP = '{"synthetic":"mensal"}'
  const observed = [mobileBillingCapability().available]
  const control = [compiledPublicOriginControl()]
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://bbbbbbbbbbbbbbbbbbbb.supabase.co'
  observed.push(mobileBillingCapability().available)
  control.push(compiledPublicOriginControl())
  delete process.env.NEXT_PUBLIC_SUPABASE_URL
  observed.push(mobileBillingCapability().available)
  control.push(compiledPublicOriginControl())
  process.env.NEXT_PUBLIC_SUPABASE_URL = firstOrigin
  observed.push(mobileBillingCapability().available)
  control.push(compiledPublicOriginControl())
  result = {
    compiler: 'Next bundled webpack + Next getNextPublicEnvironmentVariables/DefinePlugin',
    nextVersion: require('next/package.json').version,
    bundleSha256: createHash('sha256').update(emitted).digest('hex'),
    expected: [true, false, false, true],
    observed,
    constantControlWasInlined: control.every((value) => value === firstOrigin),
  }
} finally {
  if (original === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL
  else process.env.NEXT_PUBLIC_SUPABASE_URL = original
  // The directory is exclusively created above and contains only this
  // synthetic, reproducible compiler probe. No shared build cache is removed.
  await rm(temporary, { recursive: true, force: true })
}
result.cleanup = 'complete'
console.log(JSON.stringify(result))
if (
  !result.constantControlWasInlined ||
  JSON.stringify(result.observed) !== JSON.stringify(result.expected)
) {
  throw new Error('Compiled billing capability failed runtime origin revalidation')
}
