import { useState, useEffect, useCallback, useRef, createContext, useContext } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import {
  useConnect,
  useAccount,
  useDisconnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  usePublicClient,
} from 'wagmi'
import { CONTRACT_ADDRESS, ABI, ACTOR_ROLES } from './blockchain/config'

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------
type Address = `0x${string}`

// ---------------------------------------------------------------------------
// Constantes del contrato v4
// ---------------------------------------------------------------------------
const TEMPERATURE_NOT_SET = -(1n << 255n)
const TEMP_LOW_TENTHS  = 20n   // 2.0 °C
const TEMP_HIGH_TENTHS = 80n   // 8.0 °C

const CHECKPOINT_TYPES    = ['Pickup', 'Hub', 'Transit', 'Delivery', 'Other']
const SHIPMENT_STATUSES   = ['Creado', 'En tránsito', 'En hub', 'Para entrega', 'Entregado', 'Devuelto', 'Cancelado']
const INCIDENT_TYPES      = ['Retraso', 'Daño', 'Pérdida', 'Temp. violación', 'No autorizado']

const STATUS_COLORS: Record<number, string> = {
  0: 'bg-sky-100 text-sky-700',
  1: 'bg-amber-100 text-amber-700',
  2: 'bg-purple-100 text-purple-700',
  3: 'bg-orange-100 text-orange-700',
  4: 'bg-emerald-100 text-emerald-700',
  5: 'bg-red-100 text-red-700',
  6: 'bg-slate-100 text-slate-500',
}

// ---------------------------------------------------------------------------
// [FIX-UI] Tokens de color centralizados — dark mode por Context, no por prop
// ---------------------------------------------------------------------------
type DarkCtx = { dark: boolean; toggle: () => void }
const DarkContext = createContext<DarkCtx>({ dark: false, toggle: () => {} })
const useDark = () => useContext(DarkContext)

// Token helper: devuelve el valor según dark/light
function tok(dark: boolean, darkVal: string, lightVal: string) {
  return dark ? darkVal : lightVal
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const shortAddr = (a: string | undefined) =>
  a ? `${a.slice(0, 6)}…${a.slice(-4)}` : '—'

const isValidAddress = (a: string): a is Address =>
  /^0x[0-9a-fA-F]{40}$/.test(a)

const tempToTenths = (raw: bigint | number): bigint => {
  if (typeof raw === 'bigint') return raw
  if (!Number.isFinite(raw)) return 0n
  return BigInt(Math.trunc(raw))
}

const tempIsUnset = (raw: bigint | number) => tempToTenths(raw) === TEMPERATURE_NOT_SET

const tempIsOutOfRange = (raw: bigint | number) => {
  const n = tempToTenths(raw)
  return n > TEMP_HIGH_TENTHS || n < TEMP_LOW_TENTHS
}

const tempDisplay = (raw: bigint | number) => {
  const n = tempToTenths(raw)
  if (n === TEMPERATURE_NOT_SET) return '—'
  const sign = n < 0n ? '-' : ''
  const abs  = n < 0n ? -n : n
  return `${sign}${abs / 10n}.${abs % 10n} °C`
}

const fmtTs = (ts: bigint | number) =>
  new Date(Number(ts) * 1000).toLocaleString('es-CO', {
    dateStyle: 'short',
    timeStyle: 'short',
  })

// ---------------------------------------------------------------------------
// [FIX-ERR] Toast — icono integrado en el componente, no en el string del mensaje
// ---------------------------------------------------------------------------
type Toast = { id: number; msg: string; type: 'ok' | 'err' | 'info' }
let _toastId = 0

function useToast() {
  const [toasts, setToasts] = useState<Toast[]>([])
  const push = useCallback((msg: string, type: Toast['type'] = 'info') => {
    // Limpiar emojis hardcodeados que venían de CONTRACT_ERRORS
    const clean = msg.replace(/^[⛔⚠️✅ℹ️]+\s*/, '')
    const id = ++_toastId
    setToasts(t => [...t, { id, msg: clean, type }])
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), 4500)
  }, [])
  return { toasts, push }
}

// [FIX-ERR] Icono por tipo dentro del componente Toasts
function Toasts({ toasts }: { toasts: Toast[] }) {
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
// Mapeo de errores del contrato — sin emojis (el icono lo pone el componente)
// ---------------------------------------------------------------------------
const CONTRACT_ERRORS: Record<string, string> = {
  OnlyAdmin:                  'Solo el admin puede realizar esta acción.',
  ActorInactive:              'Tu cuenta no está activa en el contrato.',
  OnlySendersCanCreate:       'Solo actores con rol Sender pueden crear envíos.',
  OnlyCarrierOrHub:           'Solo Carrier o Hub pueden cambiar el estado.',
  OnlyRecipientCanConfirm:    'Solo el destinatario registrado puede confirmar la entrega.',
  OnlySenderCanCancel:        'Solo el remitente del envío puede cancelarlo.',
  ActorNotAssignedToShipment: 'Tu cuenta no está asignada a este envío.',
  AlreadyDelivered:           'Este envío ya fue confirmado como entregado.',
  AlreadyClosedShipment:      'El envío ya está en estado terminal (entregado, cancelado o devuelto).',
  CannotCancelAfterTransit:   'No se puede cancelar un envío en tránsito o en reparto.',
  CannotSetDeliveredDirectly: 'El estado Entregado solo se puede asignar mediante Confirmar Entrega.',
  AlreadyRegisteredAndActive: 'Este actor ya está registrado y activo.',
  InvalidAddress:             'La dirección proporcionada no es válida.',
  InvalidRole:                'El rol seleccionado no es válido.',
  ShipmentNotFound:           'El ID de envío no existe en el contrato.',
  MaxCheckpointsReached:      'Se alcanzó el límite máximo de checkpoints para este envío.',
  MaxIncidentsReached:        'Se alcanzó el límite máximo de incidencias para este envío.',
  ActorDoesNotExist:          'El actor no existe en el contrato.',
}

// Selectores keccak256 de los errores personalizados del contrato
// Calculados con keccak256("ErrorName()").slice(0,4)
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

function parseContractError(error: any): string {
  if (!error) return 'Error desconocido en la transacción.'

  // 1. Intentar decodificar selector de error personalizado desde el mensaje raw
  let rawStr = ''
  try { rawStr = JSON.stringify(error, (_k, v) => typeof v === 'bigint' ? v.toString() : v) } catch { rawStr = String(error) }
  const selectorMatch = rawStr.match(/custom error (0x[0-9a-fA-F]{8})/)
  if (selectorMatch) {
    const selector = selectorMatch[1].toLowerCase()
    const errorName = ERROR_SELECTORS[selector]
    if (errorName && CONTRACT_ERRORS[errorName]) return CONTRACT_ERRORS[errorName]
    if (errorName) return `Error del contrato: ${errorName}`
  }

  // 2. Buscar el nombre del error directamente en todos los strings del error
  //    Usar lista específica de strings (NO rawStr que incluye el mapa completo)
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
    // Buscar el nombre como palabra completa seguida de ( o espacio o fin
    if (new RegExp(`\\b${key}[\\s(]`).test(msgStrings) || msgStrings.endsWith(key)) {
      return CONTRACT_ERRORS[key]
    }
  }

  // 3. Rutas estándar de viem cuando el ABI incluye los errores
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
// useTx — [FIX-ERR] invalidateQueries con clave específica
// ---------------------------------------------------------------------------
function useTx(push: ReturnType<typeof useToast>['push'], queryKeys?: any[][]) {
  const { writeContract, data: txHash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })
  const queryClient = useQueryClient()

  useEffect(() => {
    if (isSuccess) {
      push('Transacción confirmada', 'ok')
      // [FIX-ERR] Invalidar solo las queries afectadas si se especifican; si no, invalidar todo
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
// Estilos compartidos
// ---------------------------------------------------------------------------

// [FIX-UI] Botón primario — verde oscuro accesible en lugar de rgb(0,255,0)
const btnPrimary = (disabled = false): React.CSSProperties => ({
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

const btnDanger = (disabled = false): React.CSSProperties => ({
  ...btnPrimary(disabled),
  backgroundColor: disabled ? '#fca5a5' : '#dc2626',
})

const btnSecondary: React.CSSProperties = {
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

// [FIX-UI] Input unificado — recibe dark del context
function inputStyle(dark: boolean, error = false): React.CSSProperties {
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

function labelStyle(dark: boolean): React.CSSProperties {
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

// [FIX-UI] TH/TD de tablas — gris neutro, bordes finos
const TH_STYLE: React.CSSProperties = {
  padding: '9px 12px',
  fontSize: '11px',
  fontWeight: 700,
  color: '#ffffff',
  textTransform: 'uppercase',
  letterSpacing: '0.07em',
  borderBottom: '1px solid rgba(0,0,0,0.15)',
  borderRight: '1px solid rgba(0,0,0,0.1)',
  backgroundColor: '#475569', // gris pizarra, no verde
}
const TD_STYLE: React.CSSProperties = {
  padding: '8px 12px',
  fontSize: '13px',
  borderBottom: '0.5px solid #e2e8f0',
  borderRight: '0.5px solid #f1f5f9',
  verticalAlign: 'top',
  wordBreak: 'break-word',
  maxWidth: '200px',
}

// ---------------------------------------------------------------------------
// Componentes base
// ---------------------------------------------------------------------------
function Card({ children, accent = 'blue', className = '' }: {
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

function SectionHeader({ children }: { children: React.ReactNode }) {
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

function FieldError({ msg }: { msg?: string }) {
  if (!msg) return null
  return (
    <span style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '12px', color: '#ef4444', marginTop: '3px', display: 'block' }}>
      ⚠ {msg}
    </span>
  )
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------
type TabId = 'actores' | 'envios' | 'operaciones' | 'trazabilidad'

const TABS: { id: TabId; label: string; icon: string }[] = [
  { id: 'actores',      label: 'Actores',      icon: '👥' },
  { id: 'envios',       label: 'Envíos',        icon: '📦' },
  { id: 'operaciones',  label: 'Operaciones',   icon: '⚙️' },
  { id: 'trazabilidad', label: 'Trazabilidad',  icon: '🔍' },
]

export default function App() {
  const { connect, connectors } = useConnect()
  const { address, isConnected } = useAccount()
  const { disconnect } = useDisconnect()
  const { toasts, push } = useToast()
  const queryClient = useQueryClient()
  const [dark, setDark] = useState(false)
  const [activeTab, setActiveTab] = useState<TabId>('actores')

  const connectWallet = () => {
    const c = connectors.find(c => c.id === 'injected') ?? connectors[0]
    connect({ connector: c })
  }

  const handleDisconnect = () => {
    disconnect()
    // Limpiar caché de wagmi para permitir reconexión inmediata
    queryClient.clear()
  }

  const GREEN_HEADER = '#166534' // [FIX-UI] verde oscuro accesible para el header

  return (
    <DarkContext.Provider value={{ dark, toggle: () => setDark(d => !d) }}>
      <div style={{
        minHeight: '100vh',
        backgroundColor: dark ? '#0f172a' : '#f8fafc',
        color: dark ? '#f1f5f9' : '#1e293b',
        fontFamily: 'Inter, system-ui, sans-serif',
        fontSize: '15px',
      }}>

        {/* ── ENCABEZADO + PESTAÑAS ── */}
        <div style={{ position: 'sticky', top: 0, zIndex: 50 }}>
          <nav style={{ backgroundColor: GREEN_HEADER, padding: '8px 24px' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px' }}>

              {/* Dark mode toggle */}
              <div style={{ flex: '0 0 auto' }}>
                <button
                  onClick={() => setDark(d => !d)}
                  style={{ fontSize: '15px', backgroundColor: 'rgba(255,255,255,0.15)', color: '#ffffff', border: '1px solid rgba(255,255,255,0.4)', padding: '4px 12px', borderRadius: '8px', cursor: 'pointer' }}
                  title={dark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro'}
                >
                  {dark ? '☀️' : '🌙'}
                </button>
              </div>

              {/* Título central */}
              <div style={{ flex: '1 1 auto', textAlign: 'center' }}>
                <div style={{ fontWeight: 800, color: '#ffffff', fontSize: 'clamp(15px, 3vw, 22px)', letterSpacing: '-0.03em', lineHeight: 1.1 }}>
                  LOGICHAIN <span style={{ color: 'rgba(255,255,255,0.55)', fontWeight: 400 }}>v4</span>
                </div>
                <code style={{ fontSize: '12px', color: 'rgba(255,255,255,0.75)', fontFamily: 'monospace', display: 'block' }}>
                  CONTRACT: {shortAddr(CONTRACT_ADDRESS)}
                </code>
                {isConnected && (
                  <span style={{ fontSize: '12px', fontFamily: 'monospace', backgroundColor: 'rgba(255,255,255,0.15)', color: '#ffffff', border: '1px solid rgba(255,255,255,0.35)', padding: '1px 8px', borderRadius: '6px', display: 'inline-flex', alignItems: 'center', gap: '5px', marginTop: '2px' }}>
                    <span style={{ fontSize: '10px', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.04em', fontFamily: 'Inter, sans-serif' }}>Cuenta activa:</span>
                    ● {shortAddr(address)}
                  </span>
                )}
                {!isConnected && (
                  <button
                    onClick={connectWallet}
                    style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '13px', fontWeight: 700, backgroundColor: 'rgb(0,255,0)', color: '#000000', padding: '6px 18px', borderRadius: '8px', border: 'none', cursor: 'pointer', textTransform: 'uppercase', letterSpacing: '0.04em', marginTop: '4px' }}
                  >
                    Conectar MetaMask
                  </button>
                )}
              </div>

              {/* Desconectar */}
              <div style={{ flex: '0 0 auto' }}>
                {isConnected && (
                  <button
                    onClick={() => handleDisconnect()}
                    style={{ fontSize: '12px', fontWeight: 600, backgroundColor: 'rgba(255,255,255,0.18)', color: '#ffffff', padding: '5px 12px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.35)', cursor: 'pointer', textTransform: 'uppercase', lineHeight: 1.3, textAlign: 'center' }}
                  >
                    Desconectar
                  </button>
                )}
              </div>
            </div>
          </nav>

          {/* Pestañas */}
          {isConnected && (
            <div style={{
              backgroundColor: dark ? '#1e293b' : '#ffffff',
              borderBottom: `1px solid ${dark ? '#334155' : '#e2e8f0'}`,
              display: 'flex',
              justifyContent: 'center',
              boxShadow: '0 2px 8px rgba(0,0,0,0.06)',
            }}>
              {TABS.map(tab => {
                const isActive = activeTab === tab.id
                return (
                  <button
                    key={tab.id}
                    onClick={() => setActiveTab(tab.id)}
                    style={{
                      fontFamily: 'Inter, system-ui, sans-serif',
                      fontSize: '13px',
                      fontWeight: isActive ? 700 : 400,
                      color: isActive ? GREEN_HEADER : (dark ? '#94a3b8' : '#64748b'),
                      backgroundColor: 'transparent',
                      border: 'none',
                      borderBottom: isActive ? `3px solid ${GREEN_HEADER}` : '3px solid transparent',
                      padding: '0 28px',
                      height: '44px',
                      cursor: 'pointer',
                      textTransform: 'uppercase',
                      letterSpacing: '0.05em',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px',
                      transition: 'all 0.15s',
                    }}
                  >
                    <span>{tab.icon}</span>
                    {tab.label}
                  </button>
                )
              })}
            </div>
          )}
        </div>

        {/* Pantalla desconectado */}
        {!isConnected ? (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', paddingTop: '140px', paddingBottom: '140px', gap: '20px', textAlign: 'center' }}>
            <div style={{ fontSize: '42px', fontWeight: 800, color: dark ? '#334155' : '#e2e8f0', letterSpacing: '-0.05em' }}>LOGICHAIN</div>
            <p style={{ fontSize: '14px', color: dark ? '#94a3b8' : '#64748b', maxWidth: '260px' }}>
              Sistema de trazabilidad logística on-chain. Conecta tu wallet para continuar.
            </p>
            <button onClick={connectWallet} style={btnPrimary()}>
              Conectar con MetaMask
            </button>
          </div>
        ) : (
          <main style={{ maxWidth: '1200px', minWidth: '1100px', width: '100%', margin: '0 auto', padding: '24px 16px 100px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: '28px' }}>
            {activeTab === 'actores'      && <><RolesGovernance push={push} /><ActorsList push={push} /></>}
            {activeTab === 'envios'       && <><ShippingPanel push={push} /><ShipmentsTable /></>}
            {activeTab === 'operaciones'  && <OperationsPanel push={push} />}
            {activeTab === 'trazabilidad' && <TraceabilityPanel />}
          </main>
        )}

        <Toasts toasts={toasts} />

        <footer style={{ position: 'fixed', bottom: 0, left: 0, right: 0, zIndex: 40, backgroundColor: GREEN_HEADER, height: '50px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
          <p style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '14px', fontWeight: 700, color: '#ffffff', margin: 0 }}>
            LUIS CARLOS GRACIA PUENTES — TFM2 CODECRYPTO
          </p>
          <p style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '12px', fontWeight: 400, color: 'rgba(255,255,255,0.75)', margin: '2px 0 0' }}>
            Todos los derechos reservados © 2026
          </p>
        </footer>
      </div>
    </DarkContext.Provider>
  )
}

// ---------------------------------------------------------------------------
// 1. Gobernanza — Registrar Actor
// ---------------------------------------------------------------------------
function RolesGovernance({ push }: { push: ReturnType<typeof useToast>['push'] }) {
  const { dark } = useDark()
  const [form, setForm] = useState({ addr: '', name: '', role: 0, loc: '' })
  const [errors, setErrors] = useState<Record<string, string>>({})
  const { write, isPending, isSuccess } = useTx(push)
  const publicClient = usePublicClient()
  const { address } = useAccount()

  const rolesFiltered = ACTOR_ROLES.slice(1)

  const validate = () => {
    const e: Record<string, string> = {}
    if (!isValidAddress(form.addr)) e.addr = 'Dirección inválida (debe ser 0x…40 hex)'
    if (!form.name.trim()) e.name = 'Campo requerido'
    if (!form.loc.trim()) e.loc = 'Campo requerido'
    if (!form.role || form.role === 0) e.role = 'Seleccione un rol'
    setErrors(e)
    return Object.keys(e).length === 0
  }

  const handleRegister = async () => {
    if (!validate()) return
    try {
      await publicClient?.simulateContract({
        address: CONTRACT_ADDRESS,
        abi: ABI,
        functionName: 'registerActor',
        args: [form.name, form.role, form.loc, form.addr as Address],
        account: address as Address,
      })
    } catch (e: any) {
      push(parseContractError(e), 'err')
      return
    }
    const key = `actors_${CONTRACT_ADDRESS}`
    const current: string[] = JSON.parse(localStorage.getItem(key) ?? '[]')
    if (!current.includes(form.addr)) {
      localStorage.setItem(key, JSON.stringify([...current, form.addr]))
    }
    write({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: 'registerActor',
      args: [form.name, form.role, form.loc, form.addr as Address],
    })
  }

  useEffect(() => {
    if (isSuccess) setForm({ addr: '', name: '', role: 1, loc: '' })
  }, [isSuccess])

  return (
    <Card accent="blue">
      <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 4px' }}>
        Registrar Actor{' '}
        <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
          (Solo el admin del contrato puede registrar actores.)
        </span>
      </h2>

      <div style={{ marginTop: '16px', display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '12px' }}>
        <div>
          <label style={labelStyle(dark)}>Wallet address</label>
          <input placeholder="0x1234…abcd" value={form.addr} onChange={e => setForm({ ...form, addr: e.target.value })} style={inputStyle(dark, !!errors.addr)} />
          <FieldError msg={errors.addr} />
        </div>
        <div>
          <label style={labelStyle(dark)}>Nombre</label>
          <input placeholder="Nombre" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} style={inputStyle(dark, !!errors.name)} />
          <FieldError msg={errors.name} />
        </div>
        <div>
          <label style={labelStyle(dark)}>Rol</label>
          <select value={form.role} onChange={e => setForm({ ...form, role: Number(e.target.value) })} style={inputStyle(dark, !!errors.role)}>
            <option value={0} disabled>— Seleccione un rol —</option>
            {rolesFiltered.map((r, i) => <option key={i} value={i + 1}>{r}</option>)}
          </select>
          <FieldError msg={errors.role} />
        </div>
        <div>
          <label style={labelStyle(dark)}>Ubicación</label>
          <input placeholder="Ubicación" value={form.loc} onChange={e => setForm({ ...form, loc: e.target.value })} style={inputStyle(dark, !!errors.loc)} />
          <FieldError msg={errors.loc} />
        </div>
      </div>

      <div style={{ display: 'flex', justifyContent: 'center', marginTop: '20px' }}>
        <button onClick={handleRegister} disabled={isPending} style={btnPrimary(isPending)}>
          {isPending ? '⏳ Procesando…' : 'Registrar Actor'}
        </button>
      </div>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// 2. Lista de actores
// ---------------------------------------------------------------------------
const ROLE_ICONS: Record<number, string>  = { 0: '⚙️', 1: '🏭', 2: '🚛', 3: '🏪', 4: '📦', 5: '🔍' }
const ROLE_COLORS: Record<number, string> = {
  1: 'bg-blue-50 text-blue-700 border-blue-200',
  2: 'bg-amber-50 text-amber-700 border-amber-200',
  3: 'bg-purple-50 text-purple-700 border-purple-200',
  4: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  5: 'bg-slate-50 text-slate-600 border-slate-200',
}

function useKnownActors() {
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

function ActorsList({ push }: { push: ReturnType<typeof useToast>['push'] }) {
  const { dark } = useDark()
  const { addrs, set } = useKnownActors()
  const publicClient = usePublicClient()
  const [isSyncing, setIsSyncing] = useState(false)

  const syncFromChain = useCallback(async () => {
    if (!publicClient) return
    setIsSyncing(true)
    try {
      const logs = await publicClient.getLogs({
        address: CONTRACT_ADDRESS,
        event: {
          type: 'event',
          name: 'ActorRegistered',
          inputs: [
            { type: 'address', name: 'actorAddress', indexed: true },
            { type: 'string',  name: 'name',         indexed: false },
            { type: 'uint8',   name: 'role',          indexed: false },
          ],
        },
        fromBlock: BigInt(0),
        toBlock: 'latest',
      })
      const candidates: string[] = []
      logs.forEach((log: any) => {
        const addr: string = log.args?.actorAddress
        if (addr && !candidates.includes(addr)) candidates.push(addr)
      })
      const valid: string[] = []
      await Promise.all(
        candidates.map(async addr => {
          try {
            const actor: any = await publicClient.readContract({
              address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getActor', args: [addr],
            })
            if (actor?.name) valid.push(addr)
          } catch { /* descartada */ }
        })
      )
      set(valid)
      push(`Sincronizado: ${valid.length} actor(es) de ${candidates.length} evento(s)`, 'ok')
    } catch (e: any) {
      push('Error al sincronizar: ' + (e?.shortMessage ?? e?.message ?? 'desconocido'), 'err')
    } finally {
      setIsSyncing(false)
    }
  }, [publicClient, set, push])

  useEffect(() => { syncFromChain() }, [])

  return (
    <SectionHeader>
      <div className="border-l-4 border-indigo-500 px-6 pt-6 pb-4">
        <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: 0 }}>
          Actores Registrados{' '}
          <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
            ({addrs.length} dirección(es) · datos leídos on-chain en tiempo real)
          </span>
        </h2>
      </div>

      <div className="px-6 pb-6">
        {/* [FIX-UX] Estado vacío con mensaje claro */}
        {addrs.length === 0 ? (
          <div style={{ padding: '48px 0', textAlign: 'center', color: dark ? '#475569' : '#94a3b8' }}>
            <div style={{ fontSize: '32px', marginBottom: '10px' }}>👥</div>
            <p style={{ fontSize: '14px', margin: '0 0 4px' }}>No hay actores registrados aún.</p>
            <p style={{ fontSize: '12px' }}>Registra un actor en el formulario de arriba o sincroniza desde la blockchain.</p>
          </div>
        ) : (
          <div style={{ marginTop: '8px', borderRadius: '8px', overflowX: 'auto', WebkitOverflowScrolling: 'touch', border: '0.5px solid #e2e8f0' }}>
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse', tableLayout: 'fixed' }}>
              <colgroup>
                <col style={{ width: '28%' }} />
                <col style={{ width: '20%' }} />
                <col style={{ width: '14%' }} />
                <col style={{ width: '24%' }} />
                <col style={{ width: '14%' }} />
              </colgroup>
              <thead>
                {/* [FIX-UI] Cabecera gris neutro, bordes finos */}
                <tr>
                  {['Nombre', 'Dirección', 'Rol', 'Ubicación', 'Acción'].map(h => (
                    <th key={h} style={TH_STYLE}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {addrs.map(a => (
                  <ActorRow key={a} address={a as Address} push={push} />
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'center', marginTop: '16px' }}>
          <button
            onClick={syncFromChain}
            disabled={isSyncing}
            title="Lee todos los eventos ActorRegistered del contrato y actualiza la lista."
            style={{ ...btnSecondary, opacity: isSyncing ? 0.5 : 1 }}
          >
            {isSyncing ? '⏳ Sincronizando…' : '⛓ Sync desde chain'}
          </button>
        </div>
      </div>
    </SectionHeader>
  )
}

// [FIX-ERR] ActorRow recibe push y usa useTx correctamente para no perder errores
function ActorRow({ address, push }: { address: Address; push: ReturnType<typeof useToast>['push'] }) {
  const { dark } = useDark()
  const { data: actor, refetch }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getActor', args: [address],
  })

  const { write, isPending } = useTx(push)

  const handleToggleActive = () => {
    const fn = actor.isActive ? 'deactivateActor' : 'reactivateActor'
    write(
      { address: CONTRACT_ADDRESS, abi: ABI, functionName: fn, args: [address] },
      { onSuccess: () => setTimeout(() => refetch(), 2000) }
    )
  }

  if (!actor) {
    return (
      <tr className="animate-pulse">
        {[...Array(5)].map((_, i) => (
          <td key={i} style={TD_STYLE}>
            <div className="h-3 bg-slate-100 rounded w-16" />
          </td>
        ))}
      </tr>
    )
  }

  if (!actor.name) return null

  const isActive: boolean = actor.isActive
  const roleIdx = Number(actor.role)

  return (
    <tr style={{ opacity: isActive ? 1 : 0.55 }} className={`transition-colors ${isActive ? (dark ? 'bg-slate-800' : 'bg-white') + ' hover:bg-slate-50' : (dark ? 'bg-slate-900' : 'bg-slate-50')}`}>
      <td style={TD_STYLE}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
          <span style={{ fontSize: '16px' }}>{ROLE_ICONS[roleIdx] ?? '👤'}</span>
          <span style={{ fontSize: '14px', fontWeight: 500, color: dark ? '#e2e8f0' : '#1e293b' }}>{actor.name}</span>
        </div>
      </td>
      <td style={TD_STYLE}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1px' }}>
          <code style={{ fontSize: '13px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b' }}>{address.slice(0, 6)}</code>
          <code style={{ fontSize: '13px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b' }}>…{address.slice(-4)}</code>
        </div>
      </td>
      <td style={TD_STYLE}>
        <span className={`text-xs font-semibold px-2 py-1 rounded-lg uppercase border ${ROLE_COLORS[roleIdx] ?? 'bg-slate-50 text-slate-600 border-slate-200'}`}>
          {ACTOR_ROLES[roleIdx] ?? '—'}
        </span>
      </td>
      <td style={{ ...TD_STYLE, fontSize: '13px', color: dark ? '#94a3b8' : '#64748b' }}>
        📍 {actor.location}
      </td>
      <td style={{ ...TD_STYLE, textAlign: 'center' }}>
        <button
          onClick={handleToggleActive}
          disabled={isPending}
          className={`text-xs font-semibold px-3 py-1.5 rounded-lg uppercase border transition-colors disabled:opacity-50
            ${isActive ? 'bg-red-50 text-red-600 border-red-200 hover:bg-red-100' : 'bg-emerald-50 text-emerald-600 border-emerald-200 hover:bg-emerald-100'}`}
        >
          {isPending ? '⏳' : isActive ? 'Desactivar' : 'Reactivar'}
        </button>
      </td>
    </tr>
  )
}

// ---------------------------------------------------------------------------
// 3. Expedición — Crear Envío
// ---------------------------------------------------------------------------
function ShippingPanel({ push }: { push: ReturnType<typeof useToast>['push'] }) {
  const { dark } = useDark()
  const [form, setForm] = useState({ rec: '', prod: '', ori: '', dst: '', cold: false })
  const [errors, setErrors] = useState<Record<string, string>>({})
  const { write, isPending, isSuccess } = useTx(push)
  const publicClient = usePublicClient()
  const { address } = useAccount()

  const validate = () => {
    const e: Record<string, string> = {}
    if (!form.rec.trim()) e.rec = 'Campo requerido'
    else if (!isValidAddress(form.rec)) e.rec = 'Dirección inválida (debe ser 0x…40 hex)'
    if (!form.prod.trim()) e.prod = 'Campo requerido'
    if (!form.ori.trim()) e.ori = 'Campo requerido'
    if (!form.dst.trim()) e.dst = 'Campo requerido'
    setErrors(e)
    return Object.keys(e).length === 0
  }

  const handleCreate = async () => {
    if (!validate()) return
    const recipient = isValidAddress(form.rec) ? form.rec as Address : '0x0000000000000000000000000000000000000000' as Address
    try {
      await publicClient?.simulateContract({
        address: CONTRACT_ADDRESS,
        abi: ABI,
        functionName: 'createShipment',
        args: [recipient, form.prod, form.ori, form.dst, form.cold],
        account: address as Address,
      })
    } catch (e: any) {
      push(parseContractError(e), 'err')
      return
    }
    write({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'createShipment', args: [recipient, form.prod, form.ori, form.dst, form.cold] })
  }

  useEffect(() => {
    if (isSuccess) setForm({ rec: '', prod: '', ori: '', dst: '', cold: false })
  }, [isSuccess])

  return (
    <Card accent="emerald">
      <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 4px' }}>
        Crear Envío{' '}
        <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
          (Solo actores con rol Sender pueden crear envíos.)
        </span>
      </h2>

      <div style={{ marginTop: '16px', display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '12px' }}>
        <div>
          <label style={labelStyle(dark)}>Destinatario</label>
          <input placeholder="0x1234...abcd" value={form.rec} onChange={e => setForm({ ...form, rec: e.target.value })} style={inputStyle(dark, !!errors.rec)} />
          <FieldError msg={errors.rec} />
        </div>
        <div>
          <label style={labelStyle(dark)}>Producto</label>
          <input placeholder="Producto" value={form.prod} onChange={e => setForm({ ...form, prod: e.target.value })} style={inputStyle(dark, !!errors.prod)} />
          <FieldError msg={errors.prod} />
          <label style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '10px', cursor: 'pointer' }}>
            <input type="checkbox" checked={form.cold} onChange={e => setForm({ ...form, cold: e.target.checked })} style={{ width: '16px', height: '16px', accentColor: '#2563eb' }} />
            <span style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '13px', color: dark ? '#94a3b8' : '#475569' }}>
              🌡️ Cadena de frío (2–8 °C)
            </span>
          </label>
        </div>
        <div>
          <label style={labelStyle(dark)}>Origen</label>
          <input placeholder="Origen" value={form.ori} onChange={e => setForm({ ...form, ori: e.target.value })} style={inputStyle(dark, !!errors.ori)} />
          <FieldError msg={errors.ori} />
        </div>
        <div>
          <label style={labelStyle(dark)}>Destino</label>
          <input placeholder="Destino" value={form.dst} onChange={e => setForm({ ...form, dst: e.target.value })} style={inputStyle(dark, !!errors.dst)} />
          <FieldError msg={errors.dst} />
        </div>
      </div>

      <div style={{ display: 'flex', justifyContent: 'center', marginTop: '20px' }}>
        <button onClick={handleCreate} disabled={isPending} style={btnPrimary(isPending)}>
          {isPending ? '⏳ Creando…' : 'Generar Envío'}
        </button>
      </div>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// 4. Operaciones
// ---------------------------------------------------------------------------
function OperationsPanel({ push }: { push: ReturnType<typeof useToast>['push'] }) {
  const { dark } = useDark()
  // [FIX-UX] Temperatura en °C directos — el label ya no expone "× 10"
  const [cpForm, setCpForm] = useState({ id: '', loc: '', type: -1, notes: '', temp: '', noTemp: false })
  const [statusForm, setStatusForm] = useState({ id: '', status: -1 })
  const [confirmId, setConfirmId] = useState('')
  const [cancelId, setCancelId] = useState('')
  const [cpErrors, setCpErrors] = useState<Record<string, string>>({})

  const { write: writeOp, isPending: opPending, isSuccess: opSuccess } = useTx(push)
  const lastOpRef = useRef<null | 'checkpoint' | 'status' | 'confirm' | 'cancel'>(null)
  const publicClient = usePublicClient()
  const { address } = useAccount()

  useEffect(() => {
    if (opSuccess) {
      if (lastOpRef.current === 'checkpoint') { setCpForm({ id: '', loc: '', type: -1, notes: '', temp: '', noTemp: false }); setCpErrors({}) }
      if (lastOpRef.current === 'confirm') setConfirmId('')
      if (lastOpRef.current === 'status') setStatusForm({ id: '', status: -1 })
      if (lastOpRef.current === 'cancel') setCancelId('')
      lastOpRef.current = null
    }
  }, [opSuccess])

  // Simula la transacción antes de abrir MetaMask — muestra el error en toast si falla
  const simulate = async (functionName: string, args: any[]): Promise<boolean> => {
    if (!publicClient) {
      push('Cliente blockchain no disponible', 'err')
      return false
    }
    try {
      await publicClient.simulateContract({
        address: CONTRACT_ADDRESS,
        abi: ABI,
        functionName,
        args,
        account: address as Address,
      })
      return true
    } catch (e: any) {
      // Serializar sin romper en BigInt
      let rawStr = ''
      try { rawStr = JSON.stringify(e, (_k, v) => typeof v === 'bigint' ? v.toString() : v) } catch { rawStr = String(e) }
      const selector = rawStr.match(/custom error (0x[0-9a-fA-F]{8})/)?.[1]?.toLowerCase()
      console.error('[simulate]', functionName, '| selector:', selector, '| msg:', e?.message?.slice(0, 120))
      push(parseContractError(e), 'err')
      return false
    }
  }

  const validateCp = () => {
    const e: Record<string, string> = {}
    if (!cpForm.id || isNaN(Number(cpForm.id))) e.id = 'ID numérico requerido'
    if (!cpForm.loc.trim()) e.loc = 'Campo requerido'
    if (cpForm.type === -1) e.type = 'Seleccione un tipo'
    if (!cpForm.notes.trim()) e.notes = 'Campo requerido'
    if (!cpForm.noTemp) {
      const t = parseFloat(cpForm.temp)
      if (isNaN(t)) e.temp = 'Ingresa una temperatura en °C o marca "Sin lectura"'
    }
    setCpErrors(e)
    return Object.keys(e).length === 0
  }

  const handleCheckpoint = async () => {
    if (!validateCp()) return
    const tempArg = cpForm.noTemp
      ? TEMPERATURE_NOT_SET
      : BigInt(Math.round(parseFloat(cpForm.temp) * 10))
    const args = [BigInt(cpForm.id), cpForm.loc, cpForm.type, cpForm.notes || 'OK', tempArg]
    try {
      await publicClient?.simulateContract({
        address: CONTRACT_ADDRESS, abi: ABI, functionName: 'recordCheckpoint',
        args, account: address as Address,
      })
    } catch (e: any) {
      push(parseContractError(e), 'err')
      return
    }
    lastOpRef.current = 'checkpoint'
    writeOp({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'recordCheckpoint', args })
  }

  const handleStatus = async () => {
    if (!statusForm.id) return push('ID de envío requerido', 'err')
    if (statusForm.status === -1) return push('Selecciona un estado', 'err')
    const ok = await simulate('updateShipmentStatus', [BigInt(statusForm.id), statusForm.status])
    if (!ok) { setStatusForm({ id: '', status: -1 }); return }
    lastOpRef.current = 'status'
    writeOp(
      { address: CONTRACT_ADDRESS, abi: ABI, functionName: 'updateShipmentStatus', args: [BigInt(statusForm.id), statusForm.status] },
      { onSuccess: () => setStatusForm({ id: '', status: -1 }) }
    )
  }

  const handleConfirm = async () => {
    if (!confirmId) return push('ID de envío requerido', 'err')
    const ok = await simulate('confirmDelivery', [BigInt(confirmId)])
    if (!ok) { setConfirmId(''); return }
    lastOpRef.current = 'confirm'
    writeOp(
      { address: CONTRACT_ADDRESS, abi: ABI, functionName: 'confirmDelivery', args: [BigInt(confirmId)] },
      { onSuccess: () => setConfirmId('') }
    )
  }

  const handleCancel = async () => {
    if (!cancelId) return push('ID de envío requerido', 'err')
    const ok = await simulate('cancelShipment', [BigInt(cancelId)])
    if (!ok) { setCancelId(''); return }
    lastOpRef.current = 'cancel'
    writeOp(
      { address: CONTRACT_ADDRESS, abi: ABI, functionName: 'cancelShipment', args: [BigInt(cancelId)] },
      { onSuccess: () => setCancelId('') }
    )
  }

  const subSectionTitle = (label: string, color = '#059669') => (
    <p style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '14px', fontWeight: 700, color, textTransform: 'uppercase', marginBottom: '12px', textDecoration: 'underline', textUnderlineOffset: '3px' }}>
      {label}
    </p>
  )

  return (
    <Card accent="orange">
      <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 4px' }}>
        Operaciones{' '}
        <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
          (Registrar checkpoint, cambiar estado, confirmar entrega o cancelar.)
        </span>
      </h2>

      {/* CHECKPOINT */}
      <div className="mt-5">
        {subSectionTitle('📍 Registrar Checkpoint')}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '12px' }}>
          <div>
            <label style={labelStyle(dark)}>ID Envío</label>
            <input type="number" min="1" placeholder="######" value={cpForm.id} onChange={e => setCpForm({ ...cpForm, id: e.target.value })} style={inputStyle(dark, !!cpErrors.id)} />
            <FieldError msg={cpErrors.id} />
          </div>
          <div>
            <label style={labelStyle(dark)}>Ubicación actual</label>
            <input placeholder="Ubicación Actual" value={cpForm.loc} onChange={e => setCpForm({ ...cpForm, loc: e.target.value })} style={inputStyle(dark, !!cpErrors.loc)} />
            <FieldError msg={cpErrors.loc} />
          </div>
          <div>
            <label style={labelStyle(dark)}>Tipo</label>
            <select value={cpForm.type} onChange={e => setCpForm({ ...cpForm, type: Number(e.target.value) })} style={inputStyle(dark, !!cpErrors.type)}>
              <option value={-1} disabled>— Seleccione un tipo —</option>
              {CHECKPOINT_TYPES.map((t, i) => <option key={i} value={i}>{t}</option>)}
            </select>
            <FieldError msg={cpErrors.type} />
          </div>
          <div>
            {/* [FIX-UX] Label claro: temperatura en °C normales */}
            <label style={labelStyle(dark)}>Temperatura (°C)</label>
            <input
              type="number" step="0.1"
              placeholder="Ej: 4.5"
              value={cpForm.temp}
              disabled={cpForm.noTemp}
              onChange={e => setCpForm({ ...cpForm, temp: e.target.value })}
              style={{ ...inputStyle(dark, !!cpErrors.temp), opacity: cpForm.noTemp ? 0.4 : 1, cursor: cpForm.noTemp ? 'not-allowed' : 'auto', backgroundColor: cpForm.noTemp ? (dark ? '#0f172a' : '#f1f5f9') : (dark ? '#0f172a' : '#f8fafc') }}
            />
            <FieldError msg={cpErrors.temp} />
            <label style={{ display: 'flex', alignItems: 'center', gap: '6px', marginTop: '6px', cursor: 'pointer' }}>
              <input type="checkbox" checked={cpForm.noTemp} onChange={e => setCpForm({ ...cpForm, noTemp: e.target.checked, temp: '' })} style={{ width: '14px', height: '14px', accentColor: '#f97316' }} />
              <span style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '12px', color: dark ? '#64748b' : '#94a3b8' }}>Sin lectura</span>
            </label>
          </div>
        </div>

        <div style={{ marginTop: '12px' }}>
          <label style={labelStyle(dark)}>Notas</label>
          <textarea
            placeholder="Si hay novedades, ingrésalas aquí"
            value={cpForm.notes}
            rows={2}
            onChange={e => setCpForm({ ...cpForm, notes: e.target.value })}
            style={{ ...inputStyle(dark, !!cpErrors.notes), resize: 'vertical', minHeight: '64px' }}
          />
          <FieldError msg={cpErrors.notes} />
        </div>

        <div style={{ display: 'flex', justifyContent: 'center', marginTop: '16px' }}>
          <button onClick={handleCheckpoint} disabled={opPending} style={btnPrimary(opPending)}>
            {opPending ? '⏳ Registrando…' : 'Registrar Checkpoint'}
          </button>
        </div>
      </div>

      <hr style={{ border: 'none', borderTop: `1px solid ${dark ? '#334155' : '#e2e8f0'}`, margin: '20px 0' }} />

      {/* STATUS + CONFIRM + CANCEL */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '0', marginTop: '8px' }}>

        {/* Cambiar Estado */}
        <div style={{ paddingRight: '24px', borderRight: `1px solid ${dark ? '#334155' : '#e2e8f0'}` }}>
          {subSectionTitle('🔄 Cambiar Estado')}
          <p style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8', marginTop: '-8px', marginBottom: '12px' }}>(Solo carrier / hub)</p>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '10px' }}>
            <label style={{ ...labelStyle(dark), whiteSpace: 'nowrap', margin: 0 }}>ID Envío</label>
            <input type="number" min="1" placeholder="######" value={statusForm.id} onChange={e => setStatusForm({ ...statusForm, id: e.target.value })} style={{ ...inputStyle(dark), flex: 1 }} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <label style={{ ...labelStyle(dark), whiteSpace: 'nowrap', margin: 0 }}>Nuevo estado</label>
            <select value={statusForm.status} onChange={e => setStatusForm({ ...statusForm, status: Number(e.target.value) })} style={{ ...inputStyle(dark), flex: '0 1 160px', maxWidth: '160px' }}>
              <option value={-1} disabled>— Estado —</option>
              {SHIPMENT_STATUSES.map((s, i) => i !== 4 ? <option key={i} value={i}>{s}</option> : null)}
            </select>
          </div>
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '16px' }}>
            <button onClick={handleStatus} disabled={opPending} style={btnPrimary(opPending)}>
              {opPending ? '⏳ Procesando…' : 'Actualizar Estado'}
            </button>
          </div>
        </div>

        {/* Confirmar Entrega */}
        <div style={{ paddingLeft: '24px', paddingRight: '24px', borderRight: `1px solid ${dark ? '#334155' : '#e2e8f0'}` }}>
          {subSectionTitle('✅ Confirmar Entrega')}
          <p style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8', marginTop: '-8px', marginBottom: '12px' }}>(Solo recipient)</p>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <label style={{ ...labelStyle(dark), whiteSpace: 'nowrap', margin: 0 }}>ID Envío</label>
            <input type="number" min="1" placeholder="######" value={confirmId} onChange={e => setConfirmId(e.target.value)} style={{ ...inputStyle(dark), flex: '0 0 140px', width: '140px' }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '16px' }}>
            <button onClick={handleConfirm} disabled={opPending} style={btnPrimary(opPending)}>
              {opPending ? '⏳ …' : 'Confirmar Entrega'}
            </button>
          </div>
        </div>

        {/* Cancelar Envío */}
        <div style={{ paddingLeft: '24px' }}>
          {subSectionTitle('❌ Cancelar Envío', '#dc2626')}
          <p style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8', marginTop: '-8px', marginBottom: '12px' }}>(Solo sender)</p>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <label style={{ ...labelStyle(dark), whiteSpace: 'nowrap', margin: 0 }}>ID Envío</label>
            <input type="number" min="1" placeholder="######" value={cancelId} onChange={e => setCancelId(e.target.value)} style={{ ...inputStyle(dark), flex: '0 0 140px', width: '140px' }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '16px' }}>
            <button onClick={handleCancel} disabled={opPending} style={btnDanger(opPending)}>
              {opPending ? '⏳ …' : 'Cancelar Envío'}
            </button>
          </div>
        </div>
      </div>

      <hr style={{ border: 'none', borderTop: `1px solid ${dark ? '#334155' : '#e2e8f0'}`, margin: '16px 0' }} />
      <CheckpointsTable />
    </Card>
  )
}

// ---------------------------------------------------------------------------
// 5. Tabla de Envíos
// ---------------------------------------------------------------------------
function ShipmentsTable() {
  const { dark } = useDark()
  const { data: nextId }: any = useReadContract({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextShipmentId' })
  const total = nextId ? Number(nextId) - 1 : 0
  const ids = Array.from({ length: total }, (_, i) => i + 1)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<number | 'all'>('all')
  const filtered = ids.filter(id => !search || String(id).includes(search))

  return (
    <SectionHeader>
      <div className="border-l-4 border-teal-500 px-6 pt-6 pb-4">
        <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 12px' }}>
          Envíos{' '}
          <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
            ({total} envío(s) registrado(s) en el contrato)
          </span>
        </h2>
        <div className="mt-3 flex gap-2 flex-wrap">
          <input
            type="text"
            placeholder="🔍 Filtrar por ID…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="flex-1 min-w-[180px] bg-slate-50 border border-slate-200 px-3 py-2 rounded-xl text-xs font-semibold outline-none focus:ring-2 focus:ring-teal-100 transition-all"
          />
          <button onClick={() => setFilterStatus('all')} className={`text-xs font-semibold px-3 py-2 rounded-xl uppercase border transition-colors ${filterStatus === 'all' ? 'bg-teal-600 text-white border-teal-600' : 'bg-white text-slate-500 border-slate-200 hover:border-teal-300'}`}>Todos</button>
          {SHIPMENT_STATUSES.map((s, i) => (
            <button key={i} onClick={() => setFilterStatus(i)} className={`text-xs font-semibold px-3 py-2 rounded-xl uppercase border transition-colors ${filterStatus === i ? 'bg-teal-600 text-white border-teal-600' : 'bg-white text-slate-500 border-slate-200 hover:border-teal-300'}`}>{s}</button>
          ))}
        </div>
      </div>

      <div className="px-6 pb-6">
        {total === 0 ? (
          <div style={{ padding: '40px 0', textAlign: 'center', color: dark ? '#475569' : '#94a3b8' }}>
            <div style={{ fontSize: '28px', marginBottom: '8px' }}>📦</div>
            <p style={{ fontSize: '13px' }}>No hay envíos registrados aún.</p>
          </div>
        ) : (
          <div style={{ marginTop: '8px', borderRadius: '8px', overflowX: 'auto', WebkitOverflowScrolling: 'touch', border: '0.5px solid #e2e8f0' }}>
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse' }}>
              <thead>
                <tr>
                  {['ID', 'Producto', 'Remitente / Destinatario', 'Ruta', 'Estado / Fecha'].map(h => (
                    <th key={h} style={TH_STYLE}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {filtered.map(id => <ShipmentRow key={id} id={id} filterStatus={filterStatus} />)}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </SectionHeader>
  )
}

function ShipmentRow({ id, filterStatus }: { id: number; filterStatus: number | 'all' }) {
  const { dark } = useDark()
  const { data: s }: any = useReadContract({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getShipment', args: [BigInt(id)] })

  if (!s) {
    return (
      <tr className="animate-pulse">
        {[...Array(5)].map((_, i) => (
          <td key={i} style={TD_STYLE}><div className="h-3 bg-slate-100 rounded w-14" /></td>
        ))}
      </tr>
    )
  }

  const statusIdx = Number(s.status)
  const zeroAddr  = '0x0000000000000000000000000000000000000000'
  if (filterStatus !== 'all' && statusIdx !== filterStatus) return null

  return (
    <tr className={`transition-colors ${dark ? 'hover:bg-slate-700' : 'bg-white hover:bg-slate-50'}`}>
      <td style={TD_STYLE}>
        <span style={{ fontSize: '13px', fontWeight: 700, color: '#64748b', backgroundColor: '#f1f5f9', padding: '2px 8px', borderRadius: '6px' }}>#{String(s.id)}</span>
        {s.requiresColdChain && <div style={{ marginTop: '4px' }}><span style={{ fontSize: '11px', fontWeight: 600, color: '#3b82f6', backgroundColor: '#eff6ff', border: '1px solid #bfdbfe', padding: '1px 6px', borderRadius: '5px' }}>❄ Frío</span></div>}
      </td>
      <td style={TD_STYLE}>
        <div style={{ fontSize: '13px', fontWeight: 500, color: dark ? '#e2e8f0' : '#1e293b', wordBreak: 'break-word', whiteSpace: 'normal' }}>{s.product}</div>
      </td>
      <td style={TD_STYLE}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
          <div><span style={{ fontSize: '11px', fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase' }}>De: </span><code style={{ fontSize: '12px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b' }}>{shortAddr(s.sender)}</code></div>
          <div><span style={{ fontSize: '11px', fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase' }}>Para: </span><code style={{ fontSize: '12px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b' }}>{s.recipient === zeroAddr ? '—' : shortAddr(s.recipient)}</code></div>
        </div>
      </td>
      <td style={TD_STYLE}>
        <div style={{ fontSize: '13px', color: dark ? '#94a3b8' : '#64748b' }}>{s.origin}</div>
        <div style={{ fontSize: '13px', color: '#cbd5e1' }}>↓</div>
        <div style={{ fontSize: '13px', color: dark ? '#94a3b8' : '#64748b' }}>{s.destination}</div>
      </td>
      <td style={TD_STYLE}>
        <span className={`text-sm font-semibold px-2 py-1 rounded-lg uppercase ${STATUS_COLORS[statusIdx] ?? 'bg-slate-100 text-slate-500'}`} style={{ display: 'inline-block' }}>
          {SHIPMENT_STATUSES[statusIdx] ?? '—'}
        </span>
        <div style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8', marginTop: '4px' }}>
          {new Date(Number(s.dateCreated) * 1000).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' })}
        </div>
      </td>
    </tr>
  )
}

// ---------------------------------------------------------------------------
// 6. Tabla de Checkpoints (dentro de Operaciones)
// ---------------------------------------------------------------------------
function CheckpointsTable() {
  const { dark } = useDark()
  const { data: nextShipId, refetch: refetchShip }: any = useReadContract({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextShipmentId' })
  const { data: nextCpId, refetch: refetchCp }: any    = useReadContract({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextCheckpointId' })

  const totalShipments = nextShipId ? Number(nextShipId) - 1 : 0
  const totalCps       = nextCpId   ? Number(nextCpId)   - 1 : 0
  const [search, setSearch] = useState('')
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const interval = setInterval(() => { refetchShip(); refetchCp(); setTick(t => t + 1) }, 3000)
    return () => clearInterval(interval)
  }, [refetchShip, refetchCp])

  return (
    <div style={{ backgroundColor: dark ? '#0f172a' : '#f8fafc', borderRadius: '12px', border: `0.5px solid ${dark ? '#334155' : '#e2e8f0'}`, overflow: 'hidden' }}>
      <div className="border-l-4 border-cyan-500 px-5 pt-5 pb-3">
        <h3 style={{ fontSize: '14px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 8px' }}>
          Checkpoints{' '}
          <span style={{ fontSize: '12px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
            ({totalCps} checkpoint(s) en {totalShipments} envío(s))
          </span>
        </h3>
        <input
          type="text"
          placeholder="🔍 Filtrar por ID de envío…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="w-full bg-slate-50 border border-slate-200 px-3 py-2 rounded-xl text-xs font-semibold outline-none focus:ring-2 focus:ring-cyan-100 transition-all"
        />
      </div>

      <div className="px-5 pb-5">
        {totalShipments === 0 ? (
          <div style={{ padding: '24px 0', textAlign: 'center', color: dark ? '#475569' : '#94a3b8' }}>
            <p style={{ fontSize: '12px' }}>No hay checkpoints registrados aún.</p>
          </div>
        ) : (
          <div style={{ marginTop: '8px', borderRadius: '8px', overflowX: 'auto', border: '0.5px solid #e2e8f0' }}>
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse' }}>
              <thead>
                <tr>
                  {['Envío', 'Tipo', 'Ubicación', 'Actor', 'Temperatura', 'Notas', 'Fecha'].map(h => (
                    <th key={h} style={TH_STYLE}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {Array.from({ length: totalShipments }, (_, i) => i + 1)
                  .filter(id => !search || String(id).includes(search.trim()))
                  .map(shipId => <CheckpointRows key={shipId} shipmentId={shipId} tick={tick} />)}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}

function CheckpointRows({ shipmentId, tick }: { shipmentId: number; tick: number }) {
  const { data: cps, refetch }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getShipmentCheckpoints', args: [BigInt(shipmentId), BigInt(0), BigInt(50)],
  })

  useEffect(() => { refetch() }, [tick])

  if (!cps) {
    return (
      <tr>
        {[...Array(7)].map((_, i) => (
          <td key={i} style={TD_STYLE}><div className="h-3 bg-slate-100 rounded w-14 animate-pulse" /></td>
        ))}
      </tr>
    )
  }

  if (cps.length === 0) return null

  return (
    <>
      {cps.map((cp: any, i: number) => (
        <tr key={i} className={i % 2 === 0 ? 'bg-white' : 'bg-slate-50'}>
          <td style={TD_STYLE}>
            <span className="text-xs font-semibold text-slate-500 bg-slate-100 px-2 py-0.5 rounded-md">#{shipmentId}</span>
          </td>
          <td style={TD_STYLE}>
            <span className="text-xs font-semibold px-2 py-1 rounded-md uppercase bg-cyan-50 text-cyan-700 border border-cyan-200">
              {CHECKPOINT_TYPES[Number(cp.checkpointType)] ?? 'Other'}
            </span>
          </td>
          {/* [FIX-UI] Ubicación con color legible en modo claro */}
          <td style={{ ...TD_STYLE, minWidth: '160px' }}>
            <span className="text-xs font-medium text-slate-700">{cp.location}</span>
          </td>
          <td style={TD_STYLE}>
            <code className="text-xs font-mono text-slate-400 bg-slate-50 border border-slate-100 px-2 py-1 rounded-md">
              {shortAddr(cp.actor)}
            </code>
          </td>
          <td style={TD_STYLE}>
            <span className={`text-xs font-semibold ${tempIsUnset(cp.temperature) ? 'text-slate-300' : tempIsOutOfRange(cp.temperature) ? 'text-red-500' : 'text-emerald-600'}`}>
              {tempDisplay(cp.temperature)}
            </span>
          </td>
          <td style={{ ...TD_STYLE, minWidth: '180px', whiteSpace: 'normal' }}>
            <span className="text-xs text-slate-500 italic">{cp.notes || '—'}</span>
          </td>
          <td style={TD_STYLE}>
            <span className="text-xs text-slate-400 font-medium">{fmtTs(cp.timestamp)}</span>
          </td>
        </tr>
      ))}
    </>
  )
}

// ---------------------------------------------------------------------------
// 7. Trazabilidad
// ---------------------------------------------------------------------------
function loadJsPDF(): Promise<any> {
  return new Promise((resolve, reject) => {
    if ((window as any).jspdf?.jsPDF) { resolve((window as any).jspdf.jsPDF); return }
    const s1 = document.createElement('script')
    s1.src = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js'
    s1.onload = () => {
      const s2 = document.createElement('script')
      s2.src = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.8.2/jspdf.plugin.autotable.min.js'
      s2.onload = () => resolve((window as any).jspdf.jsPDF)
      s2.onerror = reject
      document.head.appendChild(s2)
    }
    s1.onerror = reject
    document.head.appendChild(s1)
  })
}

function TraceabilityPanel() {
  const { dark } = useDark()
  const [id, setId] = useState('')
  const [queried, setQueried] = useState(false)
  const [generando, setGenerando] = useState(false)
  const [idError, setIdError] = useState('')

  // [FIX-ERR] Validar ID antes de consultar
  const handleQuery = () => {
    const n = parseInt(id, 10)
    if (!id.trim() || isNaN(n) || n < 1) {
      setIdError('Ingresa un ID de envío válido (número ≥ 1)')
      return
    }
    setIdError('')
    setQueried(true)
  }

  const { data: shipment }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getShipment', args: [BigInt(id || 0)],
    query: { enabled: queried && !!id },
  })

  const { data: checkpoints }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getShipmentCheckpoints', args: [BigInt(id || 0), BigInt(0), BigInt(50)],
    query: { enabled: queried && !!id },
  })

  const { data: incidents }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getShipmentIncidents', args: [BigInt(id || 0), BigInt(0), BigInt(50)],
    query: { enabled: queried && !!id },
  })

  // [FIX-UX] Llamar a verifyTemperatureCompliance para mostrar estado real de cadena de frío
  const { data: tempCompliance }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'verifyTemperatureCompliance', args: [BigInt(id || 0)],
    query: { enabled: queried && !!id && shipment?.requiresColdChain },
  })

  const statusIdx = shipment ? Number(shipment.status) : -1

  const handleDownloadPDF = async () => {
    if (!shipment || !checkpoints) return
    setGenerando(true)
    try {
      const JsPDF = await loadJsPDF()
      const doc = new JsPDF({ orientation: 'landscape', unit: 'mm', format: 'letter' })
      const M = 10
      const W = doc.internal.pageSize.getWidth()
      const azul:      [number, number, number] = [5, 60, 190]
      const negro:     [number, number, number] = [0, 0, 0]
      const blanco:    [number, number, number] = [255, 255, 255]
      const grisClaro: [number, number, number] = [245, 247, 250]

      doc.setFillColor(...azul)
      doc.rect(M, M, W - M * 2, 14, 'F')
      doc.setTextColor(...blanco)
      doc.setFontSize(14); doc.setFont('helvetica', 'bold')
      doc.text('LOGICHAIN — Reporte de Trazabilidad', M + 5, M + 9.5)
      doc.setFontSize(9); doc.setFont('helvetica', 'normal')
      doc.text(`Generado: ${new Date().toLocaleString('es-CO')}`, W - M - 5, M + 9.5, { align: 'right' })

      let y = M + 20
      doc.setTextColor(...negro); doc.setFontSize(11); doc.setFont('helvetica', 'bold')
      doc.text(`Envío #${String(shipment.id)} — ${shipment.product}`, M, y)
      y += 6; doc.setFontSize(9); doc.setFont('helvetica', 'normal'); doc.setTextColor(80, 80, 80)
      doc.text(`Origen: ${shipment.origin}   →   Destino: ${shipment.destination}`, M, y)
      doc.text(`Estado: ${SHIPMENT_STATUSES[statusIdx] ?? '—'}   |   Remitente: ${shortAddr(shipment.sender)}   |   Destinatario: ${shortAddr(shipment.recipient)}`, M, y + 5)
      doc.text(`Creado: ${fmtTs(shipment.dateCreated)}${shipment.dateDelivered > 0n ? `   |   Entregado: ${fmtTs(shipment.dateDelivered)}` : ''}${shipment.requiresColdChain ? '   |   Cadena de frío' : ''}`, M, y + 10)
      y += 20

      if (checkpoints && checkpoints.length > 0) {
        doc.setFontSize(10); doc.setFont('helvetica', 'bold'); doc.setTextColor(...negro)
        doc.text(`Checkpoints (${checkpoints.length})`, M, y); y += 4
        ;(doc as any).autoTable({
          startY: y, margin: { left: M, right: M }, tableWidth: W - M * 2,
          head: [['#', 'Tipo', 'Ubicación', 'Actor', 'Temperatura', 'Notas', 'Fecha']],
          body: checkpoints.map((cp: any, i: number) => [i + 1, CHECKPOINT_TYPES[Number(cp.checkpointType)] ?? 'Other', cp.location, shortAddr(cp.actor), tempDisplay(cp.temperature), cp.notes || '—', fmtTs(cp.timestamp)]),
          headStyles: { fillColor: azul, textColor: blanco, fontStyle: 'bold', fontSize: 8, lineWidth: 0.5, lineColor: negro },
          bodyStyles: { fontSize: 8, textColor: negro, lineWidth: 0.5, lineColor: negro },
          alternateRowStyles: { fillColor: grisClaro },
          columnStyles: { 0: { cellWidth: 8 }, 1: { cellWidth: 22 }, 2: { cellWidth: 55 }, 3: { cellWidth: 30 }, 4: { cellWidth: 25 }, 5: { cellWidth: 'auto' }, 6: { cellWidth: 32 } },
        })
        y = (doc as any).lastAutoTable.finalY + 8
      }

      if (incidents && incidents.length > 0) {
        if (y > doc.internal.pageSize.getHeight() - 40) { doc.addPage(); y = M + 10 }
        doc.setFontSize(10); doc.setFont('helvetica', 'bold'); doc.setTextColor(...negro)
        doc.text(`Incidencias (${incidents.length})`, M, y); y += 4
        ;(doc as any).autoTable({
          startY: y, margin: { left: M, right: M }, tableWidth: W - M * 2,
          head: [['Tipo', 'Descripción', 'Reporter', 'Fecha', 'Estado']],
          body: incidents.map((inc: any) => [INCIDENT_TYPES[Number(inc.incidentType)] ?? '—', inc.description, shortAddr(inc.reporter), fmtTs(inc.timestamp), inc.resolved ? 'Resuelto' : 'Abierto']),
          headStyles: { fillColor: azul, textColor: blanco, fontStyle: 'bold', fontSize: 8, lineWidth: 0.5, lineColor: negro },
          bodyStyles: { fontSize: 8, textColor: negro, lineWidth: 0.5, lineColor: negro },
          alternateRowStyles: { fillColor: grisClaro },
          columnStyles: { 0: { cellWidth: 30 }, 1: { cellWidth: 'auto' }, 2: { cellWidth: 30 }, 3: { cellWidth: 32 }, 4: { cellWidth: 20 } },
        })
      }

      const totalPages = (doc.internal as any).getNumberOfPages()
      for (let p = 1; p <= totalPages; p++) {
        doc.setPage(p); doc.setFontSize(7); doc.setTextColor(150, 150, 150); doc.setFont('helvetica', 'normal')
        doc.text(`Contrato: ${CONTRACT_ADDRESS}`, M, doc.internal.pageSize.getHeight() - M + 3)
        doc.text(`Página ${p} de ${totalPages}`, W - M, doc.internal.pageSize.getHeight() - M + 3, { align: 'right' })
      }
      doc.save(`trazabilidad-envio-${id}.pdf`)
    } catch (e) {
      console.error('Error generando PDF:', e)
    } finally {
      setGenerando(false)
    }
  }

  return (
    <Card accent="purple">
      <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 4px' }}>
        Trazabilidad{' '}
        <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
          (Consultar checkpoints e incidencias de un envío.)
        </span>
      </h2>

      <div className="mt-5">
        <div style={{ width: 'min(33%, 320px)', minWidth: '200px' }}>
          <label style={labelStyle(dark)}>ID Envío</label>
          <input
            type="number" min="1" placeholder="######"
            value={id}
            onChange={e => { setId(e.target.value); setQueried(false); setIdError('') }}
            style={inputStyle(dark, !!idError)}
          />
          <FieldError msg={idError} />
        </div>
        <div style={{ display: 'flex', gap: '12px', marginTop: '12px', justifyContent: 'center' }}>
          <button onClick={handleQuery} style={btnPrimary()}>Consultar</button>
          <div style={{ height: '24px' }} />
          {queried && shipment && shipment.id !== 0n && (
            <button onClick={handleDownloadPDF} disabled={generando} style={btnSecondary}>
              {generando ? '⏳ Generando…' : '⬇ Descargar PDF'}
            </button>
          )}
        </div>
      </div>

      {/* Info del envío */}
      {queried && shipment && shipment.id !== 0n && (
        <div className="mt-5 p-4 bg-slate-50 rounded-2xl border border-slate-200 space-y-2">
          <div className="flex justify-between items-center">
            <span className="text-xs text-slate-400 font-semibold uppercase">Envío #{String(shipment.id)}</span>
            {statusIdx >= 0 && (
              <span className={`text-sm font-semibold px-2 py-1 rounded-lg uppercase ${STATUS_COLORS[statusIdx]}`}>
                {SHIPMENT_STATUSES[statusIdx]}
              </span>
            )}
          </div>
          <p className="text-sm font-semibold text-slate-800">{shipment.product}</p>
          <p className="text-xs text-slate-400">{shipment.origin} → {shipment.destination}</p>
          <div className="flex gap-4 mt-2 text-xs text-slate-500 flex-wrap">
            <span>Creado: {fmtTs(shipment.dateCreated)}</span>
            {shipment.dateDelivered > 0n && <span>Entregado: {fmtTs(shipment.dateDelivered)}</span>}
            {/* [FIX-UX] Mostrar estado real de cumplimiento de cadena de frío */}
            {shipment.requiresColdChain && (
              <span className={`font-semibold ${tempCompliance === true ? 'text-emerald-600' : tempCompliance === false ? 'text-red-500' : 'text-blue-400'}`}>
                {tempCompliance === true ? '❄ Cadena de frío ✓' : tempCompliance === false ? '❄ Cadena de frío ⚠ Violación' : '❄ Cadena de frío'}
              </span>
            )}
          </div>
        </div>
      )}

      {/* Tabla checkpoints */}
      {queried && checkpoints && checkpoints.length > 0 && (
        <div className="mt-5">
          <p className="text-xs font-semibold text-slate-400 uppercase mb-3">Checkpoints ({checkpoints.length})</p>
          <div className="rounded-xl overflow-x-auto border border-slate-200">
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse' }}>
              <thead>
                <tr>
                  {['#', 'Tipo', 'Ubicación', 'Actor', 'Temperatura', 'Notas', 'Fecha'].map(h => (
                    <th key={h} style={TH_STYLE}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {checkpoints.map((cp: any, i: number) => (
                  <tr key={i} className={i % 2 === 0 ? 'bg-white' : 'bg-slate-50'}>
                    <td style={TD_STYLE}>
                      <span className="text-xs font-semibold text-slate-500 bg-slate-100 px-2 py-0.5 rounded-md">{i + 1}</span>
                    </td>
                    <td style={TD_STYLE}>
                      <span className="text-xs font-semibold px-2 py-1 rounded-md uppercase bg-cyan-50 text-cyan-700 border border-cyan-200">
                        {CHECKPOINT_TYPES[Number(cp.checkpointType)] ?? 'Other'}
                      </span>
                    </td>
                    {/* [FIX-UI] text-slate-700 en lugar de text-slate-200 en modo claro */}
                    <td style={{ ...TD_STYLE, minWidth: '160px', whiteSpace: 'normal' }}>
                      <span className="text-xs font-medium text-slate-700">{cp.location}</span>
                    </td>
                    <td style={TD_STYLE}>
                      <code className="text-xs font-mono text-slate-400 bg-slate-50 border border-slate-100 px-2 py-1 rounded-md">
                        {shortAddr(cp.actor)}
                      </code>
                    </td>
                    <td style={TD_STYLE}>
                      <span className={`text-xs font-semibold ${tempIsUnset(cp.temperature) ? 'text-slate-400' : tempIsOutOfRange(cp.temperature) ? 'text-red-500' : 'text-emerald-600'}`}>
                        {tempDisplay(cp.temperature)}
                      </span>
                    </td>
                    <td style={{ ...TD_STYLE, minWidth: '180px', whiteSpace: 'normal' }}>
                      <span className="text-xs text-slate-500 italic">{cp.notes || '—'}</span>
                    </td>
                    <td style={TD_STYLE}>
                      <span className="text-xs text-slate-400 font-medium">{fmtTs(cp.timestamp)}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tabla incidencias */}
      {queried && incidents && incidents.length > 0 && (
        <div className="mt-5">
          <p className="text-xs font-semibold text-slate-400 uppercase mb-3">Incidencias ({incidents.length})</p>
          <div className="rounded-xl overflow-x-auto border border-slate-200">
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse' }}>
              <thead>
                <tr>
                  {['Tipo', 'Descripción', 'Reporter', 'Fecha', 'Estado'].map(h => (
                    <th key={h} style={TH_STYLE}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {incidents.map((inc: any, i: number) => (
                  <tr key={i} className={i % 2 === 0 ? 'bg-white' : 'bg-slate-50'}>
                    <td style={TD_STYLE}>
                      <span className="text-xs font-semibold px-2 py-1 rounded-md uppercase bg-red-50 text-red-600 border border-red-200">
                        {INCIDENT_TYPES[Number(inc.incidentType)] ?? 'Incidencia'}
                      </span>
                    </td>
                    <td style={{ ...TD_STYLE, minWidth: '200px', whiteSpace: 'normal' }}>
                      <span className="text-xs text-slate-600">{inc.description}</span>
                    </td>
                    <td style={TD_STYLE}>
                      <code className="text-xs font-mono text-slate-400 bg-slate-50 border border-slate-100 px-2 py-1 rounded-md">
                        {shortAddr(inc.reporter)}
                      </code>
                    </td>
                    <td style={TD_STYLE}>
                      <span className="text-xs text-slate-400 font-medium">{fmtTs(inc.timestamp)}</span>
                    </td>
                    <td style={TD_STYLE}>
                      {inc.resolved
                        ? <span className="text-xs font-semibold px-2 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200">Resuelto</span>
                        : <span className="text-xs font-semibold px-2 py-0.5 rounded bg-red-50 text-red-600 border border-red-200">Abierto</span>
                      }
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {queried && (!checkpoints || checkpoints.length === 0) && (!incidents || incidents.length === 0) && id && (
        <p className="mt-8 text-center text-xs text-slate-500 italic">Sin datos para el envío #{id}</p>
      )}
    </Card>
  )
}
