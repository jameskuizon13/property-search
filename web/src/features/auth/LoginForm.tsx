import { Link } from '@tanstack/react-router'
import type { FormEvent } from 'react'
import { useToast } from '@/components/ui/toast'
import { authErrorMessage } from './errorMessage'
import { FormField } from './FormField'
import { useLogin } from './useAuthMutations'

export function LoginForm({ next, onSuccess }: { next?: string; onSuccess: () => void }) {
  const toast = useToast()
  const loginMutation = useLogin()

  function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = new FormData(e.currentTarget)
    loginMutation.mutate(
      { email: String(form.get('email')), password: String(form.get('password')) },
      {
        onSuccess,
        // Errors about the whole form are toasts; field errors (422) stay inline.
        onError: (err) => {
          const message = authErrorMessage(err)
          if (message) toast(message, 'error')
        },
      },
    )
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4" noValidate>
      <FormField label="Email" name="email" type="email" autoComplete="email" required />
      <FormField label="Password" name="password" type="password" autoComplete="current-password" required />
      <button
        type="submit"
        disabled={loginMutation.isPending}
        className="w-full rounded-md bg-indigo-600 px-4 py-2 font-medium text-white hover:bg-indigo-500 disabled:opacity-60"
      >
        {loginMutation.isPending ? 'Signing in…' : 'Sign in'}
      </button>
      <p className="text-center text-sm text-slate-600">
        No account?{' '}
        <Link to="/signup" search={{ next }} className="font-medium text-indigo-600 hover:underline">
          Sign up
        </Link>
      </p>
    </form>
  )
}
