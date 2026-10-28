/** Exact decimal comparison for clinical cutoffs. JSON number spellings are
 * compared as rational values; no rounded BMI or floating-point epsilon can
 * turn equality at 18.5/25 into a value on the other side of the boundary. */
function decimal(value: number) {
  if (!Number.isFinite(value) || value <= 0) throw new RangeError('Invalid clinical body value')
  const [coefficient, exponent] = value.toString().toLowerCase().split('e')
  const [whole, fraction = ''] = (coefficient ?? '').split('.')
  const scale = fraction.length - Number(exponent ?? 0)
  const numerator = BigInt(`${whole}${fraction}`)
  return scale < 0
    ? { numerator: numerator * 10n ** BigInt(-scale), denominator: 1n }
    : { numerator, denominator: 10n ** BigInt(scale) }
}
export function clinicalBmiBelow(weightKg: number, heightCm: number, cutoff: number): boolean {
  const weight = decimal(weightKg),
    height = decimal(heightCm),
    limit = decimal(cutoff)
  return (
    weight.numerator * height.denominator ** 2n * limit.denominator * 10000n <
    weight.denominator * height.numerator ** 2n * limit.numerator
  )
}
