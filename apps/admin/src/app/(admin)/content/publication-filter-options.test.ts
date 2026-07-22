import { describe, expect, it } from 'vitest'
import { buildPublicationIdentityOptions } from './publication-filter-options'

const GLOBAL_AUTHOR_ID = '10000000-0000-4000-8000-000000000001'
const PAGE_AUTHOR_ID = '20000000-0000-4000-8000-000000000002'
const OBSERVED_ONLY_ID = '30000000-0000-4000-8000-000000000003'
const SELECTED_ONLY_ID = '40000000-0000-4000-8000-000000000004'

describe('publication filter options', () => {
  it('keeps global and selected identities, deduplicated and deterministically sorted', () => {
    expect(
      buildPublicationIdentityOptions(
        [
          { id: PAGE_AUTHOR_ID, name: 'Beatriz' },
          { id: GLOBAL_AUTHOR_ID, name: 'Ana' },
        ],
        [PAGE_AUTHOR_ID, PAGE_AUTHOR_ID, OBSERVED_ONLY_ID, null],
        SELECTED_ONLY_ID,
      ),
    ).toEqual([
      [GLOBAL_AUTHOR_ID, 'Ana · 10000000...'],
      [PAGE_AUTHOR_ID, 'Beatriz · 20000000...'],
      [OBSERVED_ONLY_ID, '30000000...'],
      [SELECTED_ONLY_ID, '40000000...'],
    ])
  })
})
