import type { SummaryItem } from "@/api/summary"

type Props = {
  items: SummaryItem[]
}

// 【優先度低】itemsをmapでtrに変換して並べているだけの定型的な表描画
export function SummaryTable({ items }: Props) {
  return (
    <table className="w-full border-collapse text-left">
      <thead>
        <tr>
          <th className="border-b p-2">対象月</th>
          <th className="border-b p-2">部門名</th>
          <th className="border-b p-2">勘定科目</th>
          <th className="border-b p-2">合計金額</th>
        </tr>
      </thead>
      <tbody>
        {items.map((item, i) => (
          <tr key={i}>
            <td className="border-b p-2">{item.usageMonth}</td>
            <td className="border-b p-2">{item.departmentName}</td>
            <td className="border-b p-2">{item.accountCategory}</td>
            <td className="border-b p-2">¥{item.totalAmount.toLocaleString()}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
