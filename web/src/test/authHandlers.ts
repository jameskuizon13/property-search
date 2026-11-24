import { http, HttpResponse } from 'msw'
import type { User } from '@/features/auth/types'

export const demoUser: User = { id: 1, email: 'demo@example.com', name: 'Demo User', role: 'user' }

const unauthorized = () =>
  HttpResponse.json({ error: { code: 'unauthorized', message: 'You need to sign in' } }, { status: 401 })

export const signedOut = () => http.get('*/api/v1/me', unauthorized)
export const signedIn = (user: User = demoUser) => http.get('*/api/v1/me', () => HttpResponse.json({ data: user }))
