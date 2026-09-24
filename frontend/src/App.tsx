import type { ReactNode } from "react"
import { Navigate, Route, Routes } from "react-router-dom"
import LoginPage from "./pages/LoginPage"
import UploadPage from "./pages/UploadPage"
import SummaryPage from "./pages/SummaryPage"
import { useAuth } from "./auth/AuthProvider"

// 未ログイン状態でアクセスされたら/loginに飛ばす、画面を包むための部品。
// react-router-domには「認証必須ルート」を宣言するだけの標準機能が無いため、
// 自分で「中身を表示する前にチェックする」コンポーネントを作って各ルートを包んでいる
function RequireAuth({ children }: { children: ReactNode }) {
  const { idToken, isLoading } = useAuth()
  // isLoadingを先にチェックしないと、GISの初期化が終わる前の一時的なidToken=nullを
  // 「未ログイン」と誤判定し、再読み込みのたびに一瞬/loginに飛ばされる不具合が起きる
  if (isLoading) return null
  if (!idToken) return <Navigate to="/login" replace />
  return <>{children}</>
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/upload"
        element={
          <RequireAuth>
            <UploadPage />
          </RequireAuth>
        }
      />
      <Route
        path="/summary"
        element={
          <RequireAuth>
            <SummaryPage />
          </RequireAuth>
        }
      />
      {/* path="*"はどのルートにも一致しなかった場合の受け皿 */}
      <Route path="*" element={<Navigate to="/summary" replace />} />
    </Routes>
  )
}
