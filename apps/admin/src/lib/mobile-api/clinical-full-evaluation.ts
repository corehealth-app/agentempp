/** Server-owned FULL projection, never an HTTP effect or permission to write.
 * The original SQL context/hash remains the atomic writer's authority. */
import {
  evaluateDeficitDifficulty,
  evaluateGainReviewLimits,
  evaluatePhaseCalorieRule,
} from '@mpp/core/reevaluation-calorie-rules'
import { evaluateReevaluationSafety } from '@mpp/core/reevaluation-clinical-safety'
import { isFullReevaluationKind, requiresReevaluationPhotos } from '@mpp/core/reevaluation-form'
import {
  evaluateMaintenanceChoices,
  evaluateRecompositionReviewOptions,
} from '@mpp/core/reevaluation-phase-eligibility'
import {
  evaluateConfirmedActivityChange,
  evaluatePhaseSchedule,
  gainExitInvitation,
  planGainExit,
  planRecompositionTransition,
} from '@mpp/core/reevaluation-phase-schedule'
import { evaluateReevaluationProteinInputs } from '@mpp/core/reevaluation-protein-inputs'
import { readClinicalFullContext } from './clinical-full-authority'
import { normalizeClinicalFullCommand } from './clinical-full-command'
import {
  type ClinicalFullProposal,
  fullPackageSchema,
  fullScopeSchema,
} from './clinical-full-contracts'
import {
  clinicalPhaseEntryDeficit,
  clinicalPhaseEntryEpisode,
  projectClinicalPhaseEntry,
} from './clinical-phase-entry-policy'
import { calculateClinicalSnapshotTargets } from './clinical-snapshot-calculation'

export class ClinicalFullChoiceUnavailable extends Error {
  constructor(readonly reason: string) {
    super(`Review choice unavailable: ${reason}`)
  }
}
function unavailable(reason: string): never {
  throw new ClinicalFullChoiceUnavailable(reason)
}
function invalid(): never {
  throw new Error('Invalid clinical FULL input')
}
function hundredths(value: number | null) {
  return value !== null && Math.abs(value * 100 - Math.round(value * 100)) < 1e-9
    ? Math.round(value * 100)
    : null
}

export function evaluateClinicalFull(raw: unknown, expectedScope: unknown, rawInput: unknown) {
  const context = readClinicalFullContext(raw, expectedScope)
  const scope = fullScopeSchema.parse(expectedScope)
  const { facts } = context,
    profile = facts.profile,
    authority = facts.protocol_authority
  let normalized: ReturnType<typeof normalizeClinicalFullCommand>
  try {
    normalized = normalizeClinicalFullCommand(rawInput, {
      sex: profile.sex,
      heightCm: profile.height_cm,
    })
  } catch {
    return invalid()
  }
  const { command, preference } = normalized
  const input = command,
    choice = input.choice
  const form = command.form
  if (form.kind !== scope.kind || form.phase !== profile.current_protocol) return invalid()
  if (
    form.answers.healthCheck?.kind === 'risks' &&
    form.answers.healthCheck.items.some(
      (code) => !facts.safety.items.some((item) => item.code === code),
    )
  )
    throw new Error('Clinical context changed: declare risks before capture')
  const photo = authority.body_fat_candidate
  if (
    requiresReevaluationPhotos(scope.kind)
      ? !input.bodyFat ||
        photo?.availability !== 'available' ||
        input.bodyFat.sourceHash !== photo.source_hash ||
        input.bodyFat.meanHundredths !== photo.mean_hundredths
      : input.bodyFat !== null
  )
    return invalid()
  const clearHold =
    facts.safety.hold_active &&
    isFullReevaluationKind(scope.kind) &&
    form.answers.healthCheck?.kind === 'none' &&
    form.answers.professionalConversationConfirmed === true
  const safety = {
    date: facts.calculation_date,
    birthDate: profile.birth_date,
    heightCm: profile.height_cm,
    weightKg: form.answers.weightKg ?? profile.weight_kg,
    bodyFatPercent: input.bodyFat ? input.bodyFat.meanHundredths / 100 : profile.body_fat_percent,
    hold: {
      active: facts.safety.hold_active && !clearHold,
      items: clearHold ? [] : facts.safety.items.map((v) => v.code),
    },
  }
  const safetyDecision = evaluateReevaluationSafety(safety)
  const beforeTargets = {
    beforeKcal: facts.day?.calories_target ?? null,
    beforeProtein: facts.day?.protein_target ?? null,
  }
  if (form.phase === null) {
    if ('legacyOrigin' in form) {
      if (
        authority.phase_origin.kind !== 'legacy_transition_unassigned' ||
        JSON.stringify(form.legacyOrigin) !== JSON.stringify(authority.phase_origin)
      )
        return unavailable('legacy_origin')
      let proposal: ClinicalFullProposal = {
        version: 1,
        principal: 'keep',
        clearHold,
        profile: {
          current_protocol: null,
          deficit_level: null,
          activity_level: profile.activity_level,
          training_frequency: profile.training_frequency,
          hunger_level: profile.hunger_level,
        },
        targets: {
          ...beforeTargets,
          afterKcal: beforeTargets.beforeKcal,
          afterProtein: beforeTargets.beforeProtein,
          formulaAfterKcal: null,
        },
        episode: {
          difficultyCount: null,
          ledgerSteps: null,
          schedule: null,
          maintenanceSince: null,
        },
      }
      if (choice.kind !== 'keep') {
        if (
          choice.kind !== 'phase' ||
          !requiresReevaluationPhotos(scope.kind) ||
          !input.bodyFat ||
          form.answers.healthCheck?.kind !== 'none'
        )
          return unavailable('initial_phase')
        const confirmedActivity = form.answers.activity?.activityLevelConfirmed === true
        const prospective = {
          ...profile,
          weight_kg: safety.weightKg,
          body_fat_percent: input.bodyFat.meanHundredths / 100,
          hunger_level: form.answers.hunger ?? profile.hunger_level,
          training_frequency: form.answers.strengthSessions ?? profile.training_frequency,
          activity_level: confirmedActivity
            ? (form.answers.activity?.activityLevel ?? null)
            : profile.activity_level,
        }
        const offered = projectClinicalPhaseEntry({
          date: facts.calculation_date,
          effectiveDate: facts.calculation_date,
          profile: prospective,
          hold: safety.hold,
          calculationConfig: facts.calculation_config,
        })
        if (
          offered.availability !== 'available' ||
          !offered.options.some(
            (option) => option.phase === choice.phase && option.status === 'available',
          )
        )
          return unavailable('initial_phase_eligibility')
        const deficit = clinicalPhaseEntryDeficit(
          choice.phase,
          prospective.hunger_level,
          facts.calculation_config,
        )
        const effective = clearHold
          ? {
              ...context,
              facts: { ...facts, safety: { ...facts.safety, hold_active: false, items: [] } },
            }
          : context
        const calculated = calculateClinicalSnapshotTargets(effective, scope.userId, {
          phase: choice.phase,
          ...(deficit === null ? {} : { deficitLevel: deficit }),
          form,
          applyActivityAnswer: confirmedActivity,
          proteinInputSource: 'answers',
          assessmentProposal: true,
          bodyFatCandidate: {
            sourceHash: input.bodyFat.sourceHash,
            meanHundredths: input.bodyFat.meanHundredths,
          },
        })
        if (
          !calculated.automaticCalculationReady ||
          calculated.formulaKcal === null ||
          calculated.proteinTarget === null
        )
          return unavailable('initial_phase_calculation')
        proposal = {
          version: 1,
          principal:
            choice.phase === 'recomposicao'
              ? 'phase_recomposition'
              : choice.phase === 'ganho_massa'
                ? 'phase_gain'
                : 'phase_maintenance',
          clearHold,
          profile: {
            current_protocol: choice.phase,
            deficit_level: deficit,
            activity_level: prospective.activity_level,
            training_frequency: prospective.training_frequency,
            hunger_level: prospective.hunger_level,
          },
          targets: {
            ...beforeTargets,
            afterKcal: calculated.formulaKcal,
            afterProtein: calculated.proteinTarget,
            formulaAfterKcal: calculated.formulaKcal,
          },
          episode: clinicalPhaseEntryEpisode(
            choice.phase,
            facts.calculation_date,
            facts.day?.day_closed ?? false,
          ),
        }
      }
      return {
        context,
        command,
        preference,
        safety: safetyDecision,
        package: fullPackageSchema.parse({
          form,
          intent: { principalConfirmed: choice.kind === 'phase', bodyFat: input.bodyFat },
          proposal,
        }),
      }
    }
    if (
      authority.phase_origin.kind !== 'confirmed_no_plan' ||
      choice.kind !== 'keep' ||
      JSON.stringify(form.noPlanOrigin) !== JSON.stringify(authority.phase_origin)
    )
      return unavailable('no_plan')
    return {
      context,
      command,
      preference,
      safety: safetyDecision,
      package: fullPackageSchema.parse({
        form,
        intent: { principalConfirmed: false, bodyFat: input.bodyFat },
        proposal: {
          version: 1,
          principal: 'keep',
          clearHold,
          profile: {
            current_protocol: null,
            deficit_level: null,
            activity_level: profile.activity_level,
            training_frequency: profile.training_frequency,
            hunger_level: profile.hunger_level,
          },
          targets: {
            beforeKcal: null,
            beforeProtein: null,
            afterKcal: null,
            afterProtein: null,
            formulaAfterKcal: null,
          },
          episode: {
            difficultyCount: null,
            ledgerSteps: null,
            schedule: null,
            maintenanceSince: null,
          },
        },
      }),
    }
  }
  const plannedForm = form
  const currentPhase = form.phase
  const episode = authority.episode
  const signup = authority.signup_origin?.phase === currentPhase ? authority.signup_origin : null
  let ledger = episode ? episode.ledger_steps : signup ? [] : null
  let r = episode ? episode.maintenance_since : (signup?.maintenance_since ?? null)
  let schedule = episode?.schedule ?? null
  let difficulty = episode
    ? episode.difficulty_count === null
      ? null
      : Number(episode.difficulty_count)
    : signup
      ? 0
      : null
  const currentDeficit = currentPhase === 'recomposicao' ? profile.deficit_level : null
  const baseline =
    episode ??
    (signup
      ? {
          start_weight_kg: signup.start_weight_kg,
          start_height_cm: signup.start_height_cm,
          start_body_fat_percent: signup.start_body_fat_percent,
          start_training_frequency: signup.start_training_frequency,
          entry_date: signup.start_date,
        }
      : null)
  const startBMI =
    baseline?.start_weight_kg && baseline.start_height_cm
      ? baseline.start_weight_kg / (baseline.start_height_cm / 100) ** 2
      : null
  const startFat = hundredths(baseline?.start_body_fat_percent ?? null)
  const history = {
    date: facts.calculation_date,
    asOf: context.observed_at,
    measurements: facts.weight_history.map((v) => ({
      id: v.id,
      localDate: v.local_date,
      measuredAt: v.measured_at,
      weightHundredths: Math.round(v.weight_kg * 100),
    })),
  }
  // A pure effective-safety projection for this exact confirmed clear/neutral
  // intent. Original facts/hash are returned untouched and sent to SQL CAS;
  // this copy never clears a HOLD or authorizes a database write by itself.
  const neutral = choice.kind === 'neutral_exit'
  if (neutral && (scope.kind !== 'SAFETY' || !safetyDecision.neutralExitAllowed))
    return unavailable('neutral_exit')
  const effective =
    clearHold || neutral
      ? {
          ...context,
          facts: { ...facts, safety: { ...facts.safety, hold_active: false, items: [] } },
        }
      : context
  const bodyFatCandidate = input.bodyFat
    ? { sourceHash: input.bodyFat.sourceHash, meanHundredths: input.bodyFat.meanHundredths }
    : undefined
  const calculate = (
    phase = currentPhase,
    deficit = currentDeficit,
    activity = false,
    answers = false,
  ) =>
    calculateClinicalSnapshotTargets(effective, scope.userId, {
      phase,
      ...(deficit === null ? {} : { deficitLevel: deficit }),
      form: plannedForm,
      applyActivityAnswer: activity,
      proteinInputSource: answers ? 'answers' : 'profile',
      assessmentProposal: isFullReevaluationKind(scope.kind),
      ...(bodyFatCandidate ? { bodyFatCandidate } : {}),
    })
  const initial = calculate()
  const selectedPhase =
    choice.kind === 'phase' ? choice.phase : neutral ? 'manutencao' : currentPhase
  const protein = evaluateReevaluationProteinInputs({
    phase: selectedPhase,
    profileHunger: profile.hunger_level,
    profileSessions: profile.training_frequency,
    answeredHunger: form.answers.hunger,
    answeredSessions: form.answers.strengthSessions,
    confirmedPrincipal: neutral
      ? null
      : choice.kind === 'phase' || (choice.kind === 'schedule' && choice.action === 'reconfirm')
        ? 'phase'
        : choice.kind === 'activity'
          ? 'activity'
          : null,
    proteinFactors: initial.config.protein_factors,
    recompProteinFactor: initial.config.recomp_protein_g_per_kg,
    safety: neutral ? { ...safety, hold: { active: false, items: [] } } : safety,
  })
  const answerInputs =
    !neutral && (protein.status === 'same_branch' || protein.status === 'confirmed')
  let calculation = calculate(currentPhase, currentDeficit, false, answerInputs)
  let principal: ClinicalFullProposal['principal'] = 'keep'
  let phase = currentPhase,
    deficit = currentDeficit,
    level = profile.activity_level
  let afterKcal = beforeTargets.beforeKcal,
    afterProtein = beforeTargets.beforeProtein
  const hasSafeFormula =
    calculation.automaticCalculationReady && !safetyDecision.pauseWeightLossGuidance
  let formulaKcal: number | null = hasSafeFormula ? calculation.formulaKcal : null
  const net = () => ledger?.reduce((sum, v) => sum + v, 0) ?? null
  const ledgerTarget = (value: ReturnType<typeof calculate>) => {
    if (value.formulaKcal === null) return null
    if (phase === 'recomposicao') return value.formulaKcal
    const adjustment = net()
    if (adjustment === null) return null
    const floor = phase === 'ganho_massa' ? value.maintenanceKcal : value.sedentaryKcal
    return floor === null ? null : Math.max(floor, value.formulaKcal + adjustment)
  }
  if (hasSafeFormula) {
    afterKcal = ledgerTarget(calculation) ?? beforeTargets.beforeKcal
    afterProtein = calculation.proteinTarget
  }
  const transition = schedule !== null && r === null
  const composition =
    profile.height_cm !== null && safety.weightKg !== null
      ? {
          sex: profile.sex,
          heightCm: profile.height_cm,
          weightKg: safety.weightKg,
          bodyFat:
            calculation.bodyFat.kind === 'absent'
              ? { kind: 'absent' as const }
              : {
                  kind: calculation.bodyFat.kind,
                  hundredths: calculation.bodyFat.hundredths,
                },
          sessions: form.answers.strengthSessions,
        }
      : null
  const phaseOptions = composition
    ? evaluateRecompositionReviewOptions(
        {
          form,
          safety,
          composition,
          maintenanceSince: r,
          transitionActiveOrPaused: transition,
          measureConfirmed: input.measureConfirmed,
        },
        calculation.config,
      )
    : null
  const difficultySignal = form.answers.hunger === 'muita' || form.answers.energy === 'baixa'
  let deficitRule: ReturnType<typeof evaluateDeficitDifficulty> | null = null
  if (currentPhase === 'recomposicao' && scope.kind === 'REGULAR' && currentDeficit !== null) {
    if (difficulty !== null) {
      deficitRule = evaluateDeficitDifficulty({
        form,
        safety,
        count: difficulty,
        deficitLevel: currentDeficit,
        higherPriorityDecisionConfirmed:
          choice.kind !== 'keep' && choice.kind !== 'phase_calorie_step',
      })
      difficulty = deficitRule.nextCount
    } else if (form.answers.hunger === null || form.answers.energy === null || !difficultySignal)
      difficulty = 0
  }
  // An unknown OLD deficit cannot supply a baseline or calorie step. It also
  // must not prevent a separately confirmed, independently valid NEW phase.
  // All phase eligibility/activity/schedule checks below still apply.
  const explicitPhaseFromUnknownDeficit =
    currentPhase === 'recomposicao' &&
    currentDeficit === null &&
    choice.kind === 'phase' &&
    choice.phase !== currentPhase &&
    !safetyDecision.pauseWeightLossGuidance &&
    calculate(choice.phase, null, false, answerInputs).automaticCalculationReady
  if (choice.kind !== 'keep' && !neutral && !hasSafeFormula && !explicitPhaseFromUnknownDeficit)
    return unavailable('calculation_or_safety')
  if (choice.kind === 'phase_calorie_step') {
    if (currentPhase === 'recomposicao') {
      if (!deficitRule?.proposal) return unavailable('deficit_step')
      principal = 'deficit_step'
      deficit = deficitRule.proposal.deficitAfter
      difficulty = 0
      calculation = calculate(phase, deficit, false, answerInputs)
      afterKcal = calculation.formulaKcal
      afterProtein = calculation.proteinTarget
      formulaKcal = calculation.formulaKcal
    } else {
      if (
        ledger === null ||
        afterKcal === null ||
        (currentPhase === 'ganho_massa' && (startBMI === null || startFat === null))
      )
        return unavailable('episode_history')
      const step = evaluatePhaseCalorieRule({
        form,
        safety,
        history,
        currentTargetKcal: afterKcal,
        floorKcal:
          currentPhase === 'ganho_massa' ? calculation.maintenanceKcal : calculation.sedentaryKcal,
        ledgerSteps: ledger,
        maintenanceSince: r,
        activityChangedThisCycle: authority.routine_reviews_since_regular.some(
          (v) => v.activity_level_changed,
        ),
        transitionActive: transition,
        higherPriorityDecisionConfirmed: false,
        sex: profile.sex,
        gainStartBMI: startBMI,
        gainStartBodyFatHundredths: startFat,
        gainStartFrequency: baseline?.start_training_frequency ?? null,
        profileStrengthFrequency: profile.training_frequency,
      })
      if (!step.proposal) return unavailable(step.reason)
      principal = currentPhase === 'manutencao' ? 'maintenance_step' : 'gain_step'
      afterKcal = step.proposal.targetKcal
      ledger = [...ledger, step.proposal.deltaKcal]
    }
  }
  if (choice.kind === 'activity') {
    if (calculation.bmr === null || (currentPhase !== 'recomposicao' && ledger === null))
      return unavailable('episode_activity')
    const activity = form.answers.activity
    if (
      (!activity?.activityLevelConfirmed || activity.activityLevel === null) &&
      protein.status !== 'confirmed'
    )
      return unavailable('activity_confirmation')
    if (activity?.activityLevelConfirmed) {
      const evaluated = evaluateConfirmedActivityChange({
        phase,
        safety,
        bmr: calculation.bmr,
        activityFactors: calculation.config.activity_factors,
        surplusMultiplier: calculation.config.ganho_massa_surplus_multiplier,
        beforeLevel: profile.activity_level,
        confirmedLevel: activity.activityLevel,
        levelConfirmed: true,
        sessions: form.answers.strengthSessions,
        profileSessions: profile.training_frequency,
        gainStartSessions: baseline?.start_training_frequency ?? null,
        ledgerSteps: ledger ?? [],
      })
      if (evaluated.status === 'blocked' || evaluated.status === 'missing')
        return unavailable(evaluated.reason)
      level = activity.activityLevel
    }
    principal = 'activity'
    calculation = calculate(phase, deficit, activity?.activityLevelConfirmed === true, answerInputs)
    afterKcal = ledgerTarget(calculation)
    afterProtein = calculation.proteinTarget
    formulaKcal = calculation.formulaKcal
  }
  if (
    choice.kind === 'phase' ||
    neutral ||
    (choice.kind === 'schedule' && choice.action === 'reconfirm')
  ) {
    if (form.answers.activity?.activityLevelConfirmed !== true)
      return unavailable('activity_confirmation')
    level = form.answers.activity.activityLevel
    const newSchedule = choice.kind === 'schedule'
    if (neutral) {
      phase = 'manutencao'
      deficit = null
      principal = 'neutral_exit'
      schedule = null
      r = facts.calculation_date
      ledger = []
    } else if (newSchedule) {
      if (!schedule || !transition) return unavailable('schedule')
      principal = 'schedule_reconfirm'
    } else if (choice.kind === 'phase' && currentPhase === 'recomposicao') {
      if (
        choice.phase !== 'manutencao' ||
        phaseOptions?.proposal?.kind !== 'maintenance_transition'
      )
        return unavailable('phase')
      phase = 'manutencao'
      deficit = null
      principal = 'recomposition_transition'
      ledger = []
      r = null
    } else if (choice.kind === 'phase' && currentPhase === 'manutencao') {
      if (choice.phase === 'manutencao' || !composition) return unavailable('phase')
      const options = evaluateMaintenanceChoices(
        {
          form,
          safety,
          composition,
          history,
          maintenanceSince: r,
          transitionActiveOrPaused: transition,
          priorFulls: authority.prior_regular_reviews.map((v) => ({
            id: v.review_id,
            kind: v.kind,
            date: v.date,
            adherence: v.form.answers.adherence,
            energy: v.form.answers.energy,
          })),
        },
        calculation.config,
      )
      if (choice.phase === 'ganho_massa') {
        if (!options.gain.available) return unavailable('gain_gate')
        phase = 'ganho_massa'
        deficit = null
        principal = 'phase_gain'
      } else {
        const suggested =
          phaseOptions?.proposal?.kind === 'recomposition_suggestion'
            ? phaseOptions.proposal.deficitLevel
            : null
        const chosen =
          suggested ?? (options.recomposition.available ? options.recomposition.deficitLevel : null)
        if (chosen === null) return unavailable('recomposition_gate')
        phase = 'recomposicao'
        deficit = chosen
        principal = 'phase_recomposition'
      }
      ledger = []
      r = null
      schedule = null
    } else if (choice.kind === 'phase' && currentPhase === 'ganho_massa') {
      if (choice.phase !== 'manutencao') return unavailable('direct_phase')
      const limits = evaluateGainReviewLimits({
        sex: profile.sex,
        bodyFatHundredths: calculation.bodyFat.hundredths,
        startBodyFatHundredths: startFat,
        bmi: safetyDecision.bmi,
        startBMI,
      })
      const invited = baseline?.entry_date
        ? gainExitInvitation({
            startDate: baseline.entry_date,
            date: facts.calculation_date,
            limitActive: limits.active.length > 0,
            requested: true,
          }).offer
        : limits.active.length > 0
      if (!invited || transition) return unavailable('gain_exit')
      principal = 'gain_exit'
    }
    const scheduleKind =
      principal === 'recomposition_transition'
        ? 'recomp_to_maintenance'
        : principal === 'gain_exit'
          ? 'gain_exit'
          : newSchedule
            ? schedule?.kind
            : null
    calculation = calculate(
      scheduleKind || neutral ? 'manutencao' : phase,
      deficit,
      true,
      neutral ? false : answerInputs,
    )
    if (
      calculation.formulaKcal === null ||
      calculation.proteinTarget === null ||
      (calculation.legacyTarget.origin === 'unproven' && !calculation.assessmentProposal)
    )
      return unavailable('phase_calculation')
    formulaKcal = calculation.formulaKcal
    afterProtein = calculation.proteinTarget
    if (scheduleKind) {
      if (beforeTargets.beforeKcal === null) return unavailable('schedule_start_target')
      const input = {
        date: facts.calculation_date,
        safety,
        currentTargetKcal: beforeTargets.beforeKcal,
        maintenanceTargetKcal: calculation.maintenanceKcal,
        activityLevelConfirmed: true,
      }
      schedule =
        scheduleKind === 'gain_exit' ? planGainExit(input) : planRecompositionTransition(input)
      if (scheduleKind === 'gain_exit') formulaKcal = schedule.maintenanceTargetKcal
      r = null
    } else afterKcal = ledgerTarget(calculation)
    if (phase !== currentPhase) difficulty = 0
  }
  if (choice.kind === 'schedule' && choice.action === 'pause') {
    if (!schedule || !transition || schedule.kind === 'gain_exit')
      return unavailable('schedule_pause')
    principal = 'schedule_pause'
    schedule = { ...schedule, state: 'suspended' }
    afterKcal = beforeTargets.beforeKcal
  }
  if (schedule && r === null && principal !== 'schedule_pause') {
    if (!safetyDecision.automaticTargetChangeAllowed) {
      if (scope.kind === 'ROUTINE_REVIEW' && schedule.state === 'running')
        return unavailable('daily_schedule_suspension_required')
      if (schedule.state === 'running') principal = 'schedule_pause'
      schedule = { ...schedule, state: 'suspended' }
      afterKcal = beforeTargets.beforeKcal
      afterProtein = beforeTargets.beforeProtein
    } else {
      if (beforeTargets.beforeKcal === null || calculation.maintenanceKcal === null)
        return unavailable('schedule_calculation')
      const projected = evaluatePhaseSchedule({
        schedule,
        date: facts.calculation_date,
        safety,
        currentTargetKcal: beforeTargets.beforeKcal,
        maintenanceTargetTodayKcal: calculation.maintenanceKcal,
      })
      afterKcal = projected.targetKcal
      phase = projected.phase
      if (projected.reachedMaintenance) r = facts.calculation_date
      if (schedule.kind === 'gain_exit') formulaKcal = schedule.maintenanceTargetKcal
    }
  }
  if (scope.kind === 'SAFETY' && !neutral) return unavailable('safety_requires_neutral_exit')
  if (phase !== currentPhase) {
    ledger = []
    difficulty = 0
  }
  if (
    facts.day?.day_closed &&
    (phase !== currentPhase ||
      (episode ? episode.maintenance_since : signup?.maintenance_since) == null)
  )
    r = null
  const result = fullPackageSchema.parse({
    form,
    intent: { principalConfirmed: principal !== 'keep', bodyFat: input.bodyFat },
    proposal: {
      version: 1,
      principal,
      clearHold,
      profile: {
        current_protocol: phase,
        deficit_level: deficit,
        activity_level: level,
        training_frequency: answerInputs ? protein.profile.sessions : profile.training_frequency,
        hunger_level: answerInputs ? protein.profile.hunger : profile.hunger_level,
      },
      targets: { ...beforeTargets, afterKcal, afterProtein, formulaAfterKcal: formulaKcal },
      episode: { difficultyCount: difficulty, ledgerSteps: ledger, schedule, maintenanceSince: r },
    },
  })
  return { context, command, preference, safety: safetyDecision, package: result }
}
