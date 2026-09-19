type Props = {
  value: string
  onChange: (month: string) => void
}

// 【優先度低】<input type="month">の値をそのまま親に返すだけの薄いラッパー
export function MonthFilter({ value, onChange }: Props) {
  return (
    <input type="month" value={value} onChange={(e) => onChange(e.target.value)} className="rounded border px-2 py-1" />
  )
}
