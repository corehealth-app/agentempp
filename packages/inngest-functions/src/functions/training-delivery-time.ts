const DAY_BY_ENGLISH_SHORT: Record<string, string> = {
  Sun: 'dom',
  Mon: 'seg',
  Tue: 'ter',
  Wed: 'qua',
  Thu: 'qui',
  Fri: 'sex',
  Sat: 'sab',
}

export function resolveTrainingDeliveryClock(
  referenceTimestamp: Date,
  timezone: string,
): { localHour: number; localDate: string; dayLabel: string } | null {
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      weekday: 'short',
      hour: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(referenceTimestamp)
    const value = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((part) => part.type === type)?.value
    const year = value('year')
    const month = value('month')
    const day = value('day')
    const weekday = value('weekday')
    const localHour = Number(value('hour'))
    const dayLabel = weekday ? DAY_BY_ENGLISH_SHORT[weekday] : null
    if (!year || !month || !day || !dayLabel || !Number.isInteger(localHour)) return null
    return { localHour, localDate: `${year}-${month}-${day}`, dayLabel }
  } catch {
    return null
  }
}
