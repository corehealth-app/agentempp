export interface PublicationIdentityOptionSource {
  id: string
  name: string | null
}

export type PublicationIdentityOption = readonly [id: string, label: string]

export function buildPublicationIdentityOptions(
  globalIdentities: readonly PublicationIdentityOptionSource[],
  observedIds: readonly (string | null | undefined)[],
  selectedId?: string,
): PublicationIdentityOption[] {
  const identities = new Map<string, string | null>()

  for (const identity of globalIdentities) {
    const name = identity.name?.trim() || null
    const currentName = identities.get(identity.id)
    if (!identities.has(identity.id) || (!currentName && name)) {
      identities.set(identity.id, name)
    }
  }

  for (const id of observedIds) {
    if (id && !identities.has(id)) identities.set(id, null)
  }
  if (selectedId && !identities.has(selectedId)) identities.set(selectedId, null)

  return [...identities]
    .map(([id, name]) => ({
      id,
      name,
      label: name ? `${name} · ${shortId(id)}` : shortId(id),
    }))
    .sort((left, right) => {
      if (Boolean(left.name) !== Boolean(right.name)) return left.name ? -1 : 1
      return compareText(left.label, right.label) || compareText(left.id, right.id)
    })
    .map(({ id, label }) => [id, label])
}

function compareText(left: string, right: string): number {
  return left === right ? 0 : left < right ? -1 : 1
}

function shortId(value: string): string {
  return `${value.slice(0, 8)}...`
}
