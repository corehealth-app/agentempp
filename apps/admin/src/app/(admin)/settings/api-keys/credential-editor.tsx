'use client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { saveCredential, deleteCredential } from './actions'
import { Eye, EyeOff, Save, Trash2 } from 'lucide-react'
import { useState, useTransition } from 'react'
import { toast } from 'sonner'

interface Props {
  service: string
  keyName: string
  label: string
  placeholder?: string
  type: 'text' | 'password' | 'textarea' | 'select'
  options?: string[]
  hasValue: boolean
}

export function CredentialEditor(props: Props) {
  const [value, setValue] = useState('')
  const [showValue, setShowValue] = useState(false)
  const [pending, startTransition] = useTransition()

  function onSave() {
    if (!value.trim()) {
      toast.error('Valor não pode estar vazio')
      return
    }
    startTransition(async () => {
      const result = await saveCredential({
        service: props.service,
        key_name: props.keyName,
        value: value.trim(),
      })
      if (result.error) {
        toast.error(result.error)
      } else {
        toast.success(`${props.label} salvo`)
        setValue('')
      }
    })
  }

  function onDelete() {
    if (!confirm(`Apagar ${props.service}.${props.keyName}?`)) return
    startTransition(async () => {
      const result = await deleteCredential({
        service: props.service,
        key_name: props.keyName,
      })
      if (result.error) toast.error(result.error)
      else toast.success('Apagado')
    })
  }

  return (
    <div className="flex gap-2">
      <div className="relative flex-1">
        {props.type === 'textarea' ? (
          <Textarea
            placeholder={props.placeholder}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            disabled={pending}
            rows={3}
          />
        ) : (
          <Input
            type={props.type === 'password' && !showValue ? 'password' : 'text'}
            placeholder={props.placeholder ?? `Novo valor para ${props.label}`}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            disabled={pending}
            className="pr-10"
          />
        )}
        {props.type === 'password' && (
          <button
            type="button"
            onClick={() => setShowValue((s) => !s)}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
          >
            {showValue ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        )}
      </div>
      <Button onClick={onSave} disabled={pending || !value.trim()} size="default">
        <Save className="h-4 w-4 mr-1" />
        Salvar
      </Button>
      {props.hasValue && (
        <Button onClick={onDelete} disabled={pending} variant="outline" size="default">
          <Trash2 className="h-4 w-4" />
        </Button>
      )}
    </div>
  )
}
