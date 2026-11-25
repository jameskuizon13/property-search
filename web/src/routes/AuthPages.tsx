import { useRouter, useSearch } from '@tanstack/react-router'
import type { ReactNode } from 'react'
import { LoginForm } from '@/features/auth/LoginForm'
import { safeNext } from '@/features/auth/safeNext'
import { SignupForm } from '@/features/auth/SignupForm'

function AuthCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <main className="mx-auto mt-16 max-w-sm px-4">
      <h1 className="mb-6 text-2xl font-semibold">{title}</h1>
      <div className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm">{children}</div>
    </main>
  )
}

function useGoNext(next: string | undefined) {
  const router = useRouter()
  return () => router.history.push(safeNext(next))
}

export function LoginPage() {
  const { next } = useSearch({ from: '/login' })
  const goNext = useGoNext(next)
  return (
    <AuthCard title="Sign in">
      <LoginForm next={next} onSuccess={goNext} />
    </AuthCard>
  )
}

export function SignupPage() {
  const { next } = useSearch({ from: '/signup' })
  const goNext = useGoNext(next)
  return (
    <AuthCard title="Create an account">
      <SignupForm next={next} onSuccess={goNext} />
    </AuthCard>
  )
}
