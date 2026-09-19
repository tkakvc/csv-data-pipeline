import type { AxiosInstance } from "axios"

// 9-3の「状態（State）」で定義したSummaryItem型
export type SummaryItem = {
  usageMonth: string
  departmentCode: string
  departmentName: string
  accountCategory: string
  totalAmount: number
}

// 【優先度低】axiosでGETを叩いてdata.itemsを返すだけの定型的なAPI呼び出し
export async function fetchSummary(client: AxiosInstance, month?: string): Promise<SummaryItem[]> {
  const res = await client.get<{ items: SummaryItem[] }>("/summary", { params: month ? { month } : {} })
  return res.data.items
}
