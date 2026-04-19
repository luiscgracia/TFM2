import { useState, useEffect, useCallback } from 'react'
import {
  useReadContract,
  usePublicClient,
  useAccount,
} from 'wagmi'
import { CONTRACT_ADDRESS, ABI, ACTOR_ROLES } from '../blockchain/config'
import {
  Address,
  useDark,
  useToast,
  useKnownActors,
  useTx,
  parseContractError,
  isValidAddress,
  btnPrimary,
  btnSecondary,
  inputStyle,
  labelStyle,
  TH_STYLE,
  TD_STYLE,
  Card,
  SectionHeader,
  FieldError,
} from '../shared'
import { LocationSelect } from './LocationSelect'

// ---------------------------------------------------------------------------
// Role display constants
// ---------------------------------------------------------------------------
const ROLE_ICONS: Record<number, string>  = { 0: '⚙️', 1: '🏭', 2: '🚛', 3: '🏪', 4: '📦', 5: '🔍' }
const ROLE_COLORS: Record<number, string> = {
  1: 'bg-blue-50 text-blue-700 border-blue-200',
  2: 'bg-amber-50 text-amber-700 border-amber-200',
  3: 'bg-purple-50 text-purple-700 border-purple-200',
  4: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  5: 'bg-slate-50 text-slate-600 border-slate-200',
}

// ---------------------------------------------------------------------------
// ActorsTab — coordina RolesGovernance + ActorsList compartiendo syncFromChain
// ---------------------------------------------------------------------------
export function ActorsTab({ push }: { push: ReturnType<typeof useToast>['push'] }) {
  const publicClient = usePublicClient()
  const [isSyncing, setIsSyncing] = useState(false)
  const { set } = useKnownActors()

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
            { type: 'uint8',   name: 'role',         indexed: false },
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

  return (
    <>
      <RolesGovernance push={push} onActorRegistered={syncFromChain} />
      <TransferAdmin push={push} />
      <ActorsList push={push} isSyncing={isSyncing} onSync={syncFromChain} />
    </>
  )
}

// ---------------------------------------------------------------------------
// RolesGovernance — Registrar Actor
// ---------------------------------------------------------------------------
function RolesGovernance({ push, onActorRegistered }: { push: ReturnType<typeof useToast>['push']; onActorRegistered: () => void }) {
  const { dark } = useDark()
  const [form, setForm] = useState({ addr: '', name: '', role: 0, loc: '' })
  const [errors, setErrors] = useState<Record<string, string>>({})
  const { write, isPending, isSuccess } = useTx(push)
  const publicClient = usePublicClient()
  const { address } = useAccount()
  const { addrs, set } = useKnownActors()

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
      const updated = [...current, form.addr]
      localStorage.setItem(key, JSON.stringify(updated))
      // Actualizar la tabla inmediatamente sin esperar confirmación on-chain
      set([...addrs.filter(a => !updated.includes(a)), ...updated])
    }
    write({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: 'registerActor',
      args: [form.name, form.role, form.loc, form.addr as Address],
    })
  }

  useEffect(() => {
    if (isSuccess) {
      setForm({ addr: '', name: '', role: 1, loc: '' })
      onActorRegistered()
    }
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
          <LocationSelect
            key={form.addr + form.name}
            value={form.loc}
            onChange={loc => setForm({ ...form, loc })}
            dark={dark}
            hasError={!!errors.loc}
          />
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
// TransferAdmin — Ceder el admin del contrato a otra address
// ---------------------------------------------------------------------------
function TransferAdmin({ push }: { push: ReturnType<typeof useToast>['push'] }) {
  const { dark } = useDark()
  const [newAdmin, setNewAdmin] = useState('')
  const [error, setError] = useState('')
  const [showConfirm, setShowConfirm] = useState(false)
  const { write, isPending, isSuccess } = useTx(push)
  const publicClient = usePublicClient()
  const { address } = useAccount()

  const validate = () => {
    if (!isValidAddress(newAdmin)) {
      setError('Dirección inválida (debe ser 0x…40 hex)')
      return false
    }
    if (newAdmin.toLowerCase() === address?.toLowerCase()) {
      setError('La nueva dirección debe ser diferente a la tuya')
      return false
    }
    setError('')
    return true
  }

  const handleRequest = () => {
    if (!validate()) return
    setShowConfirm(true)
  }

  const handleConfirm = async () => {
    setShowConfirm(false)
    try {
      await publicClient?.simulateContract({
        address: CONTRACT_ADDRESS,
        abi: ABI,
        functionName: 'transferAdmin',
        args: [newAdmin as Address],
        account: address as Address,
      })
    } catch (e: any) {
      push(parseContractError(e), 'err')
      return
    }
    write({
      address: CONTRACT_ADDRESS,
      abi: ABI,
      functionName: 'transferAdmin',
      args: [newAdmin as Address],
    })
  }

  useEffect(() => {
    if (isSuccess) setNewAdmin('')
  }, [isSuccess])

  return (
    <Card accent="red">
      <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 4px' }}>
        Transferir Admin{' '}
        <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
          (Cede el control del contrato a otra dirección. Esta acción es irreversible.)
        </span>
      </h2>

      <div style={{ marginTop: '16px', display: 'grid', gridTemplateColumns: '1fr auto', gap: '12px', alignItems: 'end' }}>
        <div>
          <label style={labelStyle(dark)}>Nueva dirección admin</label>
          <input
            placeholder="0x1234…abcd"
            value={newAdmin}
            onChange={e => { setNewAdmin(e.target.value); setError('') }}
            style={inputStyle(dark, !!error)}
          />
          <FieldError msg={error} />
        </div>
        <button
          onClick={handleRequest}
          disabled={isPending}
          style={{
            ...btnPrimary(isPending),
            background: isPending ? undefined : '#dc2626',
            marginBottom: error ? '20px' : '0',
          }}
        >
          {isPending ? '⏳ Procesando…' : '🔑 Transferir Admin'}
        </button>
      </div>

      {showConfirm && (
        <div style={{
          marginTop: '16px',
          padding: '16px',
          borderRadius: '10px',
          border: '1.5px solid #fca5a5',
          background: dark ? '#450a0a' : '#fff1f2',
        }}>
          <p style={{ margin: '0 0 4px', fontWeight: 700, color: '#dc2626', fontSize: '14px' }}>
            ⚠️ ¿Estás seguro?
          </p>
          <p style={{ margin: '0 0 12px', fontSize: '13px', color: dark ? '#fca5a5' : '#b91c1c' }}>
            Perderás el acceso de admin y lo cederás a{' '}
            <code style={{ fontFamily: 'monospace' }}>{newAdmin.slice(0, 6)}…{newAdmin.slice(-4)}</code>.
            Esta acción no se puede deshacer.
          </p>
          <div style={{ display: 'flex', gap: '10px' }}>
            <button
              onClick={handleConfirm}
              style={{ ...btnPrimary(false), background: '#dc2626' }}
            >
              Confirmar transferencia
            </button>
            <button
              onClick={() => setShowConfirm(false)}
              style={btnSecondary}
            >
              Cancelar
            </button>
          </div>
        </div>
      )}
    </Card>
  )
}

// ---------------------------------------------------------------------------
// ActorsList — tabla de actores registrados
// ---------------------------------------------------------------------------
function ActorsList({ push, isSyncing, onSync }: { push: ReturnType<typeof useToast>['push']; isSyncing: boolean; onSync: () => void }) {
  const { dark } = useDark()
  const { addrs } = useKnownActors()
  const [filterActive, setFilterActive] = useState<'all' | 'active' | 'inactive'>('all')
  const [filterRole, setFilterRole] = useState<number | 'all'>('all')

  const btnFilter = (current: typeof filterActive, value: typeof filterActive, label: string) => {
    const isSelected = filterActive === value
    return (
      <button
        onClick={() => setFilterActive(value)}
        style={isSelected ? {
          fontWeight: 700,
          transform: 'scale(1.07)',
          background: '#166534',
          color: '#fff',
          border: '0px solid #166534',
          borderRadius: '5px',
          padding: '6px 14px',
          fontSize: '12px',
          textTransform: 'uppercase' as const,
          letterSpacing: '0.05em',
          transition: 'all 0.15s',
          cursor: 'pointer',
        } : {
          fontWeight: 600,
          background: dark ? '#334155' : '#fff',
          color: dark ? '#94a3b8' : '#64748b',
          border: `1.5px solid ${dark ? '#475569' : '#e2e8f0'}`,
          borderRadius: '5px',
          padding: '6px 14px',
          fontSize: '12px',
          textTransform: 'uppercase' as const,
          letterSpacing: '0.05em',
          transition: 'all 0.15s',
          cursor: 'pointer',
        }}
      >
        {isSelected ? '✓ ' : ''}{label}
      </button>
    )
  }

  const btnRoleFilter = (roleIdx: number | 'all', label: string) => {
    const isSelected = filterRole === roleIdx
    return (
      <button
        key={String(roleIdx)}
        onClick={() => setFilterRole(roleIdx)}
        style={isSelected ? {
          fontWeight: 700,
          transform: 'scale(1.07)',
          background: '#166534',
          color: '#fff',
          border: '0px solid #166534',
          borderRadius: '5px',
          padding: '6px 14px',
          fontSize: '12px',
          textTransform: 'uppercase' as const,
          letterSpacing: '0.05em',
          transition: 'all 0.15s',
          cursor: 'pointer',
        } : {
          fontWeight: 600,
          background: dark ? '#334155' : '#fff',
          color: dark ? '#94a3b8' : '#64748b',
          border: `1.5px solid ${dark ? '#475569' : '#e2e8f0'}`,
          borderRadius: '5px',
          padding: '6px 14px',
          fontSize: '12px',
          textTransform: 'uppercase' as const,
          letterSpacing: '0.05em',
          transition: 'all 0.15s',
          cursor: 'pointer',
        }}
      >
        {isSelected ? '✓ ' : (roleIdx !== 'all' ? `${ROLE_ICONS[roleIdx as number] ?? ''} ` : '')}{label}
      </button>
    )
  }

  return (
    <SectionHeader>
      <div className="border-l-4 border-indigo-500 px-6 pt-6 pb-4">
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '12px', marginBottom: '12px' }}>
          <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: 0 }}>
            Actores Registrados{' '}
            <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
              ({addrs.length} dirección(es) · datos leídos on-chain en tiempo real)
            </span>
          </h2>
          <button
            onClick={onSync}
            disabled={isSyncing}
            title="Lee todos los eventos ActorRegistered del contrato y actualiza la lista."
            style={{ ...btnSecondary, opacity: isSyncing ? 0.5 : 1, flexShrink: 0 }}
          >
            {isSyncing ? '⏳ Sincronizando…' : '⛓ Sync desde chain'}
          </button>
        </div>

        {/* Filtro por rol */}
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center' }}>
          <span style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', color: dark ? '#64748b' : '#94a3b8', letterSpacing: '0.05em' }}>
            &emsp;&emsp;Rol:
          </span>
          {btnRoleFilter('all', 'Todos')}
          {ACTOR_ROLES.slice(1).map((roleName, i) => btnRoleFilter(i + 1, roleName))}
        </div>

        {/* Filtro por estado */}
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginTop: '20px', alignItems: 'center' }}>
          <span style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', color: dark ? '#64748b' : '#94a3b8', letterSpacing: '0.05em' }}>
            Estado:
          </span>
          {btnFilter(filterActive, 'all',      'Todos')}
          {btnFilter(filterActive, 'active',   '✅ Activos')}
          {btnFilter(filterActive, 'inactive', '🚫 Inactivos')}
        </div>
      </div>

      <div className="px-6 pb-6">
        {addrs.length === 0 ? (
          <div style={{ padding: '48px 0', textAlign: 'center', color: dark ? '#475569' : '#94a3b8' }}>
            <div style={{ fontSize: '32px', marginBottom: '10px' }}>👥</div>
            <p style={{ fontSize: '14px', margin: '0 0 4px' }}>No hay actores registrados aún.</p>
            <p style={{ fontSize: '12px' }}>Registra un actor en el formulario de arriba o sincroniza desde la blockchain.</p>
          </div>
        ) : (
          <div style={{ marginTop: '8px', borderRadius: '8px', overflowX: 'auto', overflowY: 'auto', maxHeight: '600px', WebkitOverflowScrolling: 'touch', border: '0.5px solid #e2e8f0' }}>
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse', tableLayout: 'fixed' }}>
              <colgroup>
                <col style={{ width: '28%' }} />
                <col style={{ width: '20%' }} />
                <col style={{ width: '14%' }} />
                <col style={{ width: '24%' }} />
                <col style={{ width: '14%' }} />
              </colgroup>
              <thead>
                <tr>
                  {['Nombre', 'Dirección', 'Rol', 'Ubicación', 'Acción'].map(h => (
                    <th key={h} style={TH_STYLE}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {addrs.map(a => (
                  <ActorRow key={a} address={a as Address} push={push} filterActive={filterActive} filterRole={filterRole} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </SectionHeader>
  )
}

// ---------------------------------------------------------------------------
// ActorRow — fila individual de actor
// ---------------------------------------------------------------------------
function ActorRow({ address, push, filterActive, filterRole }: { address: Address; push: ReturnType<typeof useToast>['push']; filterActive: 'all' | 'active' | 'inactive'; filterRole: number | 'all' }) {
  const { dark } = useDark()
  const { data: actor, refetch }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getActor', args: [address],
  })

  const { write, isPending } = useTx(push)
  const publicClient = usePublicClient()
  const { address: account } = useAccount()

  const handleToggleActive = async () => {
    const fn = actor.isActive ? 'deactivateActor' : 'reactivateActor'
    try {
      await publicClient?.simulateContract({
        address: CONTRACT_ADDRESS, abi: ABI, functionName: fn,
        args: [address], account: account as Address,
      })
    } catch (e: any) {
      push(parseContractError(e), 'err')
      return
    }
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

  if (filterActive === 'active'   && !isActive) return null
  if (filterActive === 'inactive' &&  isActive) return null
  if (filterRole !== 'all' && roleIdx !== filterRole) return null

  return (
    <tr style={{ opacity: isActive ? 1 : 0.6 }}
      className={`transition-colors ${isActive
        ? (dark ? 'bg-slate-800 hover:bg-slate-700' : 'bg-white hover:bg-slate-50')
        : (dark ? 'bg-slate-900 hover:bg-slate-800' : 'bg-red-50 hover:bg-red-100')}`}
    >
      <td style={TD_STYLE}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
          <span style={{ fontSize: '16px' }}>{ROLE_ICONS[roleIdx] ?? '👤'}</span>
          <div>
            <span style={{ fontSize: '14px', fontWeight: 500, color: dark ? '#e2e8f0' : '#1e293b' }}>{actor.name}</span>
            {!isActive && (
              <span style={{ display: 'block', fontSize: '10px', fontWeight: 700, color: '#ef4444', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Inactivo</span>
            )}
          </div>
        </div>
      </td>
      <td style={TD_STYLE}>
        <code style={{ fontSize: '12px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b', whiteSpace: 'nowrap' }}>
          {address.slice(0, 6)}…{address.slice(-4)}
        </code>
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
