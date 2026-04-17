import { useState, useEffect, useCallback, createContext, useContext } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import {
  useWriteContract,
  useWaitForTransactionReceipt,
} from 'wagmi'
import { CONTRACT_ADDRESS } from './blockchain/config'

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------
export type Address = `0x${string}`

// ---------------------------------------------------------------------------
// Constantes del contrato v4
// ---------------------------------------------------------------------------
export const TEMPERATURE_NOT_SET = -(1n << 255n)
export const TEMP_LOW_TENTHS  = 20n   // 2.0 °C
export const TEMP_HIGH_TENTHS = 80n   // 8.0 °C

export const CHECKPOINT_TYPES    = ['PICKUP', 'HUB', 'TRANSIT', 'DELIVERY', 'OTHER']
export const SHIPMENT_STATUSES   = ['CREADO', 'EN TRÁNSITO', 'EN HUB', 'PARA ENTREGA', 'ENTREGADO', 'DEVUELTO', 'CANCELADO']
export const INCIDENT_TYPES      = ['RETRASO', 'DAÑO', 'PÉRDIDA', 'VIOLACIÓN TEMPERATURA', 'NO AUTORIZADO']

export const STATUS_COLORS: Record<number, string> = {
  0: 'bg-sky-100 text-sky-700',
  1: 'bg-amber-100 text-amber-700',
  2: 'bg-purple-100 text-purple-700',
  3: 'bg-orange-100 text-orange-700',
  4: 'bg-emerald-100 text-emerald-700',
  5: 'bg-red-100 text-red-700',
  6: 'bg-slate-100 text-slate-500',
}

// ---------------------------------------------------------------------------
// Dark mode Context
// ---------------------------------------------------------------------------
export type DarkCtx = { dark: boolean; toggle: () => void }
export const DarkContext = createContext<DarkCtx>({ dark: false, toggle: () => {} })
export const useDark = () => useContext(DarkContext)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
export const shortAddr = (a: string | undefined) =>
  a ? `${a.slice(0, 6)}…${a.slice(-4)}` : '—'

export const isValidAddress = (a: string): a is Address =>
  /^0x[0-9a-fA-F]{40}$/.test(a)

export const tempToTenths = (raw: bigint | number): bigint => {
  if (typeof raw === 'bigint') return raw
  if (!Number.isFinite(raw)) return 0n
  return BigInt(Math.trunc(raw))
}

export const tempIsUnset = (raw: bigint | number) => tempToTenths(raw) === TEMPERATURE_NOT_SET

export const tempIsOutOfRange = (raw: bigint | number) => {
  const n = tempToTenths(raw)
  return n > TEMP_HIGH_TENTHS || n < TEMP_LOW_TENTHS
}

export const tempDisplay = (raw: bigint | number) => {
  const n = tempToTenths(raw)
  if (n === TEMPERATURE_NOT_SET) return '—'
  const sign = n < 0n ? '-' : ''
  const abs  = n < 0n ? -n : n
  return `${sign}${abs / 10n}.${abs % 10n} °C`
}

export const fmtTs = (ts: bigint | number) =>
  new Date(Number(ts) * 1000).toLocaleString('es-CO', {
    dateStyle: 'short',
    timeStyle: 'short',
  })

// ---------------------------------------------------------------------------
// Toast
// ---------------------------------------------------------------------------
export type Toast = { id: number; msg: string; type: 'ok' | 'err' | 'info' }
let _toastId = 0

export function useToast() {
  const [toasts, setToasts] = useState<Toast[]>([])
  const push = useCallback((msg: string, type: Toast['type'] = 'info') => {
    const clean = msg.replace(/^[⛔⚠️✅ℹ️]+\s*/, '')
    const id = ++_toastId
    setToasts(t => [...t, { id, msg: clean, type }])
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), 4500)
  }, [])
  return { toasts, push }
}

export function Toasts({ toasts }: { toasts: Toast[] }) {
  const styles: Record<Toast['type'], { bg: string; icon: string }> = {
    ok:   { bg: 'bg-emerald-600', icon: '✓' },
    err:  { bg: 'bg-red-600',     icon: '✕' },
    info: { bg: 'bg-slate-700',   icon: 'ℹ' },
  }
  return (
    <div style={{ position: 'fixed', bottom: '80px', right: '24px', zIndex: 9999, display: 'flex', flexDirection: 'column', gap: '8px', alignItems: 'flex-end' }}>
      {toasts.map(t => (
        <div
          key={t.id}
          style={{
            backgroundColor: t.type === 'ok' ? '#16a34a' : t.type === 'err' ? '#dc2626' : '#334155',
            color: '#ffffff',
            fontSize: '14px',
            fontWeight: 500,
            padding: '10px 16px',
            borderRadius: '10px',
            boxShadow: '0 4px 12px rgba(0,0,0,0.25)',
            maxWidth: '360px',
            display: 'flex',
            alignItems: 'flex-start',
            gap: '8px',
          }}
        >
          <span style={{ fontWeight: 700, flexShrink: 0 }}>{styles[t.type].icon}</span>
          <span>{t.msg}</span>
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Contract error mapping
// ---------------------------------------------------------------------------
const CONTRACT_ERRORS: Record<string, string> = {
  OnlyAdmin:                  'Solo el ADMIN puede realizar esta acción.',
  ActorInactive:              'Esta cuenta no está activa en el contrato.',
  OnlySendersCanCreate:       'Solo actores con rol SENDER pueden crear envíos.',
  OnlyCarrierOrHub:           'Solo actores con rol CARRIER o HUB pueden cambiar el estado.',
  OnlyRecipientCanConfirm:    'Solo el destinatario registrado puede confirmar la entrega.',
  OnlySenderCanCancel:        'Solo el remitente del envío puede cancelarlo.',
  ActorNotAssignedToShipment: 'Esta cuenta no está asignada a este envío.',
  AlreadyDelivered:           'Este envío ya fue confirmado como entregado.',
  AlreadyClosedShipment:      'El envío ya está en estado terminal (entregado, cancelado o devuelto).',
  CannotCancelAfterTransit:   'No se puede cancelar un envío en tránsito o en reparto.',
  CannotSetDeliveredDirectly: 'El estado entregado solo se puede asignar mediante Confirmar Entrega.',
  AlreadyRegisteredAndActive: 'Este actor ya está registrado y activo.',
  InvalidAddress:             'La dirección proporcionada no es válida.',
  InvalidRole:                'El rol seleccionado no es válido.',
  ShipmentNotFound:           'El envío no existe en el contrato.',
  MaxCheckpointsReached:      'Se alcanzó el límite máximo de checkpoints para este envío.',
  MaxIncidentsReached:        'Se alcanzó el límite máximo de incidencias para este envío.',
  ActorDoesNotExist:          'El actor no existe en el contrato.',
  CheckpointNotFound:         'El checkpoint no existe en el contrato.',
  IncidentNotFound:           'La incidencia no existe. Verifique el ID global de la incidencia.',
  NotPendingAdmin:            'No hay una transferencia de administración pendiente.',
}

const ERROR_SELECTORS: Record<string, string> = {
  '0x47556579': 'OnlyAdmin',
  '0x2a718ceb': 'ActorInactive',
  '0xf5b43415': 'OnlySendersCanCreate',
  '0xef92a56b': 'OnlyCarrierOrHub',
  '0x007b0240': 'OnlyRecipientCanConfirm',
  '0x3f77ea3e': 'OnlySenderCanCancel',
  '0xd40c3d21': 'ActorNotAssignedToShipment',
  '0xb9f79653': 'AlreadyDelivered',
  '0x8b167a50': 'AlreadyClosedShipment',
  '0x22bc9caa': 'CheckpointNotFound',
  '0xae30d3b0': 'IncidentNotFound',
  '0x84e54a24': 'ShipmentNotFound',
  '0x058d9a1b': 'NotPendingAdmin',
  '0xb86c1b1c': 'CannotCancelAfterTransit',
  '0x9e96bb69': 'CannotSetDeliveredDirectly',
  '0x7ca2767c': 'AlreadyRegisteredAndActive',
  '0xe6c4247b': 'InvalidAddress',
  '0xd954416a': 'InvalidRole',
  '0x925c5958': 'ShipmentNotFound',
  '0x3ca72e78': 'MaxCheckpointsReached',
  '0xcdb7a76c': 'MaxIncidentsReached',
  '0x6f46a365': 'ActorDoesNotExist',
}

export function parseContractError(error: any): string {
  if (!error) return 'Error desconocido en la transacción.'

  let rawStr = ''
  try { rawStr = JSON.stringify(error, (_k, v) => typeof v === 'bigint' ? v.toString() : v) } catch { rawStr = String(error) }
  const selectorMatch = rawStr.match(/custom error (0x[0-9a-fA-F]{8})/)
  if (selectorMatch) {
    const selector = selectorMatch[1].toLowerCase()
    const errorName = ERROR_SELECTORS[selector]
    if (errorName && CONTRACT_ERRORS[errorName]) return CONTRACT_ERRORS[errorName]
    if (errorName) return `Error del contrato: ${errorName}`
  }

  const msgStrings = [
    error?.message,
    error?.shortMessage,
    error?.cause?.message,
    error?.cause?.shortMessage,
    error?.cause?.cause?.message,
    error?.cause?.cause?.shortMessage,
    ...(error?.cause?.metaMessages ?? []),
    ...(error?.cause?.cause?.metaMessages ?? []),
  ].filter(Boolean).join(' ')

  for (const [key] of Object.entries(CONTRACT_ERRORS)) {
    if (new RegExp(`\\b${key}[\\s(]`).test(msgStrings) || msgStrings.endsWith(key)) {
      return CONTRACT_ERRORS[key]
    }
  }

  const candidates: string[] = [
    error?.data?.errorName,
    error?.cause?.data?.errorName,
    error?.cause?.cause?.data?.errorName,
    error?.cause?.cause?.cause?.data?.errorName,
  ].filter(Boolean)

  for (const name of candidates) {
    if (CONTRACT_ERRORS[name]) return CONTRACT_ERRORS[name]
  }

  if (msgStrings.includes('User rejected') || msgStrings.includes('user rejected') || msgStrings.includes('4001')) {
    return 'Transacción rechazada en MetaMask.'
  }

  return (
    error?.cause?.cause?.shortMessage ??
    error?.cause?.shortMessage ??
    error?.shortMessage ??
    error?.message ??
    'Error en la transacción.'
  )
}

// ---------------------------------------------------------------------------
// useTx hook
// ---------------------------------------------------------------------------
export function useTx(push: ReturnType<typeof useToast>['push'], queryKeys?: any[][]) {
  const { writeContract, data: txHash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })
  const queryClient = useQueryClient()

  useEffect(() => {
    if (isSuccess) {
      push('Transacción confirmada', 'ok')
      if (queryKeys && queryKeys.length > 0) {
        queryKeys.forEach(key => queryClient.invalidateQueries({ queryKey: key }))
      } else {
        queryClient.invalidateQueries()
      }
    }
  }, [isSuccess])

  useEffect(() => {
    if (error) push(parseContractError(error), 'err')
  }, [error])

  return {
    write: writeContract,
    isPending: isPending || isConfirming,
    txHash,
    isSuccess,
  }
}

// ---------------------------------------------------------------------------
// Shared styles
// ---------------------------------------------------------------------------
export const btnPrimary = (disabled = false): React.CSSProperties => ({
  fontFamily: 'Inter, system-ui, sans-serif',
  fontSize: '15px',
  fontWeight: 600,
  backgroundColor: disabled ? '#86efac' : '#16a34a',
  color: '#ffffff',
  paddingTop: '10px',
  paddingBottom: '10px',
  paddingLeft: '32px',
  paddingRight: '32px',
  borderRadius: '10px',
  border: 'none',
  cursor: disabled ? 'not-allowed' : 'pointer',
  textTransform: 'uppercase' as const,
  letterSpacing: '0.04em',
  transition: 'background-color 0.15s',
  opacity: disabled ? 0.7 : 1,
})

export const btnDanger = (disabled = false): React.CSSProperties => ({
  ...btnPrimary(disabled),
  backgroundColor: disabled ? '#fca5a5' : '#dc2626',
})

export const btnSecondary: React.CSSProperties = {
  fontFamily: 'Inter, system-ui, sans-serif',
  fontSize: '13px',
  fontWeight: 600,
  backgroundColor: '#eef2ff',
  color: '#4338ca',
  border: '1px solid #c7d2fe',
  padding: '7px 18px',
  borderRadius: '8px',
  cursor: 'pointer',
  textTransform: 'uppercase' as const,
  letterSpacing: '0.03em',
}

export function inputStyle(dark: boolean, error = false): React.CSSProperties {
  return {
    width: '100%',
    fontFamily: 'Inter, system-ui, sans-serif',
    fontSize: '15px',
    padding: '8px 12px',
    border: `1px solid ${error ? '#fca5a5' : dark ? '#334155' : '#e2e8f0'}`,
    borderRadius: '8px',
    outline: 'none',
    backgroundColor: dark ? '#0f172a' : '#f8fafc',
    color: dark ? '#f1f5f9' : '#1e293b',
    boxSizing: 'border-box' as const,
    transition: 'border-color 0.15s',
  }
}

export function labelStyle(dark: boolean): React.CSSProperties {
  return {
    fontFamily: 'Inter, system-ui, sans-serif',
    fontSize: '12px',
    fontWeight: 600,
    color: dark ? '#94a3b8' : '#475569',
    textTransform: 'uppercase' as const,
    letterSpacing: '0.05em',
    display: 'block',
    marginBottom: '4px',
  }
}

export const TH_STYLE: React.CSSProperties = {
  padding: '9px 12px',
  fontSize: '11px',
  fontWeight: 700,
  color: '#ffffff',
  textTransform: 'uppercase',
  letterSpacing: '0.07em',
  borderBottom: '1px solid rgba(0,0,0,0.15)',
  borderRight: '1px solid rgba(0,0,0,0.1)',
  backgroundColor: '#475569',
  position: 'sticky',
  top: 0,
  zIndex: 2,
}

export const TD_STYLE: React.CSSProperties = {
  padding: '8px 12px',
  fontSize: '13px',
  borderBottom: '0.5px solid #e2e8f0',
  borderRight: '0.5px solid #f1f5f9',
  verticalAlign: 'top',
  wordBreak: 'break-word',
  maxWidth: '200px',
}

// ---------------------------------------------------------------------------
// Base UI components
// ---------------------------------------------------------------------------
export function Card({ children, accent = 'blue', className = '' }: {
  children: React.ReactNode
  accent?: string
  className?: string
}) {
  const { dark } = useDark()
  const accents: Record<string, string> = {
    blue:    'border-blue-500',
    indigo:  'border-indigo-500',
    emerald: 'border-emerald-500',
    orange:  'border-orange-500',
    purple:  'border-purple-500',
    slate:   'border-slate-400',
    cyan:    'border-cyan-500',
    teal:    'border-teal-500',
  }
  return (
    <section
      className={`rounded-2xl p-6 shadow-sm ${className}`}
      style={{
        backgroundColor: dark ? '#1e293b' : '#ffffff',
        border: dark ? '1px solid #334155' : '1px solid #e2e8f0',
      }}
    >
      <div className={`border-l-4 ${accents[accent] ?? 'border-blue-500'} pl-4 mb-5`}>
        {children}
      </div>
    </section>
  )
}

export function SectionHeader({ children }: { children: React.ReactNode }) {
  const { dark } = useDark()
  return (
    <section
      style={{
        backgroundColor: dark ? '#1e293b' : '#ffffff',
        border: dark ? '1px solid #334155' : '1px solid #e2e8f0',
        borderRadius: '16px',
        boxShadow: '0 1px 3px rgba(0,0,0,0.08)',
        overflow: 'hidden',
      }}
    >
      {children}
    </section>
  )
}

export function FieldError({ msg }: { msg?: string }) {
  if (!msg) return null
  return (
    <span style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '12px', color: '#ef4444', marginTop: '3px', display: 'block' }}>
      ⚠ {msg}
    </span>
  )
}

// ---------------------------------------------------------------------------
// useKnownActors hook (used by both ActorsPanel and shared state)
// ---------------------------------------------------------------------------
export function useKnownActors() {
  const key = `actors_${CONTRACT_ADDRESS}`
  const load = (): string[] => {
    try { return JSON.parse(localStorage.getItem(key) ?? '[]') }
    catch { return [] }
  }
  const [addrs, setAddrs] = useState<string[]>(load)
  const set = useCallback((list: string[]) => {
    localStorage.setItem(key, JSON.stringify(list))
    setAddrs(list)
  }, [key])
  return { addrs, set }
}
