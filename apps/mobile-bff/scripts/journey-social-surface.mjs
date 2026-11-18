// Additive, explicit family. Never relax the historical101/96/93 certificates.
export const journeySocialTransports = new Map([
  ['profile/journey-social/route.ts', ['GET', 'PATCH', 'dynamic', 'runtime']],
  ['profile/journey-social/blocks/route.ts', ['GET', 'POST', 'dynamic', 'runtime']],
  ['profile/journey-social/reports/route.ts', ['POST', 'dynamic', 'runtime']],
  ['journey/ranking/route.ts', ['GET', 'dynamic', 'runtime']],
])
export const journeySocialBuildPaths = new Set(
  [...journeySocialTransports.keys()].map(
    (path) => `/api/mobile/v1/${path.slice(0, -'/route.ts'.length)}`,
  ),
)
export function withoutJourneySocialRecords(records, label, fail) {
  console.info(`${label}_SOCIAL_CURRENT_ROUTE_EXPORT_COUNT=${records.length}`)
  if (records.length !== 105) fail(`${label}_SOCIAL_CURRENT_STREAM`)
  for (const [path, methods] of journeySocialTransports) {
    const record = records.find((value) => value.path === path)
    if (JSON.stringify(record?.exports) !== JSON.stringify(methods))
      fail(`${label}_SOCIAL_EXPORTS:${path}`)
    if (
      label === 'WRAPPER' &&
      record?.sourcePath !== `@/app/api/mobile/v1/${path.replace(/\.ts$/, '')}`
    )
      fail(`${label}_SOCIAL_SOURCE:${path}`)
  }
  return records.filter((record) => !journeySocialTransports.has(record.path))
}
export function withoutJourneySocialBuild(surface, hash, fail) {
  console.info(`BUILD_SOCIAL_CURRENT_MOBILE_ROUTE_PATH_COUNT=${surface.mobileRoutePaths.length}`)
  if (
    surface.mobileRoutePaths.length !== 105 ||
    [...journeySocialBuildPaths].some(
      (path) => !surface.mobileRoutePaths.includes(path) || !surface.routePaths.includes(path),
    )
  )
    fail('SOCIAL_CURRENT_ROUTES')
  const routePaths = surface.routePaths.filter((path) => !journeySocialBuildPaths.has(path)),
    mobileRoutePaths = surface.mobileRoutePaths.filter((path) => !journeySocialBuildPaths.has(path))
  // Bundles, traces, dependencies and forbidden-reference scans remain COMPLETE.
  return {
    ...surface,
    routePaths,
    mobileRoutePaths,
    routePathHash: hash(routePaths.map((path) => `${path}\n`).join('')),
    mobileRoutePathHash: hash(mobileRoutePaths.map((path) => `${path}\n`).join('')),
  }
}
