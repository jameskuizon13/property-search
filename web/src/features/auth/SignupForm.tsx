import { Link } from '@tanstack/react-router'
import type { FormEvent } from 'react'
import { useToast } from '@/components/ui/toast'
import { ApiError } from '@/lib/api'
import { authErrorMessage } from './errorMessage'
import { FormField } from './FormField'
import { useSignup } from './useAuthMutations'

export function SignupForm({ next, onSuccess }: { next?: string; onSuccess: () => void }) {
  const toast = useToast()
  const signupMutation = useSignup()
  const error = signupMutation.error
  const fieldErrors = error instanceof ApiError && error.status === 422 ? (error.details ?? {}) : {}

  function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = new FormData(e.currentTarget)
    signupMutation.mutate(
      {
        name: String(form.get('name')),
        email: String(form.get('email')),
        password: String(form.get('password')),
      },
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
      <FormField label="Name" name="name" autoComplete="name" required errors={fieldErrors.name} />
      <FormField label="Email" name="email" type="email" autoComplete="email" required errors={fieldErrors.email} />
      <FormField
        label="Password"
        name="password"
        type="password"
        autoComplete="new-password"
        minLength={12}
        maxLength={72}
        required
        errors={fieldErrors.password}
      />
      <p className="text-xs text-slate-500">12 to 72 characters.</p>
      <button
        type="submit"
        disabled={signupMutation.isPending}
        className="w-full rounded-md bg-indigo-600 px-4 py-2 font-medium text-white hover:bg-indigo-500 disabled:opacity-60"
      >
        {signupMutation.isPending ? 'Creating account…' : 'Create account'}
      </button>
      <p className="text-center text-sm text-slate-600">
        Already have an account?{' '}
        <Link to="/login" search={{ next }} className="font-medium text-indigo-600 hover:underline">
          Sign in
        </Link>
      </p>
    </form>
  )
}
