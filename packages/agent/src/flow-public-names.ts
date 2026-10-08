/**
 * Flow only (app Performe AI): the names the app never shows.
 *
 * The method of the calculation rules is called "MPP" (Muscular Power Plant)
 * and was written by a physician. Both are internal references: the app's
 * public name is Performe AI and its assistant is Flow. The rules loaded from
 * the database and the manual excerpts retrieved for a turn still carry those
 * names, so the model can repeat them.
 *
 * Two layers, both on the Flow path only (processAuthenticatedMessage):
 *  1. the instruction in mobileFlowSystemPolicy (pipeline.ts) is absolute;
 *  2. `projectFlowPublicNames` is the deterministic last line of defence on
 *     the text the app receives.
 *
 * The projection is a CLOSED VOCABULARY with structural guards. It replaces
 * the spellings listed below and nothing else; it reads no wording around a
 * name to guess what the sentence means (no "signature", no "vocative"). A
 * name outside the list goes through untouched and is left to the instruction.
 *
 * (a) The method → "Performe AI"
 *     - "MPP" and "MPPs", in any case;
 *     - the capital forms written with dots or spaces: "M.P.P.", "M. P. P.",
 *       "M P P";
 *     - "Muscular Power Plant", in any case, with spaces, non-breaking spaces,
 *       hyphens or nothing between the words.
 *     - C2: "Usina muscular", the full brand expression, with the same case
 *       and joining variants. This expression additionally guards query,
 *       anchor and backslash glue, and preserves full URL spans; isolated
 *       words are not replaced.
 *     Never when the match is glued to `/`, `.`, `@`, `-`, `_` or to a word
 *     character: a segment of a URL, of a path or of an identifier is not the
 *     method's name ("https://example.com/mpp/guia", "docs/CALCULO-MPP.md",
 *     "MPP-2", "@mpp/agent", "mpp_mensal_v1" stay as written). A full stop
 *     that ends the sentence is not glue.
 *
 * (b) The physician → ONLY when the surname is present
 *     - optional title (Dr., Dr, Dra., Doutor, Doctor) + optional first name
 *       (Roberto, Robert) + "Menescal" → "Performe AI";
 *     - the same match right after one of the closed leads of a
 *       self-introduction ("sou o", "sou", "aqui é o", "aqui é", "me chamo",
 *       "meu nome é", "I am", "I'm", "this is") → "Flow".
 *     Never replaced: the title and/or the first name WITHOUT the surname
 *     ("Dr. Roberto", "Doutor Roberto", "Roberto": it may be the person using
 *     the app or someone else), and another person who carries the surname (a
 *     capitalised first name other than Roberto/Robert right before
 *     "Menescal": "Dra. Roberta Menescal", "Ana Menescal").
 *     The same glue guard of (a) applies.
 *
 * (c) Account guard: when the registered name of the account contains
 *     "Menescal" (case and accent insensitive), (b) is skipped for the turn —
 *     the name in the answer is, most likely, the person's own. (a) still
 *     applies.
 *
 * The legacy WhatsApp entry (processMessage) never calls this file.
 */

/** The persona name the shared rules carry. The Flow context swaps it for "Flow". */
export const LEGACY_PERSONA_NAME_PATTERN = /\bDr\.?\s+Robert(?:o)?(?:\s+Menescal)?\b/gi

export const FLOW_PUBLIC_PRODUCT_NAME = 'Performe AI'
export const FLOW_PUBLIC_ASSISTANT_NAME = 'Flow'

// ── Structural guards ───────────────────────────────────────────────────────
const WORD = String.raw`\p{L}\p{N}_`
/** Not glued, on the left, to a word character or to `/ . @ -`. */
const NOT_GLUED_BEFORE = String.raw`(?<![${WORD}/.@\-])`
/**
 * Not glued, on the right, to a word character or to `/ @ -`, nor to a dot
 * that continues into a word ("mpp.example.com", "MPP.md"). A dot followed by
 * a space, by other punctuation or by the end of the text ends a sentence.
 */
const NOT_GLUED_AFTER = String.raw`(?![${WORD}/@\-])(?!\.[${WORD}])`

// ── (a) The method ──────────────────────────────────────────────────────────
/** A space or a non-breaking space. */
const GAP = String.raw`[ \u00A0]`
/** "M.P.P.", "M. P. P." (the last dot is captured apart) and "M P P": capitals only. */
const METHOD_SPELLED_OUT = new RegExp(
  String.raw`${NOT_GLUED_BEFORE}(?:M\.${GAP}?P\.${GAP}?P(\.?)|M${GAP}P${GAP}P)${NOT_GLUED_AFTER}`,
  'gu',
)
/** Spaces (non-breaking included), hyphens or nothing between the words. */
const JOIN = String.raw`[\s\-\u2010\u2011]*`
/** "MPP", "MPPs" and "Muscular Power Plant", in any case. */
const METHOD_NAME = new RegExp(
  `${NOT_GLUED_BEFORE}(?:MPPs?|Muscular${JOIN}Power${JOIN}Plant)${NOT_GLUED_AFTER}`,
  'giu',
)
/** C2 brand expression only; extra glue guards preserve URL queries/anchors. */
const MUSCULAR_BRAND_NAME = new RegExp(
  String.raw`(?<![${WORD}/\\.@\-?&#=])Usina${JOIN}Muscular(?![${WORD}/\\@\-&#=])(?!\?[${WORD}])(?!\.[${WORD}])`,
  'giu',
)
/** C2 only: URL/path delimiters (including relative link targets) are not prose. */
const BRAND_URL_SPAN = /(?:[a-z][a-z0-9+.-]*:\/\/|www\.|[a-z]:\\|\.?\.?\/|(?<=\]\())[^\s<>"`]+/giu
/**
 * The last dot of "M.P.P." belongs to the abbreviation when the sentence goes
 * on (other punctuation, a closing mark, or a lower-case word follows): it
 * goes with the name. Anywhere else it is also the full stop, and stays.
 */
const SENTENCE_GOES_ON = /^(?:[,;:!?…)\]"”'’]|[ \t\u00A0]+\p{Ll})/u

// ── (b) The physician ───────────────────────────────────────────────────────
const TITLE = String.raw`(?:Dr\.\s*|Dra\.\s*|(?:Dr|Doutor|Doctor)\s+)`
const FIRST_NAME = '(?:Roberto|Robert)'
/** Group 1: the title, when written. Group 2: the first name, when written. */
const PHYSICIAN = new RegExp(
  String.raw`${NOT_GLUED_BEFORE}(${TITLE})?(${FIRST_NAME}\s+)?Menescal${NOT_GLUED_AFTER}`,
  'giu',
)
/** Title + first name, and no surname after it: seen, counted, never replaced. */
const TITLE_AND_FIRST_NAME_ONLY = new RegExp(
  String.raw`${NOT_GLUED_BEFORE}${TITLE}${FIRST_NAME}(?![${WORD}])(?!\s+Menescal(?![${WORD}]))`,
  'giu',
)

/** The closed list of leads of a self-introduction (pt-BR and en). */
const SELF_INTRODUCTION_LEAD = String.raw`(?:sou\s+o|sou|aqui\s+é\s+o|aqui\s+é|me\s+chamo|meu\s+nome\s+é|I\s+am|I['’]m|this\s+is)`
/** The lead right before the name (emphasis marks of Markdown may sit between). */
const LEAD_BEFORE = new RegExp(
  String.raw`(?<![${WORD}])(${SELF_INTRODUCTION_LEAD})\s+\*{0,2}$`,
  'iu',
)
/** "Não sou o …": the name is denied, not claimed. It is not an introduction. */
const NEGATION_BEFORE = new RegExp(String.raw`(?<![${WORD}])(?:não|nao|nem|nunca|jamais)\s+$`, 'iu')
/**
 * A capitalised word of two letters or more right before the surname, on the
 * same line and with only spaces between: someone's first name. "O Menescal"
 * is not one (a single letter is not a name), nor is the last word of the
 * sentence before ("Entendi. Menescal …": the full stop is in between).
 */
const CAPITALISED_NAME_BEFORE = new RegExp(
  String.raw`(?<![${WORD}])(\p{Lu}[\p{L}\p{M}'’]+)[ \t\u00A0]+$`,
  'u',
)
const PHYSICIAN_FIRST_NAME = new RegExp(`^${FIRST_NAME}$`, 'iu')

export interface FlowPublicNamesOptions {
  /**
   * The registered name of the account (users.name). When it contains
   * "Menescal", the physician's name is not replaced in this answer.
   */
  accountName?: string | null
}

export interface FlowPublicNames {
  text: string
  /** Occurrences replaced, by kind. Numbers only: they go to telemetry. */
  method: number
  personaSelf: number
  personaOther: number
  /** Title + first name without the surname: SEEN and NOT replaced. */
  personaFirstNameOnly: number
}

/** "Menescal" in a registered name, whatever the case and the accents. */
export function accountNameCarriesPhysicianSurname(name: string | null | undefined): boolean {
  if (!name) return false
  return name.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().includes('menescal')
}

/**
 * Replaces, in an answer of the Flow, the method's names by "Performe AI" and
 * the physician's full name by "Flow" where the model introduced itself by it
 * (by "Performe AI" anywhere else). An answer with none of the spellings of
 * the closed vocabulary comes back as the very same string.
 */
export function projectFlowPublicNames(
  text: string,
  options: FlowPublicNamesOptions = {},
): FlowPublicNames {
  let method = 0
  let personaSelf = 0
  let personaOther = 0
  let personaFirstNameOnly = 0
  let projected = text

  // Protect spans in the original text, before legacy projections can change
  // their offsets or introduce spaces. The legacy replacements stay intact.
  const brandUrls = Array.from(text.matchAll(BRAND_URL_SPAN), (match) => ({
    start: match.index,
    end: match.index + match[0].length,
  }))
  projected = projected.replace(MUSCULAR_BRAND_NAME, (match: string, offset: number) => {
    if (brandUrls.some((url) => offset < url.end && offset + match.length > url.start)) {
      return match
    }
    method += 1
    return FLOW_PUBLIC_PRODUCT_NAME
  })

  if (!accountNameCarriesPhysicianSurname(options.accountName)) {
    personaFirstNameOnly = Array.from(text.matchAll(TITLE_AND_FIRST_NAME_ONLY)).length
    projected = projected.replace(
      PHYSICIAN,
      (
        match: string,
        title: string | undefined,
        firstName: string | undefined,
        offset: number,
        whole: string,
      ) => {
        const before = whole.slice(0, offset)
        const lead = LEAD_BEFORE.exec(before)
        if (lead && !NEGATION_BEFORE.test(before.slice(0, lead.index))) {
          personaSelf += 1
          return FLOW_PUBLIC_ASSISTANT_NAME
        }
        // The surname alone, after someone else's first name: another person.
        // Left exactly as written.
        if (!lead && !title && !firstName) {
          const name = CAPITALISED_NAME_BEFORE.exec(before)?.[1]
          if (name && !PHYSICIAN_FIRST_NAME.test(name)) return match
        }
        personaOther += 1
        return FLOW_PUBLIC_PRODUCT_NAME
      },
    )
  }

  projected = projected.replace(
    METHOD_SPELLED_OUT,
    (match: string, lastDot: string | undefined, offset: number, whole: string) => {
      method += 1
      if (!lastDot) return FLOW_PUBLIC_PRODUCT_NAME
      const goesOn = SENTENCE_GOES_ON.test(whole.slice(offset + match.length))
      return goesOn ? FLOW_PUBLIC_PRODUCT_NAME : `${FLOW_PUBLIC_PRODUCT_NAME}.`
    },
  )
  projected = projected.replace(METHOD_NAME, () => {
    method += 1
    return FLOW_PUBLIC_PRODUCT_NAME
  })
  if (method + personaSelf + personaOther === 0) {
    return { text, method: 0, personaSelf: 0, personaOther: 0, personaFirstNameOnly }
  }
  return { text: projected, method, personaSelf, personaOther, personaFirstNameOnly }
}
