import axios from "axios"
import { useMemo } from "react"
import { useAuth } from "@/auth/AuthProvider"

// idTokenが変わった時だけ作り直すよう、axios.create()をuseMemoで囲んでいる。囲まないと
// 毎回のレンダリングで新しいaxiosインスタンスが作られ、これに依存するuseEffect等が無駄に再実行される
export function useApiClient() {
  const { idToken } = useAuth()

  return useMemo(
    () =>
      axios.create({
        baseURL: import.meta.env.VITE_API_BASE_URL,
        headers: idToken ? { Authorization: `Bearer ${idToken}` } : {},
      }),
    [idToken],
  )
}
