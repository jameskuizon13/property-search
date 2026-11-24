import { ApiError, apiFetch } from '@/lib/api'
import type { User } from './types'

type Envelope<T> = { data: T }

export type LoginInput = { email: string; password: string }
export type SignupInput = LoginInput & { name: string }

/** The signed-in user, or null when nobody is signed in. */
export async function fetchMe(): Promise<User | null> {
  try {
    const { data } = await apiFetch<Envelope<User>>('/me', { allowUnauthorized: true })
    return data
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) return null
    throw err
  }
}

export async function login(input: LoginInput): Promise<User> {
  const { data } = await apiFetch<Envelope<User>>('/auth/login', {
    method: 'POST',
    body: input,
    allowUnauthorized: true,
  })
  return data
}

export async function signup(input: SignupInput): Promise<User> {
  const { data } = await apiFetch<Envelope<User>>('/auth/signup', { method: 'POST', body: input })
  return data
}

export async function logout(): Promise<void> {
  await apiFetch<void>('/auth/logout', { method: 'DELETE', allowUnauthorized: true })
}
