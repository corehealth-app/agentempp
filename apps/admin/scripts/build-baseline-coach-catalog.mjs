import { mkdir, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const personalities = ['balanced', 'focus', 'impulse', 'zen']

const toneFrames = {
  'pt-BR': {
    balanced: [
      {
        app: (copy) => `${copy} Vamos seguir com clareza.`,
        push: (copy) => copy,
        email: (copy) => `${copy} Siga pelo próximo passo quando estiver pronto.`,
      },
      {
        app: (copy) => `${copy} O próximo passo está bem definido.`,
        push: (copy) => `Atualização: ${copy}`,
        email: (copy) => `${copy} Você pode continuar pelo BodyFlow no seu ritmo.`,
      },
      {
        app: (copy) => `${copy} Continue de forma consistente.`,
        push: (copy) => `Para você: ${copy}`,
        email: (copy) => `${copy} O BodyFlow mantém o contexto para você continuar.`,
      },
    ],
    focus: [
      {
        app: (copy) => `Foco no próximo passo: ${copy}`,
        push: (copy) => `Agora: ${copy}`,
        email: (copy) => `Próxima ação: ${copy} Abra o BodyFlow para concluir.`,
      },
      {
        app: (copy) => `Direto ao ponto: ${copy}`,
        push: (copy) => `Direto ao ponto: ${copy}`,
        email: (copy) => `Plano objetivo: ${copy} Continue pelo BodyFlow.`,
      },
      {
        app: (copy) => `Plano claro: ${copy}`,
        push: (copy) => `Seu plano: ${copy}`,
        email: (copy) => `Prioridade definida: ${copy} O próximo passo está no BodyFlow.`,
      },
    ],
    impulse: [
      {
        app: (copy) => `Boa energia para seguir: ${copy}`,
        push: (copy) => `Boa! ${copy}`,
        email: (copy) => `Vamos manter o movimento: ${copy} Continue pelo BodyFlow.`,
      },
      {
        app: (copy) => `Vamos nessa: ${copy}`,
        push: (copy) => `Vamos nessa: ${copy}`,
        email: (copy) =>
          `Mais um passo em andamento: ${copy} O BodyFlow está pronto para continuar.`,
      },
      {
        app: (copy) => `Mais um passo em movimento: ${copy}`,
        push: (copy) => `Siga em frente: ${copy}`,
        email: (copy) => `Seu ritmo continua: ${copy} Retome pelo BodyFlow quando quiser.`,
      },
    ],
    zen: [
      {
        app: (copy) => `Com calma e atenção: ${copy}`,
        push: (copy) => `Com calma: ${copy}`,
        email: (copy) => `Com atenção ao momento: ${copy} Continue no BodyFlow sem pressa.`,
      },
      {
        app: (copy) => `Sem pressa: ${copy}`,
        push: (copy) => `No seu ritmo: ${copy}`,
        email: (copy) =>
          `Um passo tranquilo: ${copy} O BodyFlow guarda o seu ponto de continuidade.`,
      },
      {
        app: (copy) => `Um passo de cada vez: ${copy}`,
        push: (copy) => `Passo a passo: ${copy}`,
        email: (copy) => `Siga com leveza: ${copy} Volte ao BodyFlow quando for um bom momento.`,
      },
    ],
  },
  'en-US': {
    balanced: [
      {
        app: (copy) => `${copy} Keep the next step clear.`,
        push: (copy) => copy,
        email: (copy) => `${copy} Continue with the next step when you are ready.`,
      },
      {
        app: (copy) => `${copy} Your next step is well defined.`,
        push: (copy) => `Update: ${copy}`,
        email: (copy) => `${copy} You can continue in BodyFlow at your own pace.`,
      },
      {
        app: (copy) => `${copy} Keep moving with consistency.`,
        push: (copy) => `For you: ${copy}`,
        email: (copy) => `${copy} BodyFlow keeps the context ready for your return.`,
      },
    ],
    focus: [
      {
        app: (copy) => `Focus on the next action: ${copy}`,
        push: (copy) => `Now: ${copy}`,
        email: (copy) => `Next action: ${copy} Open BodyFlow to complete it.`,
      },
      {
        app: (copy) => `Straight to the point: ${copy}`,
        push: (copy) => `Next step: ${copy}`,
        email: (copy) => `Clear plan: ${copy} Continue in BodyFlow.`,
      },
      {
        app: (copy) => `The plan is clear: ${copy}`,
        push: (copy) => `Your plan: ${copy}`,
        email: (copy) => `Priority set: ${copy} Your next step is in BodyFlow.`,
      },
    ],
    impulse: [
      {
        app: (copy) => `Nice momentum: ${copy}`,
        push: (copy) => `Nice! ${copy}`,
        email: (copy) => `Keep the momentum going: ${copy} Continue in BodyFlow.`,
      },
      {
        app: (copy) => `Let's keep it moving: ${copy}`,
        push: (copy) => `Keep going: ${copy}`,
        email: (copy) => `Another step is moving forward: ${copy} BodyFlow is ready when you are.`,
      },
      {
        app: (copy) => `Another step forward: ${copy}`,
        push: (copy) => `Move forward: ${copy}`,
        email: (copy) => `Your momentum continues: ${copy} Return to BodyFlow whenever you want.`,
      },
    ],
    zen: [
      {
        app: (copy) => `Take this moment calmly: ${copy}`,
        push: (copy) => `Take it calmly: ${copy}`,
        email: (copy) => `With calm attention: ${copy} Continue in BodyFlow without rushing.`,
      },
      {
        app: (copy) => `No rush: ${copy}`,
        push: (copy) => `At your pace: ${copy}`,
        email: (copy) => `A steady step: ${copy} BodyFlow keeps your place for you.`,
      },
      {
        app: (copy) => `One step at a time: ${copy}`,
        push: (copy) => `Step by step: ${copy}`,
        email: (copy) => `Move gently: ${copy} Return to BodyFlow when the time feels right.`,
      },
    ],
  },
}

const contextCopy = {
  'pt-BR': {
    onboarding: {
      title: 'Vamos começar',
      subject: 'Seu início no BodyFlow',
      variants: [
        {
          required: [],
          app: 'Seu perfil está pronto para receber as primeiras informações.',
          push: 'Complete as primeiras informações do seu perfil.',
        },
        {
          required: [],
          app: 'Faltam poucos detalhes para personalizar sua experiência.',
          push: 'Ajuste os detalhes iniciais do seu perfil.',
        },
        {
          required: [],
          app: 'Você pode construir seu plano inicial em etapas simples.',
          push: 'Continue a configuração inicial quando puder.',
        },
      ],
    },
    meal_pending: {
      title: 'Refeição para revisar',
      subject: 'Revise uma refeição no BodyFlow',
      variants: [
        {
          required: ['meal'],
          app: 'A refeição {{meal}} está pronta para sua revisão antes do registro.',
          push: 'Revise {{meal}} antes de registrar.',
        },
        {
          required: ['meal'],
          app: 'Confira os itens de {{meal}} e confirme somente o que foi consumido.',
          push: 'Confira os itens de {{meal}}.',
        },
        {
          required: [],
          app: 'Há uma refeição aguardando sua confirmação para entrar no dia.',
          push: 'Uma refeição aguarda sua confirmação.',
        },
      ],
    },
    registration_confirmed: {
      title: 'Registro confirmado',
      subject: 'Seu registro foi atualizado',
      variants: [
        {
          required: ['meal'],
          app: 'O registro de {{meal}} foi confirmado e já faz parte do seu dia.',
          push: '{{meal}} foi registrada com sucesso.',
        },
        {
          required: ['kcal_remaining'],
          app: 'Registro concluído. Seu saldo planejado agora é de {{kcal_remaining}} kcal.',
          push: 'Registro feito. Restam {{kcal_remaining}} kcal no plano.',
        },
        {
          required: [],
          app: 'Seu registro foi salvo e os totais do dia foram recalculados.',
          push: 'Registro salvo e totais atualizados.',
        },
      ],
    },
    error_corrected: {
      title: 'Correção concluída',
      subject: 'Uma correção foi aplicada',
      variants: [
        {
          required: ['meal'],
          app: 'A correção de {{meal}} foi aplicada e os totais foram recalculados.',
          push: '{{meal}} foi corrigida e recalculada.',
        },
        {
          required: ['meal'],
          app: 'O ajuste em {{meal}} substituiu o valor anterior sem duplicar o registro.',
          push: 'O ajuste em {{meal}} foi concluído.',
        },
        {
          required: [],
          app: 'A informação corrigida já aparece no histórico e no resumo do dia.',
          push: 'Correção salva e resumo atualizado.',
        },
      ],
    },
    hydration: {
      title: 'Hora de hidratar',
      subject: 'Seu acompanhamento de hidratação',
      variants: [
        {
          required: ['water_remaining_ml'],
          app: 'Faltam {{water_remaining_ml}} ml para a meta de hidratação de hoje.',
          push: 'Faltam {{water_remaining_ml}} ml de água hoje.',
        },
        {
          required: ['water_remaining_ml'],
          app: 'Seu saldo de água é {{water_remaining_ml}} ml. Registre o próximo copo quando beber.',
          push: 'Saldo de água: {{water_remaining_ml}} ml.',
        },
        {
          required: [],
          app: 'Uma pausa para água pode ajudar a manter o acompanhamento do dia em dia.',
          push: 'Que tal registrar um pouco de água?',
        },
      ],
    },
    supplement: {
      title: 'Lembrete de suplemento',
      subject: 'Seu suplemento programado',
      variants: [
        {
          required: ['supplement_name'],
          app: '{{supplement_name}} está no horário programado. Confirme depois de seguir sua rotina.',
          push: 'Horário programado de {{supplement_name}}.',
        },
        {
          required: ['supplement_name'],
          app: 'Confira sua orientação para {{supplement_name}} antes de marcar como realizado.',
          push: 'Confira a rotina de {{supplement_name}}.',
        },
        {
          required: [],
          app: 'Há um suplemento programado para este período. Revise sua rotina antes de confirmar.',
          push: 'Há um suplemento programado agora.',
        },
      ],
    },
    medication: {
      title: 'Lembrete de medicação',
      subject: 'Sua medicação programada',
      variants: [
        {
          required: ['medication_name'],
          app: '{{medication_name}} está no horário programado. Siga somente a orientação prescrita.',
          push: 'Horário programado de {{medication_name}}.',
        },
        {
          required: ['medication_name'],
          app: 'Confira a prescrição de {{medication_name}} antes de confirmar este lembrete.',
          push: 'Confira a prescrição de {{medication_name}}.',
        },
        {
          required: [],
          app: 'Há uma medicação programada. Revise a prescrição e confirme apenas após segui-la.',
          push: 'Há uma medicação programada agora.',
        },
      ],
    },
    workout: {
      title: 'Movimento do dia',
      subject: 'Seu acompanhamento de treino',
      variants: [
        {
          required: [],
          app: 'Seu treino pode ser registrado com atividade, duração e intensidade percebida.',
          push: 'Registre o treino quando concluir.',
        },
        {
          required: [],
          app: 'Movimento concluído também conta. Salve a sessão para manter o histórico preciso.',
          push: 'Salve a atividade feita hoje.',
        },
        {
          required: [],
          app: 'Quando houver treino, registre uma vez e revise os detalhes antes de confirmar.',
          push: 'Revise e confirme a atividade de hoje.',
        },
      ],
    },
    progress: {
      title: 'Seu progresso',
      subject: 'Atualização do seu progresso',
      variants: [
        {
          required: ['block_progress_percent'],
          app: 'Seu bloco atual chegou a {{block_progress_percent}}%. O valor usa apenas dias elegíveis.',
          push: 'Seu bloco está em {{block_progress_percent}}%.',
        },
        {
          required: ['protein_remaining_g'],
          app: 'Faltam {{protein_remaining_g}} g de proteína para a referência planejada de hoje.',
          push: 'Faltam {{protein_remaining_g}} g de proteína hoje.',
        },
        {
          required: [],
          app: 'Seu progresso foi atualizado com base nos registros confirmados até agora.',
          push: 'Seu progresso recebeu uma atualização.',
        },
      ],
    },
    day_incomplete: {
      title: 'Dia ainda incompleto',
      subject: 'Revise um registro pendente do dia',
      variants: [
        {
          required: ['meal'],
          app: 'A refeição {{meal}} ainda não foi registrada nem marcada como pulada.',
          push: '{{meal}} ainda precisa de uma resposta.',
        },
        {
          required: ['meal'],
          app: 'Confirme {{meal}}, reclassifique outro registro ou informe que essa refeição foi pulada.',
          push: 'Revise a pendência de {{meal}}.',
        },
        {
          required: [],
          app: 'Existe uma refeição esperada sem resposta. Resolva a pendência antes do fechamento.',
          push: 'Há uma refeição pendente antes do fechamento.',
        },
      ],
    },
    reevaluation: {
      title: 'Reavaliação',
      subject: 'Sua próxima reavaliação BodyFlow',
      variants: [
        {
          required: ['next_reevaluation_date'],
          app: 'Sua próxima reavaliação está prevista para {{next_reevaluation_date}}.',
          push: 'Reavaliação prevista para {{next_reevaluation_date}}.',
        },
        {
          required: ['next_reevaluation_date'],
          app: 'Reserve um momento em {{next_reevaluation_date}} para atualizar suas medidas e respostas.',
          push: 'Prepare sua reavaliação de {{next_reevaluation_date}}.',
        },
        {
          required: [],
          app: 'Uma reavaliação ajuda a atualizar o plano com dados mais recentes.',
          push: 'Sua reavaliação está se aproximando.',
        },
      ],
    },
    reengagement: {
      title: 'Seu plano continua aqui',
      subject: 'Retome seu acompanhamento no seu ritmo',
      variants: [
        {
          required: [],
          app: 'Seu histórico continua disponível. Você pode retomar com um registro simples.',
          push: 'Retome com um registro simples.',
        },
        {
          required: [],
          app: 'Não é preciso recuperar tudo de uma vez. Comece pelo que acontecer hoje.',
          push: 'Comece novamente pelo dia de hoje.',
        },
        {
          required: [],
          app: 'Quando fizer sentido voltar, o próximo passo pode ser pequeno e objetivo.',
          push: 'Seu próximo passo pode ser pequeno.',
        },
      ],
    },
    trial: {
      title: 'Período de teste',
      subject: 'Informações sobre seu período de teste',
      variants: [
        {
          required: ['trial_days_remaining'],
          app: 'Seu período de teste tem {{trial_days_remaining}} dias restantes para explorar os recursos.',
          push: 'Restam {{trial_days_remaining}} dias no período de teste.',
        },
        {
          required: ['trial_days_remaining'],
          app: 'Você ainda tem {{trial_days_remaining}} dias para avaliar se o BodyFlow combina com sua rotina.',
          push: 'Avalie o BodyFlow por mais {{trial_days_remaining}} dias.',
        },
        {
          required: [],
          app: 'Use o período de teste para conhecer os recursos que fazem sentido para você.',
          push: 'Explore os recursos durante o período de teste.',
        },
      ],
    },
    paywall: {
      title: 'Acesso ao BodyFlow',
      subject: 'Opções para continuar no BodyFlow',
      variants: [
        {
          required: [],
          app: 'Alguns recursos precisam de uma assinatura ativa. Revise as opções antes de decidir.',
          push: 'Revise as opções de assinatura.',
        },
        {
          required: [],
          app: 'A tela de planos mostra preços, período e renovação antes da confirmação.',
          push: 'Confira os detalhes dos planos disponíveis.',
        },
        {
          required: [],
          app: 'Escolha continuar apenas se a assinatura fizer sentido para sua rotina.',
          push: 'Decida sobre a assinatura no seu tempo.',
        },
      ],
    },
    return_after_abandonment: {
      title: 'Bem-vindo de volta',
      subject: 'Seu retorno ao BodyFlow',
      variants: [
        {
          required: [],
          app: 'Seu retorno pode começar pelo dia de hoje, sem reconstruir os dias anteriores.',
          push: 'Volte começando pelo dia de hoje.',
        },
        {
          required: [],
          app: 'Seus dados continuam organizados para você retomar de onde faz sentido.',
          push: 'Seu acompanhamento está pronto para continuar.',
        },
        {
          required: [],
          app: 'Um novo registro já é suficiente para colocar o acompanhamento em movimento.',
          push: 'Um novo registro pode marcar seu retorno.',
        },
      ],
    },
  },
  'en-US': {
    onboarding: {
      title: 'Let’s get started',
      subject: 'Your BodyFlow setup',
      variants: [
        {
          required: [],
          app: 'Your profile is ready for the first details that shape your experience.',
          push: 'Add the first details to your profile.',
        },
        {
          required: [],
          app: 'Only a few details remain before your experience can be personalized.',
          push: 'Review the opening details of your profile.',
        },
        {
          required: [],
          app: 'You can build your starting plan through a few simple steps.',
          push: 'Continue your initial setup when ready.',
        },
      ],
    },
    meal_pending: {
      title: 'Meal ready to review',
      subject: 'Review a meal in BodyFlow',
      variants: [
        {
          required: ['meal'],
          app: 'Your {{meal}} is ready for review before it is recorded.',
          push: 'Review {{meal}} before recording it.',
        },
        {
          required: ['meal'],
          app: 'Check the items in {{meal}} and confirm only what you consumed.',
          push: 'Check the items in {{meal}}.',
        },
        {
          required: [],
          app: 'A meal is waiting for your confirmation before it is added to today.',
          push: 'A meal is waiting for your confirmation.',
        },
      ],
    },
    registration_confirmed: {
      title: 'Entry confirmed',
      subject: 'Your daily record was updated',
      variants: [
        {
          required: ['meal'],
          app: 'Your {{meal}} entry is confirmed and now included in today’s totals.',
          push: '{{meal}} was recorded successfully.',
        },
        {
          required: ['kcal_remaining'],
          app: 'The entry is complete. Your planned balance is now {{kcal_remaining}} kcal.',
          push: 'Entry saved. {{kcal_remaining}} kcal remain in the plan.',
        },
        {
          required: [],
          app: 'Your entry was saved and today’s totals were recalculated.',
          push: 'Entry saved and daily totals updated.',
        },
      ],
    },
    error_corrected: {
      title: 'Correction complete',
      subject: 'A correction was applied',
      variants: [
        {
          required: ['meal'],
          app: 'The correction to {{meal}} was applied and the totals were recalculated.',
          push: '{{meal}} was corrected and recalculated.',
        },
        {
          required: ['meal'],
          app: 'The change to {{meal}} replaced the previous value without creating a duplicate.',
          push: 'The change to {{meal}} is complete.',
        },
        {
          required: [],
          app: 'The corrected information now appears in your history and daily summary.',
          push: 'Correction saved and summary updated.',
        },
      ],
    },
    hydration: {
      title: 'Time to hydrate',
      subject: 'Your hydration progress',
      variants: [
        {
          required: ['water_remaining_ml'],
          app: '{{water_remaining_ml}} ml remain toward today’s hydration target.',
          push: '{{water_remaining_ml}} ml of water remain today.',
        },
        {
          required: ['water_remaining_ml'],
          app: 'Your water balance is {{water_remaining_ml}} ml. Record your next serving after you drink it.',
          push: 'Water balance: {{water_remaining_ml}} ml.',
        },
        {
          required: [],
          app: 'A brief water break can help keep your daily tracking current.',
          push: 'Ready to record some water?',
        },
      ],
    },
    supplement: {
      title: 'Supplement reminder',
      subject: 'Your scheduled supplement',
      variants: [
        {
          required: ['supplement_name'],
          app: '{{supplement_name}} is scheduled for this time. Confirm it after following your routine.',
          push: '{{supplement_name}} is scheduled now.',
        },
        {
          required: ['supplement_name'],
          app: 'Review your directions for {{supplement_name}} before marking it complete.',
          push: 'Review your {{supplement_name}} routine.',
        },
        {
          required: [],
          app: 'A supplement is scheduled for this period. Review your routine before confirming it.',
          push: 'A supplement is scheduled now.',
        },
      ],
    },
    medication: {
      title: 'Medication reminder',
      subject: 'Your scheduled medication',
      variants: [
        {
          required: ['medication_name'],
          app: '{{medication_name}} is scheduled for this time. Follow only your prescribed directions.',
          push: '{{medication_name}} is scheduled now.',
        },
        {
          required: ['medication_name'],
          app: 'Review the prescription for {{medication_name}} before confirming this reminder.',
          push: 'Review the prescription for {{medication_name}}.',
        },
        {
          required: [],
          app: 'A medication is scheduled. Review the prescription and confirm only after following it.',
          push: 'A medication is scheduled now.',
        },
      ],
    },
    workout: {
      title: 'Today’s movement',
      subject: 'Your workout tracking',
      variants: [
        {
          required: [],
          app: 'You can record a workout with the activity, duration, and perceived intensity.',
          push: 'Record your workout when it is complete.',
        },
        {
          required: [],
          app: 'Completed movement counts too. Save the session to keep your history accurate.',
          push: 'Save the activity you completed today.',
        },
        {
          required: [],
          app: 'When you train, record it once and review the details before confirming.',
          push: 'Review and confirm today’s activity.',
        },
      ],
    },
    progress: {
      title: 'Your progress',
      subject: 'An update on your progress',
      variants: [
        {
          required: ['block_progress_percent'],
          app: 'Your current block has reached {{block_progress_percent}}%. It includes only eligible days.',
          push: 'Your current block is at {{block_progress_percent}}%.',
        },
        {
          required: ['protein_remaining_g'],
          app: '{{protein_remaining_g}} g of protein remain toward today’s planned reference.',
          push: '{{protein_remaining_g}} g of protein remain today.',
        },
        {
          required: [],
          app: 'Your progress was updated from the entries confirmed so far.',
          push: 'Your progress has a new update.',
        },
      ],
    },
    day_incomplete: {
      title: 'Day still incomplete',
      subject: 'Review a pending daily entry',
      variants: [
        {
          required: ['meal'],
          app: '{{meal}} has not been recorded or marked as skipped yet.',
          push: '{{meal}} still needs a response.',
        },
        {
          required: ['meal'],
          app: 'Confirm {{meal}}, reclassify another entry, or note that the meal was skipped.',
          push: 'Review the pending {{meal}} entry.',
        },
        {
          required: [],
          app: 'An expected meal still needs a response. Resolve it before the day closes.',
          push: 'A meal is pending before the day closes.',
        },
      ],
    },
    reevaluation: {
      title: 'Reassessment',
      subject: 'Your next BodyFlow reassessment',
      variants: [
        {
          required: ['next_reevaluation_date'],
          app: 'Your next reassessment is planned for {{next_reevaluation_date}}.',
          push: 'Reassessment planned for {{next_reevaluation_date}}.',
        },
        {
          required: ['next_reevaluation_date'],
          app: 'Set aside a moment on {{next_reevaluation_date}} to update your measurements and answers.',
          push: 'Prepare for your {{next_reevaluation_date}} reassessment.',
        },
        {
          required: [],
          app: 'A reassessment helps update your plan with more recent information.',
          push: 'Your reassessment is coming up.',
        },
      ],
    },
    reengagement: {
      title: 'Your plan is still here',
      subject: 'Return to your tracking at your pace',
      variants: [
        {
          required: [],
          app: 'Your history is still available. You can return with one simple entry.',
          push: 'Return with one simple entry.',
        },
        {
          required: [],
          app: 'You do not need to rebuild everything at once. Start with what happens today.',
          push: 'Start again with today.',
        },
        {
          required: [],
          app: 'When returning feels right, the next step can be small and specific.',
          push: 'Your next step can be small.',
        },
      ],
    },
    trial: {
      title: 'Trial period',
      subject: 'Information about your trial',
      variants: [
        {
          required: ['trial_days_remaining'],
          app: 'Your trial has {{trial_days_remaining}} days left to explore the available features.',
          push: '{{trial_days_remaining}} days remain in your trial.',
        },
        {
          required: ['trial_days_remaining'],
          app: 'You have {{trial_days_remaining}} days to decide whether BodyFlow fits your routine.',
          push: 'Explore BodyFlow for {{trial_days_remaining}} more days.',
        },
        {
          required: [],
          app: 'Use the trial period to explore the features that matter to you.',
          push: 'Explore the features during your trial.',
        },
      ],
    },
    paywall: {
      title: 'BodyFlow access',
      subject: 'Options for continuing with BodyFlow',
      variants: [
        {
          required: [],
          app: 'Some features require an active subscription. Review the options before deciding.',
          push: 'Review the subscription options.',
        },
        {
          required: [],
          app: 'The plans screen shows price, term, and renewal details before confirmation.',
          push: 'Check the details of the available plans.',
        },
        {
          required: [],
          app: 'Continue only if the subscription makes sense for your routine.',
          push: 'Decide about the subscription in your own time.',
        },
      ],
    },
    return_after_abandonment: {
      title: 'Welcome back',
      subject: 'Your return to BodyFlow',
      variants: [
        {
          required: [],
          app: 'Your return can begin with today, without rebuilding earlier days.',
          push: 'Come back by starting with today.',
        },
        {
          required: [],
          app: 'Your information remains organized so you can restart where it makes sense.',
          push: 'Your tracking is ready to continue.',
        },
        {
          required: [],
          app: 'One new entry is enough to put your tracking back in motion.',
          push: 'One new entry can mark your return.',
        },
      ],
    },
  },
}

function buildCatalog() {
  const groups = []
  for (const personality of personalities) {
    for (const [locale, contexts] of Object.entries(contextCopy)) {
      for (const [context, definition] of Object.entries(contexts)) {
        groups.push({
          personality,
          context,
          locale,
          variants: definition.variants.map((variant, index) => {
            const frame = toneFrames[locale][personality][index]
            return {
              variant: index + 1,
              required_variables: variant.required,
              renditions: {
                in_app: { body: frame.app(variant.app) },
                push: { title: definition.title, body: frame.push(variant.push) },
                email: { subject: definition.subject, body: frame.email(variant.app) },
              },
            }
          }),
        })
      }
    }
  }

  return {
    schema_version: 'bodyflow.coach-catalog.v1',
    pack: {
      slug: 'bodyflow-baseline-v1',
      label: 'BodyFlow baseline bilingual catalog v1',
    },
    groups,
  }
}

const outputUrl = new URL(
  '../../../content/coach-messages/bodyflow-baseline-v1.json',
  import.meta.url,
)
const outputPath = fileURLToPath(outputUrl)
await mkdir(new URL('../../../content/coach-messages/', import.meta.url), { recursive: true })
await writeFile(outputPath, `${JSON.stringify(buildCatalog(), null, 2)}\n`, 'utf8')

process.stdout.write(`Generated ${outputPath}\n`)
