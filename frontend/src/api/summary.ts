import type { AxiosInstance } from "axios"

export type SummaryItem = {
  usageMonth: string
  departmentCode: string
  departmentName: string
  accountCategory: string
  totalAmount: number
}

export async function fetchSummary(client: AxiosInstance, month?: string): Promise<SummaryItem[]> {
  const res = await client.get<{ items: SummaryItem[] }>("/summary", { params: month ? { month } : {} })
  return res.data.items
}
