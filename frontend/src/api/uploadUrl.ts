import type { AxiosInstance } from "axios"

type UploadUrlResponse = {
  url: string
  key: string
  expiresIn: number
}

export async function requestUploadUrl(client: AxiosInstance): Promise<UploadUrlResponse> {
  const res = await client.post<UploadUrlResponse>("/upload-url")
  return res.data
}

// 進捗を取得できるXMLHttpRequestでS3に直接PUTする（fetchでは進捗イベントを取れないため）
export function putFileToS3(url: string, file: File, onProgress: (percent: number) => void): Promise<void> {
  // XMLHttpRequestはコールバック形式のAPIなので、async/awaitで使えるようPromiseで包んでいる
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open("PUT", url)
    xhr.setRequestHeader("Content-Type", "text/csv")
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100))
    }
    xhr.onload = () => (xhr.status < 300 ? resolve() : reject(new Error("アップロードに失敗しました")))
    xhr.onerror = () => reject(new Error("アップロードに失敗しました"))
    xhr.send(file)
  })
}
