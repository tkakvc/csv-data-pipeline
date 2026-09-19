// 【AI任せでOK】StrictMode・createRootは、Viteのreact-tsテンプレートが最初から生成する定型のエントリーポイント
import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { BrowserRouter } from "react-router-dom"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import App from "./App"
import { AuthProvider } from "./auth/AuthProvider"
import "./index.css"

// 【抑えておく】QueryClientは「取得データのキャッシュを保持する入れ物」。1個作って全体で使い回す
const queryClient = new QueryClient()

// 【面接で説明できるようにする】Provider（BrowserRouter・QueryClientProvider・AuthProvider）を
// 重ねる順番に意味がある。外側のProviderが提供する機能は、内側のどこからでも使える。
// AuthProviderが一番内側にあるのは、それより外のProvider（Router・Query）はAuthProviderの
// 中身（idToken）に依存していないため。逆に、もしRouterの中でAuthの状態を見て画面遷移させたい
// 場合（今回のRequireAuthがまさにそう）は、AuthProviderがBrowserRouterより内側でも外側でも
// 動作上は問題ない（useAuthはcontextを辿るだけなので、木構造のどこにいても親を辿れる）
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <App />
        </AuthProvider>
      </QueryClientProvider>
    </BrowserRouter>
  </StrictMode>,
)
