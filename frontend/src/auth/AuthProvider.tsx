import { createContext, useContext, useEffect, useState, type ReactNode } from "react"

type AuthContextValue = {
  idToken: string | null
  isLoading: boolean
}

// 【抑えておく】createContextは「値を、間のコンポーネントを飛び越して下の階層に配る」仕組み
const AuthContext = createContext<AuthContextValue>({ idToken: null, isLoading: true })

// 他のコンポーネントから「今ログイン中か・IDトークンは何か」を読むためのフック
// eslint-disable-next-line react-refresh/only-export-components -- Provider本体とセットで使うため同じファイルに置く（React Contextの一般的な書き方）
export function useAuth() {
  return useContext(AuthContext)
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [idToken, setIdToken] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    // 【面接で説明できるようにする】GISが提供するのは「ログイン画面（ポップアップ等）を出して、
    // 成功したらJWT形式のIDトークンを返してくれる」ところまで。initialize()はその窓口を開く処理で、
    // client_idでどのOAuthクライアントとして認証するかを指定し、callbackで結果の受け取り方を登録する
    function initialize() {
      window.google.accounts.id.initialize({
        client_id: import.meta.env.VITE_GOOGLE_OAUTH_CLIENT_ID,
        // ログイン成功時、GISがこの関数を呼び出し、response.credentialにIDトークン（JWT）を渡してくる
        callback: (response: { credential: string }) => {
          setIdToken(response.credential)
        },
      })
      setIsLoading(false)
    }

    // 【面接で説明できるようにする】index.htmlで読み込んでいるGISのスクリプトはasync（非同期）なので、
    // このReactコンポーネントの方が先に描画され、window.googleがまだ存在しない可能性がある。
    // そのため「すでに読み込み済みか」を毎回チェックし、未読み込みならload完了を待ってから初期化する
    //
    // 【面接で説明できるようにする】"load"イベントとは：今開いているページに必要な全ファイル
    // （HTML本体・CSS・画像・<script>タグの中身）のダウンロードが「全部」終わった瞬間に発生する
    // イベント。Reactが画面を描画するタイミング（HTMLの解析が終わった時点）より後になることがある。
    //   0ms   HTML読み込み開始
    //   50ms  HTML解析完了 → Reactが描画開始（この時点でGISのscriptはまだDL中のことがある）
    //   200ms 全リソースのDL完了 → ここで初めて"load"イベントが発生
    // なのでelse側では「今すぐは呼べないので、"load"イベントが起きたら呼んでね」と予約している
    if (window.google?.accounts?.id) {
      initialize()
    } else {
      window.addEventListener("load", initialize)
      // 【面接で説明できるようにする】クリーンアップ：コンポーネントが消えた後に"load"イベントが
      // 発生すると、既に無いコンポーネントの関数が呼ばれてエラー・警告の原因になる。
      // removeEventListenerで予約を取り消しておくことでそれを防ぐ
      return () => window.removeEventListener("load", initialize)
    }
  }, [])

  return <AuthContext.Provider value={{ idToken, isLoading }}>{children}</AuthContext.Provider>
}
