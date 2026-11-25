import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, within, type RenderOptions } from '@testing-library/react'
import { Provider as JotaiProvider, createStore } from 'jotai'
import type { ReactElement, ReactNode } from 'react'

export function renderWithProviders(
  ui: ReactElement,
  { store = createStore(), ...options }: RenderOptions & { store?: ReturnType<typeof createStore> } = {},
) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  const Wrapper = ({ children }: { children: ReactNode }) => (
    <JotaiProvider store={store}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </JotaiProvider>
  )
  return { store, queryClient, ...render(ui, { wrapper: Wrapper, ...options }) }
}

/** Queries scoped to the toast region. */
export function toasts() {
  return within(screen.getByRole('list', { name: 'Notifications' }))
}
