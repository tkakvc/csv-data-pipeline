import { useState } from "react"
import { useApiClient } from "@/api/client"
import { requestUploadUrl, putFileToS3 } from "@/api/uploadUrl"
import { FileDropZone } from "@/components/FileDropZone"

// 【面接で説明できるようにする】9-2の「状態（State）」で定義した型をそのまま使う。
// booleanフラグ（isUploading・isSuccess等）を複数持つのではなく、「今どの状態か」を
// 1つのUnion型で表現している。理由：同時に有り得ない組み合わせ（例：uploading中かつ
// error）をそもそも型として表現できなくする（不正な状態を作れないようにする設計）
type UploadState =
  | { status: "idle" }
  | { status: "selected"; file: File }
  | { status: "requesting-url" }
  | { status: "uploading"; progress: number }
  | { status: "success" }
  | { status: "error"; message: string }

const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024

export default function UploadPage() {
  const [state, setState] = useState<UploadState>({ status: "idle" })
  const client = useApiClient()

  // 9-2処理フロー1番：拡張子・サイズをクライアント側でチェックする
  function handleFileSelect(file: File) {
    if (!file.name.endsWith(".csv")) {
      setState({ status: "error", message: "CSVファイルを選択してください" })
      return
    }
    if (file.size > MAX_FILE_SIZE_BYTES) {
      setState({ status: "error", message: "ファイルサイズは10MB以下にしてください" })
      return
    }
    setState({ status: "selected", file })
  }

  // 9-2処理フロー2〜5番
  async function handleUpload() {
    if (state.status !== "selected") return
    const file = state.file
    setState({ status: "requesting-url" })
    try {
      const { url } = await requestUploadUrl(client)
      setState({ status: "uploading", progress: 0 })
      await putFileToS3(url, file, (progress) => setState({ status: "uploading", progress }))
      setState({ status: "success" })
    } catch (e) {
      setState({ status: "error", message: e instanceof Error ? e.message : "アップロードに失敗しました" })
    }
  }

  // 【優先度低】ここから下はstate.statusの値に応じて表示を出し分けるだけのJSX
  return (
    <div className="mx-auto max-w-xl p-6">
      <h1 className="mb-4 text-2xl font-bold">CSVアップロード</h1>
      <FileDropZone onFileSelect={handleFileSelect} />

      {state.status === "selected" && (
        <p className="mt-2">
          {state.file.name}（{Math.round(state.file.size / 1024)}KB）
        </p>
      )}

      <button
        disabled={state.status !== "selected"}
        onClick={handleUpload}
        className="mt-4 rounded bg-primary px-4 py-2 text-primary-foreground disabled:opacity-50"
      >
        アップロード
      </button>

      {state.status === "uploading" && <progress value={state.progress} max={100} className="mt-4 w-full" />}
      {state.status === "success" && (
        <p className="mt-4">アップロードが完了しました。数分後に集計結果画面に反映されます。</p>
      )}
      {state.status === "error" && <p className="mt-4 text-destructive">{state.message}</p>}
    </div>
  )
}
