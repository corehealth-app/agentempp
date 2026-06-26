/**
 * Tests — vision-inflight-policy (audit 06-26 review HIGH 3 + MED 1).
 */
import { describe, expect, it } from 'vitest'
import { allMediaDone, pickMediaDoneEvents } from './vision-inflight-policy.js'

describe('pickMediaDoneEvents', () => {
  it('image → vision.analyzed + vision.download_failed', () => {
    expect(pickMediaDoneEvents('image')).toEqual([
      'vision.analyzed',
      'vision.download_failed',
    ])
  })

  it('audio → stt.transcribed + stt.failed', () => {
    expect(pickMediaDoneEvents('audio')).toEqual(['stt.transcribed', 'stt.failed'])
  })

  it('text/template/interactive → vazio (não é mídia)', () => {
    expect(pickMediaDoneEvents('text')).toEqual([])
    expect(pickMediaDoneEvents('template')).toEqual([])
    expect(pickMediaDoneEvents('interactive')).toEqual([])
    expect(pickMediaDoneEvents('')).toEqual([])
  })
})

describe('allMediaDone (gate multimodal MED 1)', () => {
  it('só foto + vision done → flush OK', () => {
    expect(
      allMediaDone(['image'], { hasVisionDone: true, hasSttDone: false }),
    ).toBe(true)
  })

  it('só foto + vision pending → bloqueia', () => {
    expect(
      allMediaDone(['image'], { hasVisionDone: false, hasSttDone: false }),
    ).toBe(false)
  })

  it('só áudio + STT done → flush OK', () => {
    expect(
      allMediaDone(['audio'], { hasVisionDone: false, hasSttDone: true }),
    ).toBe(true)
  })

  it('só áudio + STT pending → bloqueia', () => {
    expect(
      allMediaDone(['audio'], { hasVisionDone: false, hasSttDone: false }),
    ).toBe(false)
  })

  it('foto + áudio + AMBOS done → flush OK', () => {
    expect(
      allMediaDone(['image', 'audio'], { hasVisionDone: true, hasSttDone: true }),
    ).toBe(true)
  })

  it('foto + áudio + só vision done → bloqueia (STT em vôo)', () => {
    expect(
      allMediaDone(['image', 'audio'], { hasVisionDone: true, hasSttDone: false }),
    ).toBe(false)
  })

  it('foto + áudio + só STT done → bloqueia (vision em vôo)', () => {
    expect(
      allMediaDone(['image', 'audio'], { hasVisionDone: false, hasSttDone: true }),
    ).toBe(false)
  })

  it('lista vazia → flush OK (sem mídia pra esperar)', () => {
    expect(allMediaDone([], { hasVisionDone: false, hasSttDone: false })).toBe(true)
  })
})
