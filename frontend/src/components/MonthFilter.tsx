type Props = {
  value: string
  onChange: (month: string) => void
}

export function MonthFilter({ value, onChange }: Props) {
  return (
    <input type="month" value={value} onChange={(e) => onChange(e.target.value)} className="rounded border px-2 py-1" />
  )
}
