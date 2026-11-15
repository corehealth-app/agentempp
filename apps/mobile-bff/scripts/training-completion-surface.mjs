// Additive family only; the entire existing96/frozen93 stream stays pinned.
export const completionTransports = new Map([
  ['training/execution-v2/route.ts', ['GET', 'dynamic', 'runtime']],
  ['training/execution-v2/[sessionId]/route.ts', ['GET', 'dynamic', 'runtime']],
  ['training/execution-v2/completions/route.ts', ['POST', 'dynamic', 'runtime']],
  [
    'training/execution-v2/[sessionId]/completions/[completionId]/route.ts',
    ['GET', 'dynamic', 'runtime'],
  ],
  [
    'training/execution-v2/[sessionId]/completions/[completionId]/cancel/route.ts',
    ['POST', 'dynamic', 'runtime'],
  ],
])
export const completionBuildPaths = new Set(
  [...completionTransports.keys()].map((p) => '/api/mobile/v1/' + p.slice(0, -'/route.ts'.length)),
)
