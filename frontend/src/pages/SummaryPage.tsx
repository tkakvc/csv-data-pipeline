import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { useApiClient } from "@/api/client"
import { fetchSummary } from "@/api/summary"
import { MonthFilter } from "@/components/MonthFilter"
import { SummaryTable } from "@/components/SummaryTable"

export default function SummaryPage() {
  const [month, setMonth] = useState("")
  const client = useApiClient()

  // 【面接で説明できるようにする】9-3処理フロー2番：TanStack Queryは「queryKeyの中身が
  // 変わったら自動で再取得する」という仕組みを持つ。monthをqueryKeyの配列に含めているため、
  // MonthFilterでmonthが変わるたびに、自分でuseEffect等を書かなくても再取得が走る
  const { data, isLoading, isError } = useQuery({
    queryKey: ["summary", month],
    queryFn: () => fetchSummary(client, month || undefined),
  })

  // 【優先度低】ここから下はisLoading/isError/dataの状態に応じて表示を出し分けるだけのJSX
  return (
    <div className="mx-auto max-w-3xl p-6">
      <h1 className="mb-4 text-2xl font-bold">集計結果</h1>
      <MonthFilter value={month} onChange={setMonth} />

      {isLoading && <p className="mt-4">読み込み中...</p>}
      {isError && <p className="mt-4 text-destructive">取得に失敗しました</p>}
      {data && data.length === 0 && <p className="mt-4">まだCSVがアップロードされていません</p>}
      {data && data.length > 0 && (
        <div className="mt-4">
          <SummaryTable items={data} />
        </div>
      )}
    </div>
  )
}
