import { createContext, useContext, useEffect, useState, type ReactNode } from "react"

type AuthContextValue = {
  idToken: string | null
  isLoading: boolean
  logout: () => void
}

// sessionStorageに保存するキー。タブを閉じるまでの間だけ、リロードしてもログイン状態を保つ。
const STORAGE_KEY = "idToken"

// createContextは、値を間のコンポーネントを飛び越して下の階層に配る仕組み
const AuthContext = createContext<AuthContextValue>({ idToken: null, isLoading: true, logout: () => {} })

// 他のコンポーネントから「今ログイン中か・IDトークンは何か」を読むためのフック
// eslint-disable-next-line react-refresh/only-export-components -- Provider本体とセットで使うため同じファイルに置く（React Contextの一般的な書き方）
export function useAuth() {
  return useContext(AuthContext)
}

export function AuthProvider({ children }: { children: ReactNode }) {
  // 初期値をsessionStorageから読むことで、リロード直後でも前回ログイン済みだった状態を復元する。
  // トークンの期限切れはここでは検証しない（期限切れならAPI呼び出し時に401が返る）。
  const [idToken, setIdToken] = useState<string | null>(() => sessionStorage.getItem(STORAGE_KEY))
  const [isLoading, setIsLoading] = useState(true)

  function handleIdToken(token: string) {
    setIdToken(token)
    sessionStorage.setItem(STORAGE_KEY, token)
  }

  function logout() {
    setIdToken(null)
    sessionStorage.removeItem(STORAGE_KEY)
  }

  useEffect(() => {
    // GISが提供するのは「ログイン画面（ポップアップ等）を出して、成功したらJWT形式のIDトークンを
    // 返してくれる」ところまで。initialize()はその窓口を開く処理で、client_idでどのOAuthクライアント
    // として認証するかを指定し、callbackで結果の受け取り方を登録する
    function initialize() {
      window.google.accounts.id.initialize({
        client_id: import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID,
        // ログイン成功時、GISがこの関数を呼び出し、response.credentialにIDトークン（JWT）を渡してくる
        callback: (response: { credential: string }) => {
          handleIdToken(response.credential)
        },
      })
      setIsLoading(false)
    }

    // index.htmlで読み込んでいるGISのスクリプトはasync（非同期）なので、Reactコンポーネントの方が
    // 先に描画され、window.googleがまだ存在しない可能性がある。そのため読み込み済みかを毎回チェックし、
    // 未読み込みならwindowの"load"イベント（全リソースの読み込み完了時に発火）を待ってから初期化する
    if (window.google?.accounts?.id) {
      initialize()
    } else {
      window.addEventListener("load", initialize)
      // コンポーネントが消えた後にloadイベントが発生すると、既に無いコンポーネントの関数が
      // 呼ばれてエラーの原因になるため、removeEventListenerで予約を取り消す
      return () => window.removeEventListener("load", initialize)
    }
  }, [])

  return <AuthContext.Provider value={{ idToken, isLoading, logout }}>{children}</AuthContext.Provider>
}
