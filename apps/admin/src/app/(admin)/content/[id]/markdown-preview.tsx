'use client'

import {
  type ContentMarkdownBlock,
  type ContentMarkdownInline,
  validateContentMarkdown,
} from '@mpp/core'
import type { ReactNode } from 'react'

export function MarkdownPreview({ markdown }: { markdown: string }) {
  try {
    const content = validateContentMarkdown(markdown)
    return (
      <div className="min-h-[360px] min-w-0 rounded-md border border-border bg-background p-5">
        <div className="prose prose-sm max-w-none break-words text-foreground dark:prose-invert">
          <RenderBlocks blocks={content.blocks} />
        </div>
        <p className="mt-6 border-t border-border pt-3 font-mono text-[10px] text-muted-foreground">
          {content.wordCount.toLocaleString('pt-BR')} palavras · {content.readingTimeMinutes} min
        </p>
      </div>
    )
  } catch {
    return (
      <div className="flex min-h-[360px] items-center justify-center rounded-md border border-dashed border-border p-6 text-center">
        <p className="max-w-sm text-sm text-muted-foreground">
          A previa sera exibida quando o Markdown estiver valido.
        </p>
      </div>
    )
  }
}

function RenderBlocks({ blocks }: { blocks: readonly ContentMarkdownBlock[] }) {
  return keyedNodes(blocks).map(({ key, value }) => <RenderBlock key={key} block={value} />)
}

function RenderBlock({ block }: { block: ContentMarkdownBlock }): ReactNode {
  if (block.type === 'paragraph')
    return (
      <p>
        <RenderInlines inlines={block.children} />
      </p>
    )
  if (block.type === 'heading') {
    return block.level === 2 ? (
      <h2>
        <RenderInlines inlines={block.children} />
      </h2>
    ) : (
      <h3>
        <RenderInlines inlines={block.children} />
      </h3>
    )
  }
  if (block.type === 'blockquote')
    return (
      <blockquote>
        <RenderBlocks blocks={block.children} />
      </blockquote>
    )
  const List = block.ordered ? 'ol' : 'ul'
  return (
    <List>
      {keyedNodes(block.items).map(({ key, value }) => {
        return (
          <li key={key}>
            <RenderBlocks blocks={value} />
          </li>
        )
      })}
    </List>
  )
}

function RenderInlines({ inlines }: { inlines: readonly ContentMarkdownInline[] }) {
  return keyedNodes(inlines).map(({ key, value }) => <RenderInline key={key} inline={value} />)
}

function RenderInline({ inline }: { inline: ContentMarkdownInline }): ReactNode {
  if (inline.type === 'text') return inline.value
  if (inline.type === 'strong')
    return (
      <strong>
        <RenderInlines inlines={inline.children} />
      </strong>
    )
  if (inline.type === 'emphasis')
    return (
      <em>
        <RenderInlines inlines={inline.children} />
      </em>
    )
  if (!('url' in inline) || !isSafeHttpsUrl(inline.url)) {
    return <RenderInlines inlines={inline.children} />
  }
  return (
    <a href={inline.url} target="_blank" rel="noopener noreferrer">
      <RenderInlines inlines={inline.children} />
    </a>
  )
}

function isSafeHttpsUrl(value: string): boolean {
  try {
    return new URL(value).protocol === 'https:'
  } catch {
    return false
  }
}

function keyedNodes<T>(values: readonly T[]): Array<{ key: string; value: T }> {
  const occurrences = new Map<string, number>()
  return values.map((value) => {
    const fingerprint = JSON.stringify(value)
    const occurrence = (occurrences.get(fingerprint) ?? 0) + 1
    occurrences.set(fingerprint, occurrence)
    return { key: `${fingerprint}:${occurrence}`, value }
  })
}
