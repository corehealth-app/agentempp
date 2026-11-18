import { createHash } from 'node:crypto'
import fs from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

// Build a closed scheduler/provider-free Edge artifact from the tested source.
// Output must stay outside the repository; it contains no environment files.
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const out = path.resolve(process.argv[2] ?? '')
if (!process.argv[2] || out === root || out.startsWith(`${root}/`))
  throw Error('Provide an external artifact directory')
fs.mkdirSync(out, { recursive: true })
for (const name of ['maintenance.js', 'index.ts', 'SOURCE-MANIFEST.json'])
  if (fs.existsSync(path.join(out, name))) throw Error('Refuse to overwrite an existing artifact')
const require = createRequire(path.join(root, 'packages/inngest-functions/package.json'))
const vitePackage = createRequire(require.resolve('vitest/package.json')).resolve(
  'vite/package.json',
)
const { build } = await import(
  pathToFileURL(path.join(path.dirname(vitePackage), 'dist/node/index.js'))
)
const result = await build({
  root,
  configFile: false,
  logLevel: 'error',
  build: {
    outDir: out,
    emptyOutDir: false,
    write: false,
    minify: false,
    target: 'es2022',
    sourcemap: false,
    lib: {
      entry: path.join(
        root,
        'packages/inngest-functions/src/lib/conversation-media-maintenance.ts',
      ),
      formats: ['es'],
      fileName: () => 'maintenance.js',
    },
    rollupOptions: { output: { inlineDynamicImports: true } },
  },
})
const chunks = (Array.isArray(result) ? result : [result]).flatMap((x) => x.output)
if (
  chunks.length !== 1 ||
  chunks[0].type !== 'chunk' ||
  chunks[0].imports.length !== 0 ||
  chunks[0].dynamicImports.length !== 0
)
  throw Error('Unexpected runtime dependency')
const modules = Object.keys(chunks[0].modules).filter((x) => !x.startsWith('\0'))
const pureAgentLeaves = [
  'reevaluation-photo-disposition.ts',
  'supabase-reevaluation-photo-disposition.ts',
]
if (
  modules.some(
    (x) =>
      /packages\/providers\/|inngest-functions\/src\/(functions\/|client\.|lib\/env\.)|node_modules\/.*\/inngest\//.test(
        x,
      ) ||
      (x.includes('/packages/agent/') &&
        !pureAgentLeaves.some((leaf) => x === path.join(root, 'packages/agent/src', leaf))),
  )
)
  throw Error('Scheduler/provider dependency crossed the cleanup boundary')
const hash = (x) => createHash('sha256').update(x).digest('hex')
const entry = fs.readFileSync(
  path.join(root, 'supabase/functions/conversation-media-maintenance/index.ts'),
)
fs.writeFileSync(path.join(out, 'maintenance.js'), chunks[0].code, { flag: 'wx' })
fs.writeFileSync(path.join(out, 'index.ts'), entry, { flag: 'wx' })
const manifest = {
  schema: 'conversation.media-maintenance-artifact.v1',
  target: 'xitugspwfxkcluxvrdeg',
  files: ['index.ts', 'maintenance.js'].map((name) => ({
    name,
    sha256: hash(fs.readFileSync(path.join(out, name))),
    bytes: fs.statSync(path.join(out, name)).size,
  })),
  modules: modules.map((name) => ({
    path: path.relative(root, name),
    sha256: hash(fs.readFileSync(name)),
  })),
}
fs.writeFileSync(path.join(out, 'SOURCE-MANIFEST.json'), `${JSON.stringify(manifest, null, 2)}\n`, {
  flag: 'wx',
})
console.log(
  JSON.stringify({ files: manifest.files, modules: modules.length, schedulerAndProviders: false }),
)
