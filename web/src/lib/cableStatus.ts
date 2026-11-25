import { atom } from 'jotai'

/**
 * The live-updates socket, for the header's status dot. `connecting` covers
 * ActionCable's own reconnect attempts; `disconnected` means it gave up (for
 * example, the cookie expired) or the user is signed out.
 */
export type CableStatus = 'disconnected' | 'connecting' | 'connected'

export const cableStatusAtom = atom<CableStatus>('disconnected')
