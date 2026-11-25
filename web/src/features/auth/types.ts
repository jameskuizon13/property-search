// Mirrors the API's user roles. The server checks the role on every admin
// request; the UI only uses it to show or hide the admin link (Milestone 8).
export type Role = 'user' | 'admin'

export type User = {
  id: number
  email: string
  name: string
  role: Role
}
