import axios from "axios"
import { useMemo } from "react"
import { useAuth } from "@/auth/AuthProvider"

// 【面接で説明できるようにする】idTokenが変わった時だけ作り直す（毎回のレンダリングで
// 作り直さないようuseMemoで囲む）。理由は下の補足参照
export function useApiClient() {
  const { idToken } = useAuth()

  return useMemo(
    () =>
      // 【抑えておく】axios.create()は「共通設定（baseURL・headers）を持った、専用のaxios」を作る書き方
      axios.create({
        baseURL: import.meta.env.VITE_API_BASE_URL,
        headers: idToken ? { Authorization: `Bearer ${idToken}` } : {},
      }),
    [idToken],
  )
}
