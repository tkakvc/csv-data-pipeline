import { useRef, type DragEvent } from "react"

type Props = {
  onFileSelect: (file: File) => void
}

export function FileDropZone({ onFileSelect }: Props) {
  const inputRef = useRef<HTMLInputElement>(null)

  // 【優先度低】ドラッグ＆ドロップの定型処理。dataTransfer.files[0]で1つ目のファイルを取り出し、
  // 存在すればonFileSelectに渡すだけ。preventDefaultはブラウザ標準の「ファイルを開く」動作を止めるため
  function handleDrop(e: DragEvent<HTMLDivElement>) {
    e.preventDefault()
    const file = e.dataTransfer.files[0]
    if (file) onFileSelect(file)
  }

  // 【優先度低】onDrop/onDragOver/onClickはonClickと同じ「イベント名→関数」の定型パターン
  return (
    <div
      onDrop={handleDrop}
      onDragOver={(e) => e.preventDefault()}
      onClick={() => inputRef.current?.click()}
      className="cursor-pointer rounded border-2 border-dashed p-8 text-center"
    >
      <input
        ref={inputRef}
        type="file"
        accept=".csv"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0]
          if (file) onFileSelect(file)
        }}
      />
      ここにCSVファイルをドラッグ＆ドロップ、またはクリックして選択
    </div>
  )
}
