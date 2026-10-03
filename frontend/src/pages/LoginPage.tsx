import { useEffect, useRef } from "react"
import { useNavigate } from "react-router-dom"
import { useAuth } from "@/auth/AuthProvider"

export default function LoginPage() {
  const { idToken, isLoading } = useAuth()
  const navigate = useNavigate()
  // renderButtonはGoogleが用意した関数で、渡されたDOM要素に対してReactを介さず直接HTMLを
  // 書き込んでボタンを作る。useStateではなくuseRefで実際のDOM要素そのものへの参照を持つ必要がある
  const buttonRef = useRef<HTMLDivElement>(null)

  // GISの初期化が終わったら、「Googleでログイン」ボタンを描画する
  useEffect(() => {
    if (!isLoading && buttonRef.current && window.google) {
      window.google.accounts.id.renderButton(buttonRef.current, {
        theme: "outline",
        size: "large",
      })
    }
  }, [isLoading])

  // ログインが完了したら（idTokenが手に入ったら）集計画面に移動する
  useEffect(() => {
    if (idToken) {
      navigate("/summary")
    }
  }, [idToken, navigate])

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted p-4">
      <div className="w-full max-w-sm rounded-lg border bg-card p-8 text-center shadow-sm">
        <h1 className="text-xl font-bold">コストデータ取込・分析</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Googleアカウントでログインしてください
        </p>
        <div className="mt-6 flex justify-center" ref={buttonRef} />
      </div>
    </div>
  )
}
