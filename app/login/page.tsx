import { LoginForm } from './LoginForm'

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ inactive?: string }> }) {
  const { inactive } = await searchParams
  return (
    <main className="login">
      <div className="card">
        <h1>Finance Approval Portal</h1>
        <p className="muted">Sign in with the account your Admin created for you.</p>
        {inactive && <p className="msg error">Your account is inactive. Ask an Admin to turn it back on.</p>}
        <LoginForm />
      </div>
    </main>
  )
}
