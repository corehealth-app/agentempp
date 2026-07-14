export interface MealToolResultLike {
  success?: boolean
  error?: unknown
  message?: unknown
}

export function requireSuccessfulMealToolResult(result: MealToolResultLike | null): void {
  if (result?.success === true) return
  const code = typeof result?.error === 'string' ? result.error : 'meal_tool_rejected'
  const detail = typeof result?.message === 'string' ? `: ${result.message}` : ''
  throw new Error(`${code}${detail}`)
}
