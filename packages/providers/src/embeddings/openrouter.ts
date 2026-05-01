/**
 * Embeddings via OpenRouter — usa OpenAI text-embedding-3-large (3072 dims)
 * mas trunca para 1024 que é o que a tabela message_embeddings espera.
 */
import OpenAI from 'openai'

export interface EmbeddingsConfig {
  apiKey: string
  baseURL?: string
  model?: string // default 'openai/text-embedding-3-large'
  dimensions?: number // default 1024 (compatível com schema)
}

export class OpenRouterEmbeddings {
  private client: OpenAI
  private model: string
  private dimensions: number

  constructor(cfg: EmbeddingsConfig) {
    this.client = new OpenAI({
      apiKey: cfg.apiKey,
      baseURL: cfg.baseURL ?? 'https://openrouter.ai/api/v1',
    })
    this.model = cfg.model ?? 'openai/text-embedding-3-large'
    this.dimensions = cfg.dimensions ?? 1024
  }

  async embed(text: string): Promise<number[]> {
    const result = await this.client.embeddings.create({
      model: this.model,
      input: text,
      dimensions: this.dimensions,
    })
    const v = result.data[0]?.embedding
    if (!v) throw new Error('Embedding vazio')
    return v
  }

  async embedBatch(texts: string[]): Promise<number[][]> {
    if (texts.length === 0) return []
    const result = await this.client.embeddings.create({
      model: this.model,
      input: texts,
      dimensions: this.dimensions,
    })
    return result.data.map((d) => d.embedding)
  }
}
