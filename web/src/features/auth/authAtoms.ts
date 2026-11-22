import { atomWithStorage } from 'jotai/utils'

export const tokenAtom = atomWithStorage<string | null>('auth_token', null, undefined, {
  getOnInit: true,
})
