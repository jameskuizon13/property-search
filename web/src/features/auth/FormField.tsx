import type { InputHTMLAttributes } from 'react'

type Props = InputHTMLAttributes<HTMLInputElement> & {
  label: string
  name: string
  errors?: string[]
}

export function FormField({ label, name, errors, ...input }: Props) {
  const errorId = `${name}-error`
  const hasError = !!errors?.length
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="block text-sm font-medium text-slate-700">
        {label}
      </label>
      <input
        id={name}
        name={name}
        aria-invalid={hasError || undefined}
        aria-describedby={hasError ? errorId : undefined}
        className="block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 focus:outline-none aria-invalid:border-red-500"
        {...input}
      />
      {hasError && (
        <p id={errorId} className="text-sm text-red-600">
          {errors.join(', ')}
        </p>
      )}
    </div>
  )
}
