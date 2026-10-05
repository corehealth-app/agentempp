/**
 * Símbolo aprovado do Performe AI ("Signal Spark").
 *
 * Os arquivos em /public/brand são cópias idênticas dos masters aprovados
 * (ver brand-symbol.md, ao lado): a imagem é usada como está, sem recolorir.
 * O nome do produto vem sempre como texto ao lado — o símbolo é decorativo
 * para leitor de tela (alt vazio).
 *
 * - `light`: sobre fundo claro (menu lateral, cabeçalho no celular, favicon).
 * - `negative`: sobre o fundo de marca escuro (coluna do login).
 */
export function BrandSymbol({
  variant,
  size,
  className,
}: {
  variant: 'light' | 'negative'
  size: number
  className?: string
}) {
  return (
    // biome-ignore lint/performance/noImgElement: o SVG aprovado é servido como está; next/image passaria a imagem pelo otimizador.
    <img
      src={`/brand/symbol-${variant}.svg`}
      alt=""
      aria-hidden="true"
      width={size}
      height={size}
      className={className}
      draggable={false}
    />
  )
}
