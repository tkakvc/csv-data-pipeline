import type { ReactNode } from "react"
import { Navigate, Route, Routes } from "react-router-dom"
import LoginPage from "./pages/LoginPage"
import UploadPage from "./pages/UploadPage"
import SummaryPage from "./pages/SummaryPage"
import { useAuth } from "./auth/AuthProvider"

// 【面接で説明できるようにする】未ログイン状態でアクセスされたら/loginに飛ばす、画面を包むための部品。
// なぜこのパターンが必要か：react-router-domには「認証必須ルート」を宣言するだけの標準機能が
// 無いため、自分で「中身を表示する前にチェックする」コンポーネントを作って各ルートを包む必要がある
function RequireAuth({ children }: { children: ReactNode }) {
  const { idToken, isLoading } = useAuth()
  // 【面接で説明できるようにする】isLoadingを先にチェックする理由：GISの初期化が終わる前は
  // idTokenがnullなだけで「本当に未ログイン」とは限らない。ここを省くと、ページ再読み込みの
  // たびに一瞬だけ/loginに飛ばされてすぐ戻る、という誤動作が起きる
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
      {/* 【抑えておく】path="*"はどのルートにも一致しなかった場合の受け皿 */}
      <Route path="*" element={<Navigate to="/summary" replace />} />
    </Routes>
  )
}
