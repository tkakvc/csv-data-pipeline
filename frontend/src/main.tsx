import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { BrowserRouter } from "react-router-dom"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import App from "./App"
import { AuthProvider } from "./auth/AuthProvider"
import "./index.css"

// QueryClientは取得データのキャッシュを保持する入れ物。1個作って全体で使い回す
const queryClient = new QueryClient()

// Provider（BrowserRouter・QueryClientProvider・AuthProvider）を重ねる順番には意味があり、
// 外側のProviderが提供する機能は内側のどこからでも使える。AuthProviderが一番内側にあるのは、
// それより外のProvider（Router・Query）がAuthProviderの中身（idToken）に依存していないため
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
