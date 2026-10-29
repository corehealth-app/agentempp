const copies = {
  pt: {
    lang: 'pt-BR',
    title: 'Nova senha',
    intro: 'Escolha uma nova senha para sua conta Performe AI.',
    password: 'Nova senha',
    confirmation: 'Confirmar nova senha',
    submit: 'Salvar nova senha',
    working: 'Salvando…',
    mismatch: 'As senhas precisam ser iguais.',
    invalid: 'Este link é inválido ou expirou. Solicite uma nova recuperação no aplicativo.',
    uncertain:
      'Não foi possível confirmar a alteração. Tente entrar no aplicativo com a nova senha. Se não funcionar, solicite um novo link.',
    done: 'Senha alterada. Abra o Performe AI e entre com sua nova senha.',
    unavailable: 'A recuperação está temporariamente indisponível. Tente novamente mais tarde.',
    serviceUnavailable:
      'O serviço de recuperação está indisponível. Aguarde e abra este link novamente. Se não funcionar, solicite outro no aplicativo.',
    rejected:
      'A nova senha foi recusada. Solicite outro link e escolha uma senha diferente que atenda às regras do aplicativo.',
    noScript: 'Ative o JavaScript para definir sua nova senha.',
  },
  en: {
    lang: 'en',
    title: 'New password',
    intro: 'Choose a new password for your Performe AI account.',
    password: 'New password',
    confirmation: 'Confirm new password',
    submit: 'Save new password',
    working: 'Saving…',
    mismatch: 'The passwords must match.',
    invalid: 'This link is invalid or expired. Request a new password reset in the app.',
    uncertain:
      'We could not confirm the change. Try signing in to the app with your new password. If it does not work, request a new link.',
    done: 'Password changed. Open Performe AI and sign in with your new password.',
    unavailable: 'Password recovery is temporarily unavailable. Please try again later.',
    serviceUnavailable:
      'The recovery service is unavailable. Wait and open this link again. If it does not work, request another in the app.',
    rejected:
      'The new password was rejected. Request another link and choose a different password that meets the app requirements.',
    noScript: 'Enable JavaScript to set your new password.',
  },
}

export function passwordRecoveryPage(nonce: string, language: string, enabled: boolean): string {
  const c = language.toLowerCase().startsWith('en') ? copies.en : copies.pt
  // Only fixed, reviewed copy and a server-generated nonce enter this HTML.
  // The bearer hash is read from the fragment in memory, never rendered here.
  return `<!doctype html><html lang="${c.lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>${c.title} · Performe AI</title>
<style nonce="${nonce}">:root{color-scheme:light dark;font:17px/1.5 system-ui,sans-serif}*{box-sizing:border-box}body{margin:0;background:#043e40;color:#183535;min-height:100dvh;padding:28px 16px;display:grid;place-items:center}main{width:min(100%,440px);background:#fffdf7;border-radius:24px;padding:28px}p{margin:0 0 24px}h1{font-size:1.7rem;margin:12px 0}.brand{font-weight:700;color:#006c69}label{display:block;margin-top:20px;font-weight:600}input{font:inherit;width:100%;min-height:48px;border:1px solid #6e8381;border-radius:10px;padding:10px;background:#fff;color:#183535}button{font:inherit;font-weight:650;width:100%;min-height:48px;border:0;border-radius:12px;margin-top:24px;padding:12px;background:#006c69;color:white}button:disabled{opacity:.65}input:focus-visible,button:focus-visible{outline:3px solid #a64b00;outline-offset:3px}#status{margin-top:24px;overflow-wrap:anywhere}form[hidden]{display:none}@media(prefers-color-scheme:dark){main{background:#163b3b;color:#faf9f2}.brand{color:#a4e7dd}input{background:#0c292a;color:#faf9f2;border-color:#9ebcb7}button{background:#b3e8db;color:#052f30}input:focus-visible,button:focus-visible{outline-color:#ffcb88}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}</style></head>
<body><main><div class="brand">Performe AI</div><h1 tabindex="-1">${c.title}</h1><p>${c.intro}</p>
<form id="form" method="post" ${enabled ? '' : 'hidden'}><label for="password">${c.password}</label><input id="password" type="password" autocomplete="new-password" required maxlength="1024"><label for="confirmation">${c.confirmation}</label><input id="confirmation" type="password" autocomplete="new-password" required maxlength="1024"><button id="submit" type="submit">${c.submit}</button></form>
<p id="status" role="status" aria-live="polite">${enabled ? '' : c.unavailable}</p><noscript>${c.noScript}</noscript></main>
<script nonce="${nonce}">(() => {
  const copy = ${JSON.stringify(c)};
  const form = document.getElementById('form');
  const status = document.getElementById('status');
  const button = document.getElementById('submit');
  const password = document.getElementById('password');
  const confirmation = document.getElementById('confirmation');
  const params = new URLSearchParams(location.hash.slice(1));
  let token = params.get('token_hash');
  const valid = params.get('type') === 'recovery' && typeof token === 'string' && /^[!-~]{20,2048}$/.test(token);
  params.delete('token_hash');
  history.replaceState(null, '', location.pathname);
  if (!${enabled} || !valid) {
    token = null; form.hidden = true;
    status.textContent = ${enabled} ? copy.invalid : copy.unavailable;
    return;
  }
  let submitting = false;
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (submitting || !token) return;
    if (!password.value.trim() || password.value !== confirmation.value) {
      status.textContent = copy.mismatch; confirmation.focus(); return;
    }
    submitting = true; button.disabled = true; button.setAttribute('aria-busy', 'true');
    button.textContent = copy.working; status.textContent = '';
    let payload = JSON.stringify({token_hash:token,password:password.value,password_confirmation:confirmation.value});
    token = null; password.value = ''; confirmation.value = '';
    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(), 60000);
    try {
      const response = await fetch(location.pathname, {method:'POST',credentials:'omit',cache:'no-store',redirect:'error',signal:controller.signal,headers:{'Content-Type':'application/json'},body:payload});
      payload = '';
      const answer = await response.json();
      status.textContent = response.ok && answer.status === 'password_changed' ? copy.done
        : answer.status === 'new_link_required' ? copy.invalid
        : answer.status === 'password_rejected' ? copy.rejected
        : answer.status === 'recovery_unavailable' ? copy.serviceUnavailable : copy.uncertain;
    } catch { status.textContent = copy.uncertain; }
    finally {
      clearTimeout(deadline);
      payload = ''; form.hidden = true; button.removeAttribute('aria-busy');
      document.querySelector('h1').focus();
    }
  });
})();</script></body></html>`
}
