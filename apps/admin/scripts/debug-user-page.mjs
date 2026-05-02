import { createClient } from '@supabase/supabase-js'
const svc = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } })

const id = '819e755d-14d4-4893-b252-31874db166ea'

console.log('=== fetch user ===')
const { data: user, error: e1 } = await svc.from('users').select('*').eq('id', id).maybeSingle()
console.log('user:', e1 || 'OK', user?.name)

console.log('=== fetch profile ===')
const { data: profile, error: e2 } = await svc.from('user_profiles').select('*').eq('user_id', id).maybeSingle()
console.log('profile:', e2 || 'OK', 'sex=', profile?.sex)

console.log('=== fetch progress ===')
const { data: progress, error: e3 } = await svc.from('user_progress').select('*').eq('user_id', id).maybeSingle()
console.log('progress:', e3 || 'OK', 'xp=', progress?.xp_total)

console.log('=== fetch messages ===')
const { data: messages, error: e4 } = await svc.from('messages').select('id, direction, content, content_type, agent_stage, model_used, cost_usd, created_at').eq('user_id', id).order('created_at', {ascending: false}).limit(50)
console.log('messages:', e4 || 'OK', 'count=', messages?.length)

console.log('=== fetch snapshots ===')
const { data: snapshots, error: e5 } = await svc.from('daily_snapshots').select('*').eq('user_id', id).order('date', {ascending:false}).limit(14)
console.log('snapshots:', e5 || 'OK', 'count=', snapshots?.length)

console.log('=== fetch subscription ===')
const { data: sub, error: e6 } = await svc.from('subscriptions').select('id, plan, status, current_period_end, trial_ends_at, cancel_at_period_end').eq('user_id', id).order('updated_at', {ascending:false}).limit(1).maybeSingle()
console.log('sub:', e6 || 'OK', sub)

if (sub && sub.cancel_at_period_end === undefined) console.log('!!! cancel_at_period_end UNDEFINED')
