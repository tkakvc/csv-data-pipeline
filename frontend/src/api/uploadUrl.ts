import type { AxiosInstance } from "axios"

type UploadUrlResponse = {
  url: string
  key: string
  expiresIn: number
}

// 【優先度低】axiosでPOSTを叩いてdataを返すだけの定型的なAPI呼び出し
export async function requestUploadUrl(client: AxiosInstance): Promise<UploadUrlResponse> {
  const res = await client.post<UploadUrlResponse>("/upload-url")
  return res.data
}

// 【面接で説明できるようにする】9-2の処理フロー3番：進捗を取得できるXMLHttpRequestで
// S3に直接PUTする（fetchでは進捗が取れない。理由は9-2の補足参照）
export function putFileToS3(url: string, file: File, onProgress: (percent: number) => void): Promise<void> {
  // 【抑えておく】XMLHttpRequestはコールバック形式のAPIなので、async/awaitで使えるよう
  // Promiseで包んでいる
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
