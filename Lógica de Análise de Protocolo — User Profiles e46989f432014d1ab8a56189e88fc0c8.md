# Código Cálculo Coleta de Dados

// ========================================
// AGENTE MPP - ANÁLISE DE PROTOCOLO v2
// Respeita tipo de medida (BF vs IMC)
// ========================================

// Variáveis de entrada (com parsing seguro)
const bfRaw = $('Profile User Data Edit').first().json['Body Fat Percent'];
const imcRaw = $('Formulas').first().json['IMC'];
const sex = $('Profile User Data Edit').first().json.Sex;
const trainingFreqRaw = $('Profile User Data Edit').first().json['Training Frequency'];
const bedtime = $('Profile User Data Edit').first().json.Bedtime || null;
const wakeTime = $('Profile User Data Edit').first().json['Wake Time'] || null;
const foodOrg = $('Profile User Data Edit').first().json['Food Organization'];

// Parse seguro para números
const bf = (bfRaw !== null && bfRaw !== undefined && bfRaw !== '' && parseFloat(bfRaw) > 0)
? parseFloat(bfRaw)
: null;
const imc = (imcRaw !== null && imcRaw !== undefined && imcRaw !== '')
? parseFloat(imcRaw)
: null;
const trainingFreq = (trainingFreqRaw !== null && trainingFreqRaw !== undefined)
? parseInt(trainingFreqRaw)
: 0;

// Constantes por sexo (apenas para BF)
const isHomem = sex === "Masculino";
const BF_LIMITE_RECOMP = isHomem ? 20 : 28;
const BF_LIMITE_GANHO = isHomem ? 19 : 27;
const BF_FAIXA_SAUDAVEL_MIN = isHomem ? 15 : 23;
const BF_FAIXA_SAUDAVEL_MAX = isHomem ? 19 : 27;

// Constantes para IMC (universal)
const IMC_LIMITE_RECOMP = 25;
const IMC_LIMITE_GANHO = 24;

// ========================================
// FUNÇÕES AUXILIARES
// ========================================

function formatNum(num, decimals = 1) {
if (num === null || num === undefined || isNaN(num)) return "N/D";
return Number(num).toFixed(decimals);
}

function calcularHorasSono(bedtime, wakeTime) {
if (!bedtime || !wakeTime) return null;

const bedParts = bedtime.split(':');
const wakeParts = wakeTime.split(':');
if (bedParts.length < 2 || wakeParts.length < 2) return null;

const bedH = parseInt(bedParts[0]);
const bedM = parseInt(bedParts[1]);
const wakeH = parseInt(wakeParts[0]);
const wakeM = parseInt(wakeParts[1]);

if (isNaN(bedH) || isNaN(bedM) || isNaN(wakeH) || isNaN(wakeM)) return null;

let bedMinutes = bedH * 60 + bedM;
let wakeMinutes = wakeH * 60 + wakeM;

// Tratar virada de meia-noite
if (wakeMinutes <= bedMinutes) {
wakeMinutes += 24 * 60;
}

let horasSono = (wakeMinutes - bedMinutes) / 60;

// ✅ NOVO: Validação de sono impossível (> 12h)
// Se detectado, provavelmente os campos foram invertidos
if (horasSono > 12) {
horasSono = 24 - horasSono; // Corrige automaticamente
}

return horasSono;
}

// Cálculo de meta de BF (escada progressiva)
function calcularBFGoal(bf) {
if (bf > 30) return bf - 10;
if (bf > 20) return 20;
if (bf > 18) return 18;
if (bf > 15) return 15;
return 10;
}

// Cálculo de meta de IMC (com margem mínima de 1 ponto)
function calcularIMCGoal(imc) {
const escadas = [30, 25, 23, 22, 21];
for (const meta of escadas) {
if (imc >= meta && (imc - meta) >= 1) return meta;
}
// Se nenhuma escada tem diferença >= 1, retorna a próxima escada abaixo do IMC atual
for (const meta of escadas) {
if (imc > meta) return meta;
}
return escadas[escadas.length - 1]; // fallback: 21
}

// ========================================
// ANÁLISE DE CRITÉRIOS COMPORTAMENTAIS
// ========================================

const horasSono = calcularHorasSono(bedtime, wakeTime);
const temBF = bf !== null;
const alimentacaoEstruturada = foodOrg === "Sim";
const treinoMinimo = trainingFreq >= 3;
const sonoMinimo = horasSono !== null && horasSono >= 6.5;

let criteriosGanhoAtendidos = [];
let criteriosGanhoFaltando = [];

// Verificar critérios de ganho
if (treinoMinimo) {
criteriosGanhoAtendidos.push("musculação ≥ 3x/semana");
} else {
criteriosGanhoFaltando.push(`musculação insuficiente (atual: ${trainingFreq}x/semana, mínimo: 3x)`);
}

if (sonoMinimo) {
criteriosGanhoAtendidos.push(`sono adequado (${formatNum(horasSono)}h)`);
} else if (horasSono !== null) {
criteriosGanhoFaltando.push(`sono insuficiente (${formatNum(horasSono)}h, mínimo: 6h30)`);
} else {
criteriosGanhoFaltando.push("horários de sono não informados");
}

if (alimentacaoEstruturada) {
criteriosGanhoAtendidos.push("alimentação estruturada");
} else {
criteriosGanhoFaltando.push("alimentação não estruturada");
}

// ========================================
// DECISÃO DE PROTOCOLO
// ========================================

let protocoloSugerido = null;
let podeEscolher = false;
let motivoBloqueio = [];
let situacaoComposicao = "";
let metaTipo = null;
let metaValor = null;

if (temBF) {
// ========== ANÁLISE COM BODY FAT ==========
metaTipo = "BF";
metaValor = calcularBFGoal(bf);

if (bf >= BF_LIMITE_RECOMP) {
// BF acima do limite → Recomposição obrigatória
protocoloSugerido = "Recomposição Corporal";
situacaoComposicao = `BF atual (${formatNum(bf)}%) está acima do limite de ${BF_LIMITE_RECOMP}% para ${sex.toLowerCase()}.`;
motivoBloqueio.push("gordura corporal acima do limite para ganho de massa");

} else if (bf <= BF_LIMITE_GANHO && criteriosGanhoFaltando.length === 0) {
// BF adequado + todos os critérios → Pode escolher
podeEscolher = true;
situacaoComposicao = `BF atual (${formatNum(bf)}%) está dentro da faixa saudável (${BF_FAIXA_SAUDAVEL_MIN}-${BF_FAIXA_SAUDAVEL_MAX}%).`;

} else if (bf <= BF_LIMITE_GANHO && criteriosGanhoFaltando.length > 0) {
// BF adequado mas faltam critérios → Recomposição
protocoloSugerido = "Recomposição Corporal";
situacaoComposicao = `BF atual (${formatNum(bf)}%) está adequado, mas faltam critérios comportamentais para ganho de massa.`;
motivoBloqueio = criteriosGanhoFaltando;

} else {
// Faixa intermediária (entre limite de ganho e recomp)
if (criteriosGanhoFaltando.length === 0) {
podeEscolher = true;
situacaoComposicao = `BF atual (${formatNum(bf)}%) está em faixa intermediária, mas critérios comportamentais OK.`;
} else {
protocoloSugerido = "Recomposição Corporal";
situacaoComposicao = `BF atual (${formatNum(bf)}%) está em faixa intermediária e faltam critérios comportamentais.`;
motivoBloqueio = criteriosGanhoFaltando;
}
}

} else if (imc !== null && !isNaN(imc)) {
// ========== ANÁLISE COM IMC (sem BF) ==========
metaTipo = "IMC";
metaValor = calcularIMCGoal(imc);

if (imc >= IMC_LIMITE_RECOMP) {
// IMC acima de 25 → Recomposição obrigatória
protocoloSugerido = "Recomposição Corporal";
situacaoComposicao = `IMC atual (${formatNum(imc)}) está acima de ${IMC_LIMITE_RECOMP}. BF não disponível.`;
motivoBloqueio.push("IMC acima do limite para ganho de massa");

} else if (imc <= IMC_LIMITE_GANHO && criteriosGanhoFaltando.length === 0) {
// IMC adequado + todos os critérios → Pode escolher
podeEscolher = true;
situacaoComposicao = `IMC atual (${formatNum(imc)}) está adequado. BF não disponível.`;

} else {
// IMC adequado mas faltam critérios → Recomposição
protocoloSugerido = "Recomposição Corporal";
situacaoComposicao = `IMC atual (${formatNum(imc)}). BF não disponível.`;
if (criteriosGanhoFaltando.length > 0) {
motivoBloqueio = criteriosGanhoFaltando;
} else {
motivoBloqueio.push("IMC em faixa limítrofe");
}
}

} else {
// Nenhuma métrica disponível
protocoloSugerido = "Recomposição Corporal";
situacaoComposicao = "Dados de composição corporal insuficientes (BF e IMC não disponíveis).";
motivoBloqueio.push("dados insuficientes para avaliação");
}

// ========================================
// MONTAR TEXTO EXPLICATIVO
// ========================================

let texto = `📊 ANÁLISE DO PERFIL DO USUÁRIO\\n\\n`;

// Dados de composição
texto += `**Dados de Composição Corporal:**\\n`;
texto += `• Sexo: ${sex}\\n`;
if (temBF) {
texto += `• Body Fat: ${formatNum(bf)}%\\n`;
}
if (imc !== null && !isNaN(imc)) {
texto += `• IMC: ${formatNum(imc)}\\n`;
}
texto += `• Métrica de referência: ${metaTipo || "N/D"}\\n`;
texto += `\\n`;

// Dados comportamentais
texto += `**Dados Comportamentais:**\\n`;
texto += `• Frequência de treino: ${trainingFreq}x/semana\\n`;
texto += `• Alimentação estruturada: ${alimentacaoEstruturada ? "Sim" : "Não"}\\n`;
if (horasSono !== null) {
texto += `• Sono estimado: ${formatNum(horasSono)}h/noite (${bedtime} às ${wakeTime})\\n`;
}
texto += `\\n`;

// Situação atual
texto += `**Situação Atual:**\\n`;
texto += `${situacaoComposicao}\\n\\n`;

// Decisão de protocolo
texto += `**Decisão de Protocolo:**\\n`;

if (podeEscolher) {
texto += `✅ O usuário PODE ESCOLHER o protocolo.\\n`;
texto += `Critérios atendidos:\\n`;
criteriosGanhoAtendidos.forEach(c => { texto +=   `• ${c}\\n`; });
texto += `\\nOpções disponíveis:\\n`;
texto +=   `1. Recomposição Corporal\\n`;
texto +=   `2. Ganho de Massa Muscular\\n`;
texto +=   `3. Manutenção\\n`;
texto += `\\n👉 AÇÃO: Perguntar ao usuário qual protocolo prefere.\\n`;

} else {
texto += `⚠️ Protocolo OBRIGATÓRIO: ${protocoloSugerido}\\n\\n`;

if (motivoBloqueio.length > 0) {
texto += `Motivos do bloqueio de Ganho de Massa:\\n`;
motivoBloqueio.forEach(m => { texto +=   `❌ ${m}\\n`; });
}

texto += `\\n👉 AÇÃO: Conduzir o usuário para ${protocoloSugerido} sem oferecer escolha.\\n`;
}

// Meta (agora com tipo correto)
if (metaTipo !== null && metaValor !== null) {
texto += `\\n**Meta de ${metaTipo}:** ${formatNum(metaValor)}${metaTipo === "BF" ? "%" : ""}\\n`;

if (metaTipo === "BF" && temBF && bf > metaValor) {
texto += `• Gordura a perder: ~${formatNum(bf - metaValor)} pontos percentuais de BF\\n`;
} else if (metaTipo === "IMC" && imc !== null && imc > metaValor) {
texto += `• IMC a reduzir: ~${formatNum(imc - metaValor)} pontos de IMC\\n`;
}
}

// ========================================
// RETORNO
// ========================================

return {
json: {
textoParaIA: texto,
protocoloSugerido: protocoloSugerido,
podeEscolher: podeEscolher,
metaTipo: metaTipo,
metaValor: metaValor,
metaAtual: metaTipo === "BF" ? bf : imc,  // ← novo
criteriosAtendidos: criteriosGanhoAtendidos,
criteriosFaltando: criteriosGanhoFaltando
}
};