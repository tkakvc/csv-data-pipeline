import { NavLink, useNavigate } from "react-router-dom"
import { useAuth } from "@/auth/AuthProvider"

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  `rounded px-3 py-1.5 text-sm font-medium ${
    isActive ? "bg-primary text-primary-foreground" : "text-foreground hover:bg-accent"
  }`

// ログイン後の画面（/upload・/summary）を行き来するためのナビゲーション。
// これが無いと、ログイン後は常に/summaryに固定されてしまい、/uploadへ移動する手段が無くなる。
export function AppHeader() {
  const { logout } = useAuth()
  const navigate = useNavigate()

  function handleLogout() {
    logout()
    navigate("/login")
  }

  return (
    <header className="border-b">
      <div className="mx-auto flex max-w-3xl items-center gap-2 p-4">
        <h1 className="mr-auto text-lg font-bold">コストデータ取込・分析</h1>
        <nav className="flex gap-2">
          <NavLink to="/upload" className={navLinkClass}>
            アップロード
          </NavLink>
          <NavLink to="/summary" className={navLinkClass}>
            集計結果
          </NavLink>
        </nav>
        <button
          onClick={handleLogout}
          className="rounded px-3 py-1.5 text-sm font-medium text-muted-foreground hover:bg-accent"
        >
          ログアウト
        </button>
      </div>
    </header>
  )
}
