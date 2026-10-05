/**
 * The system's status answer ("STATUS PURO") as the app's chat shows it.
 *
 * The Flow reaches the same deterministic path as WhatsApp when the model
 * calls consulta_progresso for a plain status question, and got the WhatsApp
 * card: a pictograph per line, `**bold**` and `_(italic)_`. The app's bubble
 * prints the string as it is (FlowMessageBubble, Text(message.content)), so
 * the patient saw the asterisks and underscores.
 *
 * This is formatting only. The input is the finished WhatsApp text, so every
 * number, its order and its unit are the ones WhatsApp sends; nothing is
 * computed, rounded or added here. A line loses its leading pictograph and
 * its emphasis marks, and three labels take the wording the app's Today
 * screen uses for the same number (Localizable.xcstrings, pt-BR). The note of
 * the exercise line spells the block as that label does.
 */

/** Card label → the Today screen's label for the same number. */
const TODAY_LABELS: ReadonlyArray<readonly [card: string, today: string]> = [
  ['Restam:', 'Restam para comida:'], // today.energy.food-remaining
  ['Excedente:', 'Excesso alimentar:'], // today.energy.food-excess
  ['Bloco 7700:', 'Bloco 7.700:'], // today.block.title
]

/**
 * The exercise line's note names the block with the card's spelling ("7700")
 * while the block label right below it takes the Today screen's ("7.700"):
 * the note follows the label, so one answer has one spelling.
 */
const BLOCK_NOTE: readonly [card: string, plain: string] = [
  '(acelera o bloco 7700)',
  '(acelera o bloco 7.700)',
]

/** The pictograph that opens a card line, with its skin-tone/variation marks. */
const LEADING_PICTOGRAPH = /^\p{Extended_Pictographic}(?:\p{Emoji_Modifier}|\uFE0F)*\s+/u

export function flowPlainStatusText(card: string): string {
  return card
    .split('\n')
    .map((line) => {
      const plain = line
        .replace(LEADING_PICTOGRAPH, '')
        .replace(/\*\*/g, '')
        .replace(/_\(([^)\n]*)\)_/g, '($1)')
        .replace(BLOCK_NOTE[0], BLOCK_NOTE[1])
      const label = TODAY_LABELS.find(([cardLabel]) => plain.startsWith(cardLabel))
      return label ? `${label[1]}${plain.slice(label[0].length)}` : plain
    })
    .join('\n')
}
