import { useEffect, useRef } from "react"
import { useNavigate } from "react-router-dom"
import { useAuth } from "@/auth/AuthProvider"

export default function LoginPage() {
  const { idToken, isLoading } = useAuth()
  const navigate = useNavigate()
  // 【面接で説明できるようにする】renderButton（下のuseEffect内）はGoogleが用意した関数で、
  // 渡されたDOM要素（ブラウザが実際に画面に表示している本物の<div>）に対して、Reactを介さず
  // 直接HTMLを書き込んでボタンを作る。useStateで値を管理してもReactが検知できる変更ではないため、
  // useRefで本物のDOM要素そのものへの参照を持ち、それをrenderButtonにそのまま渡す必要がある
  const buttonRef = useRef<HTMLDivElement>(null)

  // GISの初期化が終わったら、「Googleでログイン」ボタンを描画する
  useEffect(() => {
    if (!isLoading && buttonRef.current && window.google) {
      // 【抑えておく】theme・sizeはボタンの見た目のオプション（好みで変更可）
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

  // 一般的なログイン画面の形（中央にカード、上にタイトルと説明、下にログインボタン）にしている。
  // buttonRefの中身自体はGISが直接書き込むので、囲んでいるdiv・見出し・説明文はただの装飾。
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
