import { useState, useEffect } from 'react'
import {
  useReadContract,
  usePublicClient,
  useAccount,
} from 'wagmi'
import { CONTRACT_ADDRESS, ABI } from '../blockchain/config'
import {
  Address,
  useDark,
  useToast,
  useTx,
  parseContractError,
  isValidAddress,
  btnPrimary,
  inputStyle,
  labelStyle,
  TH_STYLE,
  TD_STYLE,
  SHIPMENT_STATUSES,
  STATUS_COLORS,
  shortAddr,
  fmtTs,
  Card,
  SectionHeader,
  FieldError,
} from '../shared'
import { LocationSelect } from './LocationSelect'

// ---------------------------------------------------------------------------
// ShippingPanel — Crear Envío
// ---------------------------------------------------------------------------
export function ShippingPanel({ push }: { push: ReturnType<typeof useToast>['push'] }) {
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
          <LocationSelect
            value={form.ori}
            onChange={ori => setForm({ ...form, ori })}
            dark={dark}
            hasError={!!errors.ori}
          />
          <FieldError msg={errors.ori} />
        </div>
        <div>
          <label style={labelStyle(dark)}>Destino</label>
          <LocationSelect
            value={form.dst}
            onChange={dst => setForm({ ...form, dst })}
            dark={dark}
            hasError={!!errors.dst}
          />
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
// ShipmentsTable — Tabla de todos los envíos
// ---------------------------------------------------------------------------
export function ShipmentsTable() {
  const { dark } = useDark()
  const { data: nextId }: any = useReadContract({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextShipmentId' })
  const total = nextId ? Number(nextId) - 1 : 0
  const ids = Array.from({ length: total }, (_, i) => i + 1)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<number | 'all'>('all')
  const filtered = ids.filter(id => !search || String(id) === search.trim())
  return (
    <SectionHeader>
      <div className="border-l-4 border-teal-500 px-6 pt-6 pb-4">
        <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 12px' }}>
          Envíos{' '}
          <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
            ({total} envío(s) registrado(s) en el contrato)
          </span>
        </h2>
        <div style={{ marginTop: '12px', display: 'flex', flexWrap: 'wrap', gap: '8px' }}>
          <input
            type="text"
            placeholder="🔍 Filtrar por ID…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="flex-1 min-w-[180px] bg-slate-50 border border-slate-200 px-3 py-2 rounded-xl text-xs font-semibold outline-none focus:ring-2 focus:ring-teal-100 transition-all"
          />
          <button
            onClick={() => { setFilterStatus('all'); setSearch('') }}
            style={filterStatus === 'all'
              ? { fontWeight: 700, background: '#0d9488', color: '#fff', border: '1px solid #0d9488', borderRadius: '4px', padding: '3px 12px', fontSize: '12px', textTransform: 'uppercase' as const, letterSpacing: '0.05em', cursor: 'pointer', transition: 'all 0.15s' }
              : { fontWeight: 600, background: '#d3d3d3', color: '#64748b', border: '1px solid #e2e8f0', borderRadius: '4px', padding: '3px 12px', fontSize: '12px', textTransform: 'uppercase' as const, letterSpacing: '0.05em', cursor: 'pointer', transition: 'all 0.15s' }}
          >Todos</button>
          {SHIPMENT_STATUSES.map((s, i) => (
            <button
              key={i}
              onClick={() => setFilterStatus(i)}
              style={filterStatus === i
                ? { fontWeight: 700, background: '#0d9488', color: '#fff', border: '1px solid #0d9488', borderRadius: '4px', padding: '3px 12px', fontSize: '12px', textTransform: 'uppercase' as const, letterSpacing: '0.05em', cursor: 'pointer', transition: 'all 0.15s' }
                : { fontWeight: 600, background: '#d3d3d3', color: '#64748b', border: '1px solid #e2e8f0', borderRadius: '4px', padding: '3px 12px', fontSize: '12px', textTransform: 'uppercase' as const, letterSpacing: '0.05em', cursor: 'pointer', transition: 'all 0.15s' }}
            >{s}</button>
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
          <div style={{ marginTop: '8px', borderRadius: '8px', overflowX: 'auto', overflowY: 'auto', maxHeight: '520px', WebkitOverflowScrolling: 'touch', border: '0.5px solid #e2e8f0' }}>
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'separate', borderSpacing: 0 }}>
              <thead>
                <tr>
				  {[
					{ label: 'ID',                        width: '8%'  },
					{ label: 'Producto',                  width: '28%' },
					{ label: 'Remitente / Destinatario',  width: '31%' },
					{ label: 'Ruta',                      width: '19%' },
					{ label: 'Estado / Fecha',            width: '14%' },
				  ].map(h => (
				  <th key={h.label} style={{ ...TH_STYLE, width: h.width, whiteSpace: 'nowrap' }}>{h.label}</th>
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

// ---------------------------------------------------------------------------
// ShipmentRow — fila individual de envío
// ---------------------------------------------------------------------------
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
	  <td style={{ ...TD_STYLE, maxWidth: '40px', width: '40px' }}>
        <span style={{ fontSize: '13px', fontWeight: 700, color: '#64748b', backgroundColor: '#f1f5f9', padding: '2px 8px', borderRadius: '6px' }}>#{String(s.id)}</span>
        {s.requiresColdChain && <div style={{ marginTop: '4px' }}><span style={{ fontSize: '11px', fontWeight: 600, color: '#3b82f6', backgroundColor: '#eff6ff', border: '1px solid #bfdbfe', padding: '1px 6px', borderRadius: '5px' }}>❄ Frío</span></div>}
      </td>
	  <td style={{ ...TD_STYLE, maxWidth: '190px', width: '190px' }}>
        <div style={{ fontSize: '14px', fontWeight: 500, color: dark ? '#e2e8f0' : '#1e293b', wordBreak: 'break-word', whiteSpace: 'normal' }}>{s.product}</div>
      </td>
	  <td style={{ ...TD_STYLE, maxWidth: '220px', width: '220px' }}>
	    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
	      <div style={{ display: 'flex', flexDirection: 'column' }}>
	        <span style={{ fontSize: '10px', fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', marginBottom: '1px' }}>De:</span>
	        <code style={{ fontSize: '13px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b', wordBreak: 'break-all', whiteSpace: 'normal' }}>{s.sender}</code>
	      </div>
	      <div style={{ display: 'flex', flexDirection: 'column' }}>
	        <span style={{ fontSize: '10px', fontWeight: 700, color: '#94a3b8', textTransform: 'uppercase', marginBottom: '1px' }}>Para:</span>
	        <code style={{ fontSize: '13px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b', wordBreak: 'break-all', whiteSpace: 'normal' }}>{s.recipient === zeroAddr ? '—' : s.recipient}</code>
	      </div>
	    </div>
	  </td>
	  <td style={{ ...TD_STYLE, maxWidth: '120px', width: '120px' }}>
        <div style={{ fontSize: '13px', color: dark ? '#94a3b8' : '#64748b' }}>{s.origin}</div>
        <div style={{ fontSize: '13px', color: '#cbd5e1' }}>↓</div>
        <div style={{ fontSize: '13px', color: dark ? '#94a3b8' : '#64748b' }}>{s.destination}</div>
      </td>
	  <td style={{ ...TD_STYLE, maxWidth: '65px', width: '65px' }}>
        <span className={`text-sm font-semibold px-2 py-1 rounded-lg uppercase ${STATUS_COLORS[statusIdx] ?? 'bg-slate-100 text-slate-500'}`} style={{ display: 'inline-block' }}>
          {SHIPMENT_STATUSES[statusIdx] ?? '—'}
        </span>
        <div style={{ fontSize: '14px', color: dark ? '#64748b' : '#94a3b8', marginTop: '4px' }}>
          {new Date(Number(s.dateCreated) * 1000).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' })}
        </div>
      </td>
    </tr>
  )
}
