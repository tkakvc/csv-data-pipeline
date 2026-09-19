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

  // 【優先度低】GISがbuttonRefの中に直接ボタンを描画するための空のdivを置いているだけ
  return (
    <div className="flex min-h-screen items-center justify-center">
      <div ref={buttonRef} />
    </div>
  )
}
