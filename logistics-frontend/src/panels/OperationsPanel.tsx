import { useState, useEffect, useRef } from 'react'
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
  btnPrimary,
  btnDanger,
  inputStyle,
  labelStyle,
  TH_STYLE,
  TD_STYLE,
  CHECKPOINT_TYPES,
  SHIPMENT_STATUSES,
  INCIDENT_TYPES,
  TEMPERATURE_NOT_SET,
  tempIsUnset,
  tempIsOutOfRange,
  tempDisplay,
  shortAddr,
  fmtTs,
  Card,
  FieldError,
} from '../shared'
import { LocationSelect } from './LocationSelect'

// ---------------------------------------------------------------------------
// OperationsPanel — panel principal de operaciones
// ---------------------------------------------------------------------------
export function OperationsPanel({ push }: { push: ReturnType<typeof useToast>['push'] }) {
  const { dark } = useDark()
  const [globalShipId, setGlobalShipId] = useState('')
  const [globalShipStatus, setGlobalShipStatus] = useState<number | null>(null)
  const [globalShipStatusLoading, setGlobalShipStatusLoading] = useState(false)
  const [globalShipNotFound, setGlobalShipNotFound] = useState(false)
  const [cpForm, setCpForm] = useState({ loc: '', type: -1, notes: '', temp: '', noTemp: false })
  const [statusForm, setStatusForm] = useState({ status: -1 })
  const [confirmOpenIncidents, setConfirmOpenIncidents] = useState<number | null>(null)
  const [cpErrors, setCpErrors] = useState<Record<string, string>>({})
  const [incForm, setIncForm] = useState({ type: -1, desc: '' })
  const [incErrors, setIncErrors] = useState<Record<string, string>>({})
  const [sharedSearch, setSharedSearch] = useState('')

  const isDelivered = globalShipStatus === 4
  const shipNotFound = globalShipNotFound
  // Cancelar solo permitido en estado Creado (0) o En hub (2)
  const CANCELLABLE_STATUSES = [0, 2]
  const canCancel = globalShipStatus !== null && CANCELLABLE_STATUSES.includes(globalShipStatus)

  const { write: writeOp, isPending: opPending, isSuccess: opSuccess } = useTx(push)
  const lastOpRef = useRef<null | 'checkpoint' | 'status' | 'confirm' | 'cancel' | 'incident' | 'resolve'>(null)
  const publicClient = usePublicClient()
  const { address } = useAccount()
  const { data: nextShipmentId }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextShipmentId',
  })

  useEffect(() => {
    if (opSuccess) {
      if (lastOpRef.current === 'checkpoint') { setCpForm({ loc: '', type: -1, notes: '', temp: '', noTemp: false }); setCpErrors({}) }
      if (lastOpRef.current === 'confirm') { setConfirmOpenIncidents(null); setGlobalShipStatus(null); setGlobalShipId(''); setSharedSearch('') }
      if (lastOpRef.current === 'status') { setStatusForm({ status: -1 }); setGlobalShipStatus(null); setGlobalShipId(''); setSharedSearch('') }
      if (lastOpRef.current === 'cancel') { setGlobalShipStatus(null); setGlobalShipId(''); setSharedSearch('') }
      if (lastOpRef.current === 'incident') { setIncForm({ type: -1, desc: '' }); setIncErrors({}) }
      lastOpRef.current = null
    }
  }, [opSuccess])

  useEffect(() => {
    if (!globalShipId || isNaN(Number(globalShipId)) || !publicClient) {
      setGlobalShipStatus(null)
      setConfirmOpenIncidents(null)
      setGlobalShipNotFound(false)
      return
    }
    const id = Number(globalShipId)
    if (id <= 0 || (nextShipmentId !== undefined && id >= Number(nextShipmentId))) {
      setGlobalShipStatus(null)
      setConfirmOpenIncidents(null)
      setGlobalShipNotFound(true)
      setGlobalShipStatusLoading(false)
      return
    }
    let cancelled = false
    setGlobalShipNotFound(false)
    setGlobalShipStatusLoading(true)
    Promise.all([
      publicClient.readContract({
        address: CONTRACT_ADDRESS,
        abi: ABI,
        functionName: 'getShipment',
        args: [BigInt(globalShipId)],
      }),
      publicClient.readContract({
        address: CONTRACT_ADDRESS,
        abi: ABI,
        functionName: 'getShipmentIncidents',
        args: [BigInt(globalShipId), BigInt(0), BigInt(50)],
      }),
    ]).then(([shipment, incidents]: any) => {
      if (cancelled) return
      const status = shipment?.status !== undefined ? Number(shipment.status) : null
      setGlobalShipStatus(status)
      const open = (incidents ?? []).filter((inc: any) => !inc.resolved).length
      setConfirmOpenIncidents(open)
    }).catch(() => {
      if (!cancelled) { setGlobalShipStatus(null); setConfirmOpenIncidents(null); setGlobalShipNotFound(true) }
    }).finally(() => { if (!cancelled) setGlobalShipStatusLoading(false) })
    return () => { cancelled = true }
  }, [globalShipId, publicClient, nextShipmentId])

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
    if (!globalShipId || isNaN(Number(globalShipId))) e.id = 'Ingresa el ID de envío arriba'
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
    const args = [BigInt(globalShipId), cpForm.loc, cpForm.type, cpForm.notes || 'OK', tempArg]
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
    if (!globalShipId) return push('ID de envío requerido', 'err')
    if (statusForm.status === -1) return push('Selecciona un estado', 'err')
    const ok = await simulate('updateShipmentStatus', [BigInt(globalShipId), statusForm.status])
    if (!ok) { setStatusForm({ status: -1 }); return }
    lastOpRef.current = 'status'
    writeOp(
      { address: CONTRACT_ADDRESS, abi: ABI, functionName: 'updateShipmentStatus', args: [BigInt(globalShipId), statusForm.status] },
      { onSuccess: () => setStatusForm({ status: -1 }) }
    )
  }

  const handleConfirm = async () => {
    if (!globalShipId) return push('ID de envío requerido', 'err')
    if (globalShipStatus === 4) return push(`El envío #${globalShipId} ya fue entregado.`, 'err')
    if (globalShipStatus !== 3) return push(`Cambia primero el estado del envío #${globalShipId} a "Para entrega" antes de confirmar la entrega final.`, 'err')
    if (confirmOpenIncidents !== null && confirmOpenIncidents > 0)
      return push(`Hay ${confirmOpenIncidents} incidencia${confirmOpenIncidents > 1 ? 's' : ''} abierta${confirmOpenIncidents > 1 ? 's' : ''} sin resolver. Resuélvelas antes de confirmar.`, 'err')

    const ok = await simulate('confirmDelivery', [BigInt(globalShipId)])
    if (!ok) return
    lastOpRef.current = 'confirm'
    writeOp({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'confirmDelivery', args: [BigInt(globalShipId)] })
  }

  const handleCancel = async () => {
    if (!globalShipId) return push('ID de envío requerido', 'err')
    const ok = await simulate('cancelShipment', [BigInt(globalShipId)])
    if (!ok) return
    lastOpRef.current = 'cancel'
    writeOp({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'cancelShipment', args: [BigInt(globalShipId)] })
  }

  const validateInc = () => {
    const e: Record<string, string> = {}
    if (!globalShipId || isNaN(Number(globalShipId))) e.id = 'Ingresa el ID de envío arriba'
    if (incForm.type === -1) e.type = 'Seleccione un tipo'
    if (!incForm.desc.trim()) e.desc = 'Campo requerido'
    setIncErrors(e)
    return Object.keys(e).length === 0
  }

  const handleIncident = async () => {
    if (!validateInc()) return
    const args = [BigInt(globalShipId), incForm.type, incForm.desc]
    const ok = await simulate('reportIncident', args)
    if (!ok) return
    lastOpRef.current = 'incident'
    writeOp({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'reportIncident', args })
  }

  const subSectionTitle = (label: string, color = '#059669') => (
    <p style={{ fontFamily: 'Inter, system-ui, sans-serif', fontSize: '14px', fontWeight: 700, color, textTransform: 'uppercase', marginBottom: '12px', textDecoration: 'underline', textUnderlineOffset: '3px' }}>
      {label}
    </p>
  )

  return (
    <Card accent="orange">
      <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 12px' }}>
        Operaciones{' '}
        <span style={{ fontSize: '13px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
          (Registrar checkpoint, cambiar estado, confirmar entrega o cancelar.)
        </span>
      </h2>

      {/* GLOBAL SHIPMENT ID */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', padding: '12px 16px', borderRadius: '10px', backgroundColor: dark ? '#1e293b' : '#f1f5f9', border: `1px solid ${dark ? '#334155' : '#e2e8f0'}`, marginBottom: '20px' }}>
        <span style={{ fontSize: '13px', fontWeight: 700, color: dark ? '#94a3b8' : '#64748b', whiteSpace: 'nowrap' }}>📦 ID Envío</span>
        <input
          type="number" min="1" placeholder="Ingresa el ID del envío…"
          value={globalShipId}
          onChange={e => { setGlobalShipId(e.target.value); setSharedSearch(e.target.value); setGlobalShipStatus(null); setConfirmOpenIncidents(null) }}
          style={{ ...inputStyle(dark), flex: '0 0 180px', width: '180px', margin: 0 }}
        />
        {globalShipStatusLoading && (
          <span style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8' }}>⏳ Verificando…</span>
        )}
        {!globalShipStatusLoading && shipNotFound && globalShipId && (
          <span style={{
            fontSize: '12px', fontWeight: 700, padding: '3px 10px', borderRadius: '6px',
            backgroundColor: dark ? '#450a0a' : '#fef2f2',
            color: dark ? '#fca5a5' : '#dc2626',
            border: `1px solid ${dark ? '#991b1b' : '#fecaca'}`,
          }}>
            ❌ Envío no encontrado
          </span>
        )}
        {!globalShipStatusLoading && globalShipStatus !== null && (
          <span style={{
            fontSize: '12px', fontWeight: 700, padding: '3px 10px', borderRadius: '6px',
            backgroundColor: isDelivered ? (dark ? '#1e3a5f' : '#eff6ff') : (dark ? '#1e293b' : '#f8fafc'),
            color: isDelivered ? (dark ? '#93c5fd' : '#1d4ed8') : (dark ? '#e2e8f0' : '#1e293b'),
            border: `1px solid ${isDelivered ? (dark ? '#1d4ed8' : '#bfdbfe') : (dark ? '#475569' : '#cbd5e1')}`,
          }}>
            {isDelivered ? '📦 ' : '🔖 '}
            {SHIPMENT_STATUSES[globalShipStatus] ?? `Estado ${globalShipStatus}`}
            {' '}
            <span style={{ opacity: 0.5, fontWeight: 400 }}>({globalShipStatus})</span>
          </span>
        )}
      </div>

      {/* BLOQUEO GLOBAL — envío ya entregado */}
      {isDelivered && (
        <div style={{ marginBottom: '20px', padding: '12px 16px', borderRadius: '10px', backgroundColor: dark ? '#1e3a5f' : '#eff6ff', border: `1px solid ${dark ? '#1d4ed8' : '#bfdbfe'}`, display: 'flex', alignItems: 'flex-start', gap: '10px' }}>
          <span style={{ fontSize: '18px', flexShrink: 0 }}>📦</span>
          <p style={{ margin: 0, fontSize: '13px', fontWeight: 600, color: dark ? '#93c5fd' : '#1d4ed8', lineHeight: '1.5' }}>
            El envío <strong>#{globalShipId}</strong> ya fue entregado. No es posible registrar checkpoints, cambiar el estado, confirmar entrega, cancelar ni reportar incidencias sobre este envío.
            Solo puedes consultar su trazabilidad o generar el PDF.
          </p>
        </div>
      )}

      {/* BLOQUEO GLOBAL — envío no existe */}
      {shipNotFound && globalShipId && (
        <div style={{ marginBottom: '20px', padding: '12px 16px', borderRadius: '10px', backgroundColor: dark ? '#450a0a' : '#fef2f2', border: `1px solid ${dark ? '#991b1b' : '#fecaca'}`, display: 'flex', alignItems: 'flex-start', gap: '10px' }}>
          <span style={{ fontSize: '18px', flexShrink: 0 }}>❌</span>
          <p style={{ margin: 0, fontSize: '13px', fontWeight: 600, color: dark ? '#fca5a5' : '#dc2626', lineHeight: '1.5' }}>
            El envío <strong>#{globalShipId}</strong> no existe. Verifica el ID ingresado.
          </p>
        </div>
      )}

      {/* CHECKPOINT */}
      <div className="mt-5">
        {subSectionTitle('📍 Registrar Checkpoint')}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '12px' }}>
          <div>
            <label style={labelStyle(dark)}>Ubicación actual</label>
            <LocationSelect
              value={cpForm.loc}
              onChange={loc => setCpForm({ ...cpForm, loc })}
              dark={dark}
              hasError={!!cpErrors.loc}
            />
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
          <button onClick={handleCheckpoint} disabled={opPending || isDelivered || shipNotFound || !globalShipId} style={btnPrimary(opPending || isDelivered || shipNotFound || !globalShipId)}>
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
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <label style={{ ...labelStyle(dark), whiteSpace: 'nowrap', margin: 0 }}>Nuevo estado</label>
            <select value={statusForm.status} onChange={e => setStatusForm({ ...statusForm, status: Number(e.target.value) })} style={{ ...inputStyle(dark), flex: '0 1 160px', maxWidth: '160px' }}>
              <option value={-1} disabled>— Estado —</option>
              {SHIPMENT_STATUSES.map((s, i) => i !== 4 ? <option key={i} value={i}>{s}</option> : null)}
            </select>
          </div>
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '16px' }}>
            <button onClick={handleStatus} disabled={opPending || isDelivered || shipNotFound || !globalShipId} style={btnPrimary(opPending || isDelivered || shipNotFound || !globalShipId)}>
              {opPending ? '⏳ Procesando…' : 'Actualizar Estado'}
            </button>
          </div>
        </div>

        {/* Confirmar Entrega */}
        <div style={{ paddingLeft: '24px', paddingRight: '24px', borderRight: `1px solid ${dark ? '#334155' : '#e2e8f0'}` }}>
          {subSectionTitle('✅ Confirmar Entrega')}
          <p style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8', marginTop: '-8px', marginBottom: '12px' }}>(Solo recipient)</p>
          {globalShipId && globalShipStatus !== null && globalShipStatus !== 3 && !isDelivered && (
            <div style={{ marginTop: '10px', padding: '8px 12px', borderRadius: '8px', backgroundColor: dark ? '#422006' : '#fffbeb', border: `1px solid ${dark ? '#92400e' : '#fde68a'}`, display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
              <span style={{ fontSize: '14px', flexShrink: 0 }}>⚠️</span>
              <p style={{ margin: 0, fontSize: '12px', fontWeight: 600, color: dark ? '#fcd34d' : '#92400e', lineHeight: '1.4' }}>
                El envío aún no está en estado <strong>"Para entrega"</strong>. Cambie primero el estado a <strong>"Para entrega"</strong> antes de confirmar.
              </p>
            </div>
          )}
          {globalShipId && globalShipStatus === 3 && confirmOpenIncidents !== null && confirmOpenIncidents > 0 && (
            <div style={{ marginTop: '10px', padding: '8px 12px', borderRadius: '8px', backgroundColor: dark ? '#450a0a' : '#fef2f2', border: `1px solid ${dark ? '#991b1b' : '#fecaca'}`, display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
              <span style={{ fontSize: '14px', flexShrink: 0 }}>🔴</span>
              <p style={{ margin: 0, fontSize: '12px', fontWeight: 600, color: dark ? '#fca5a5' : '#dc2626', lineHeight: '1.4' }}>
                {confirmOpenIncidents} incidencia{confirmOpenIncidents > 1 ? 's' : ''} abierta{confirmOpenIncidents > 1 ? 's' : ''} sin resolver. Resuélvalas antes de confirmar.
              </p>
            </div>
          )}
          {globalShipId && globalShipStatus === 3 && confirmOpenIncidents === 0 && (
            <div style={{ marginTop: '10px', padding: '8px 12px', borderRadius: '8px', backgroundColor: dark ? '#052e16' : '#f0fdf4', border: `1px solid ${dark ? '#166534' : '#bbf7d0'}` }}>
              <p style={{ margin: 0, fontSize: '12px', fontWeight: 600, color: dark ? '#86efac' : '#16a34a' }}>
                ✅ Sin incidencias abiertas, puede confirmar la entrega.
              </p>
            </div>
          )}
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '16px' }}>
            <button
              onClick={handleConfirm}
              disabled={opPending || isDelivered || shipNotFound || !globalShipId || globalShipStatus !== 3 || (confirmOpenIncidents !== null && confirmOpenIncidents > 0)}
              style={btnPrimary(opPending || isDelivered || shipNotFound || !globalShipId || globalShipStatus !== 3 || (confirmOpenIncidents !== null && confirmOpenIncidents > 0))}
            >
              {opPending ? '⏳ …' : 'Confirmar Entrega'}
            </button>
          </div>
        </div>

        {/* Cancelar Envío */}
        <div style={{ paddingLeft: '24px' }}>
          {subSectionTitle('❌ Cancelar Envío', '#dc2626')}
          <p style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8', marginTop: '-8px', marginBottom: '12px' }}>(Solo sender)</p>
          {globalShipId && globalShipStatus !== null && !shipNotFound && !canCancel && (
            <div style={{ marginBottom: '10px', padding: '8px 12px', borderRadius: '8px', backgroundColor: dark ? '#422006' : '#fffbeb', border: `1px solid ${dark ? '#92400e' : '#fde68a'}`, display: 'flex', alignItems: 'flex-start', gap: '8px' }}>
              <span style={{ fontSize: '14px', flexShrink: 0 }}>⚠️</span>
              <p style={{ margin: 0, fontSize: '12px', fontWeight: 600, color: dark ? '#fcd34d' : '#92400e', lineHeight: '1.4' }}>
                Solo se puede cancelar un envío en estado <strong>Creado</strong> o <strong>En Hub</strong>.
              </p>
            </div>
          )}
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '10px' }}>
            <button onClick={handleCancel} disabled={opPending || shipNotFound || !globalShipId || !canCancel} style={btnDanger(opPending || shipNotFound || !globalShipId || !canCancel)}>
              {opPending ? '⏳ …' : 'Cancelar Envío'}
            </button>
          </div>
        </div>
      </div>

      <hr style={{ border: 'none', borderTop: `1px solid ${dark ? '#334155' : '#e2e8f0'}`, margin: '16px 0' }} />

      {/* REPORTAR INCIDENCIA */}
      <div className="mt-2">
        {subSectionTitle('⚠️ Reportar Incidencia', '#d97706')}
        <p style={{ fontSize: '12px', color: dark ? '#64748b' : '#94a3b8', marginTop: '-8px', marginBottom: '12px' }}>
          (Cualquier actor asignado al envío puede reportar una incidencia)
        </p>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '12px' }}>
          <div>
            <label style={labelStyle(dark)}>Tipo de incidencia</label>
            <select
              value={incForm.type}
              onChange={e => setIncForm({ ...incForm, type: Number(e.target.value) })}
              style={inputStyle(dark, !!incErrors.type)}
            >
              <option value={-1} disabled>— Seleccione un tipo —</option>
              {INCIDENT_TYPES.map((t, i) => <option key={i} value={i}>{t}</option>)}
            </select>
            <FieldError msg={incErrors.type} />
          </div>
          <div style={{ gridColumn: 'span 2' }}>
            <label style={labelStyle(dark)}>Descripción detallada</label>
            <textarea
              placeholder="Describa la incidencia con el mayor detalle posible…"
              value={incForm.desc}
              rows={3}
              onChange={e => setIncForm({ ...incForm, desc: e.target.value })}
              style={{ ...inputStyle(dark, !!incErrors.desc), resize: 'vertical', minHeight: '72px' }}
            />
            <FieldError msg={incErrors.desc} />
          </div>
        </div>
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: '14px' }}>
          <button
            onClick={handleIncident}
            disabled={opPending || isDelivered || shipNotFound || !globalShipId}
            style={{ ...btnPrimary(opPending || isDelivered || shipNotFound || !globalShipId), backgroundColor: (opPending || isDelivered || shipNotFound || !globalShipId) ? '#fcd34d' : '#d97706' }}
          >
            {opPending ? '⏳ Registrando…' : '⚠️ Reportar Incidencia'}
          </button>
        </div>
      </div>

      <hr style={{ border: 'none', borderTop: `1px solid ${dark ? '#334155' : '#e2e8f0'}`, margin: '16px 0' }} />
      <CheckpointsTable sharedSearch={sharedSearch} setSharedSearch={setSharedSearch} />
      <div style={{ marginTop: '20px' }}>
        <IncidentsTable push={push} sharedSearch={sharedSearch} setSharedSearch={setSharedSearch} />
      </div>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// CheckpointsTable — tabla de checkpoints dentro de Operaciones
// ---------------------------------------------------------------------------
function CheckpointsTable({ sharedSearch, setSharedSearch }: { sharedSearch: string; setSharedSearch: (v: string) => void }) {
  const { dark } = useDark()
  const { data: nextShipId, refetch: refetchShip }: any = useReadContract({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextShipmentId' })
  const { data: nextCpId, refetch: refetchCp }: any    = useReadContract({ address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextCheckpointId' })

  const totalShipments = nextShipId ? Number(nextShipId) - 1 : 0
  const totalCps       = nextCpId   ? Number(nextCpId)   - 1 : 0
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const interval = setInterval(() => { refetchShip(); refetchCp(); setTick(t => t + 1) }, 3000)
    return () => clearInterval(interval)
  }, [refetchShip, refetchCp])

  return (
    <div style={{ backgroundColor: dark ? '#0f172a' : '#f8fafc', borderRadius: '12px', border: `0.5px solid ${dark ? '#334155' : '#e2e8f0'}`, overflow: 'hidden' }}>
      <div className="border-l-4 border-cyan-500 px-5 pt-5 pb-3">
        <h3 style={{ fontSize: '14px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 10px' }}>
          Checkpoints{' '}
          <span style={{ fontSize: '12px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
            ({totalCps} checkpoint(s) en {totalShipments} envío(s))
          </span>
        </h3>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '10px' }}>
          <button
            onClick={() => setSharedSearch('')}
            className={`text-xs font-semibold px-3 py-2 rounded-xl uppercase border transition-colors ${
              sharedSearch === ''
                ? 'bg-cyan-600 text-white border-cyan-600'
                : dark
                  ? 'bg-slate-700 text-slate-300 border-slate-600 hover:border-cyan-400'
                  : 'bg-white text-slate-500 border-slate-200 hover:border-cyan-300'
            }`}
          >Todos</button>
        </div>
        <input
          type="text"
          placeholder="🔍 Filtrar por ID de envío…"
          value={sharedSearch}
          onChange={e => setSharedSearch(e.target.value)}
          className={`w-full border px-3 py-2 rounded-xl text-xs font-semibold outline-none transition-all ${dark ? 'bg-slate-800 border-slate-700 text-slate-200 placeholder-slate-500' : 'bg-slate-50 border-slate-200'}`}
        />
      </div>

      <div className="px-5 pb-5">
        {totalShipments === 0 ? (
          <div style={{ padding: '24px 0', textAlign: 'center', color: dark ? '#475569' : '#94a3b8' }}>
            <p style={{ fontSize: '12px' }}>No hay checkpoints registrados aún.</p>
          </div>
        ) : (
          <div style={{ marginTop: '8px', borderRadius: '8px', overflowX: 'auto', overflowY: 'auto', maxHeight: '480px', border: '0.5px solid #e2e8f0' }}>
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
                  .filter(id => !sharedSearch || String(id) === sharedSearch.trim())
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
// IncidentsTable — tabla de incidencias con botón Resolver
// ---------------------------------------------------------------------------
function IncidentsTable({ push, sharedSearch, setSharedSearch }: { push: ReturnType<typeof useToast>['push']; sharedSearch: string; setSharedSearch: (v: string) => void }) {
  const { dark } = useDark()
  const { data: nextShipId, refetch: refetchShip }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'nextShipmentId',
  })
  const totalShipments = nextShipId ? Number(nextShipId) - 1 : 0
  const [filterResolved, setFilterResolved] = useState<'all' | 'open' | 'resolved'>('all')
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const interval = setInterval(() => { refetchShip(); setTick(t => t + 1) }, 3000)
    return () => clearInterval(interval)
  }, [refetchShip])

  const btnF = (val: typeof filterResolved, label: string) => (
    <button
      onClick={() => { setFilterResolved(val); if (val === 'all') setSharedSearch('') }}
      className={`text-xs font-semibold px-3 py-2 rounded-xl uppercase border transition-colors ${
        filterResolved === val
          ? 'bg-amber-600 text-white border-amber-600'
          : dark
            ? 'bg-slate-700 text-slate-300 border-slate-600 hover:border-amber-400'
            : 'bg-white text-slate-500 border-slate-200 hover:border-amber-300'
      }`}
    >{label}</button>
  )

  return (
    <div style={{ backgroundColor: dark ? '#0f172a' : '#f8fafc', borderRadius: '12px', border: `0.5px solid ${dark ? '#334155' : '#e2e8f0'}`, overflow: 'hidden' }}>
      <div className="border-l-4 border-amber-500 px-5 pt-5 pb-3">
        <h3 style={{ fontSize: '14px', fontWeight: 700, textTransform: 'uppercase', color: dark ? '#f1f5f9' : '#1e293b', margin: '0 0 10px' }}>
          ⚠️ Incidencias{' '}
          <span style={{ fontSize: '12px', fontWeight: 400, color: dark ? '#64748b' : '#94a3b8', textTransform: 'none' }}>
            (Historial de todas las incidencias · botón Resolver para el ADMIN)
          </span>
        </h3>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '10px' }}>
          {btnF('all',      'Todas')}
          {btnF('open',     '🔴 Abiertas')}
          {btnF('resolved', '✅ Resueltas')}
        </div>
        <input
          type="text"
          placeholder="🔍 Filtrar por ID de envío…"
          value={sharedSearch}
          onChange={e => setSharedSearch(e.target.value)}
          className={`w-full border px-3 py-2 rounded-xl text-xs font-semibold outline-none transition-all ${dark ? 'bg-slate-800 border-slate-700 text-slate-200 placeholder-slate-500' : 'bg-slate-50 border-slate-200'}`}
        />
      </div>
      <div className="px-5 pb-5">
        {totalShipments === 0 ? (
          <div style={{ padding: '24px 0', textAlign: 'center', color: dark ? '#475569' : '#94a3b8' }}>
            <p style={{ fontSize: '12px' }}>No hay incidencias registradas aún.</p>
          </div>
        ) : (
          <div style={{ marginTop: '8px', borderRadius: '8px', overflowX: 'auto', overflowY: 'auto', maxHeight: '480px', border: `0.5px solid ${dark ? '#334155' : '#e2e8f0'}` }}>
            <table style={{ width: '100%', textAlign: 'left', borderCollapse: 'separate', borderSpacing: 0 }}>
              <thead>
                <tr>
                  {['#', 'Envío', 'Tipo', 'Descripción', 'Reporter', 'Fecha', 'Estado', 'Acción'].map(h => (
                    <th key={h} style={TH_STYLE}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {Array.from({ length: totalShipments }, (_, i) => i + 1)
                  .filter(id => !sharedSearch || String(id) === sharedSearch.trim())
                  .map(shipId => (
                    <IncidentRows key={shipId} shipmentId={shipId} tick={tick} filterResolved={filterResolved} push={push} />
                  ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}

function IncidentRows({ shipmentId, tick, filterResolved, push }: {
  shipmentId: number
  tick: number
  filterResolved: 'all' | 'open' | 'resolved'
  push: ReturnType<typeof useToast>['push']
}) {
  const { dark } = useDark()
  const { data: incs, refetch }: any = useReadContract({
    address: CONTRACT_ADDRESS, abi: ABI, functionName: 'getShipmentIncidents',
    args: [BigInt(shipmentId), BigInt(0), BigInt(50)],
  })
  const publicClient  = usePublicClient()
  const { address }   = useAccount()
  const { write }     = useTx(push)
  const [resolving, setResolving] = useState<number | null>(null)
  const [resolveModal, setResolveModal] = useState<{ incidentId: bigint; localIdx: number } | null>(null)
  const [resolveNote, setResolveNote] = useState('')



  useEffect(() => { refetch() }, [tick])

  const openResolveModal = (incidentId: bigint, localIdx: number) => {
    setResolveNote('')
    setResolveModal({ incidentId, localIdx })
  }

  const confirmResolve = async () => {
    if (!resolveModal) return
    const { incidentId, localIdx } = resolveModal
    setResolving(localIdx)
    setResolveModal(null)
    const args: [bigint, string] = [incidentId, resolveNote.trim()]
    try {
      await publicClient?.simulateContract({
        address: CONTRACT_ADDRESS, abi: ABI,
        functionName: 'resolveIncident',
        args, account: address as Address,
      })
    } catch (e: any) {
      push(parseContractError(e), 'err')
      setResolving(null)
      return
    }
    write(
      { address: CONTRACT_ADDRESS, abi: ABI, functionName: 'resolveIncident', args },
      { onSuccess: () => { setTimeout(() => refetch(), 2000); setResolving(null) } }
    )
  }

  if (!incs) {
    return (
      <tr>
        {[...Array(8)].map((_, i) => (
          <td key={i} style={TD_STYLE}><div className="h-3 bg-slate-100 rounded w-14 animate-pulse" /></td>
        ))}
      </tr>
    )
  }

  if (incs.length === 0) return null

  const filtered: { inc: any; idx: number }[] = incs
    .map((inc: any, idx: number) => ({ inc, idx }))
    .filter(({ inc }: { inc: any }) => {
      if (filterResolved === 'open')     return !inc.resolved
      if (filterResolved === 'resolved') return  inc.resolved
      return true
    })

  if (filtered.length === 0) return null

  return (
    <>
      {filtered.map(({ inc, idx }) => {
        const isResolved: boolean = inc.resolved
        const isResolving = resolving === idx
        return (
          <tr key={idx} style={{
            backgroundColor: isResolved
              ? (dark ? '#052e16' : '#f0fdf4')
              : (dark ? '#2d1a0e' : '#fff7ed'),
          }}>
            <td style={TD_STYLE}>
              <span style={{ fontSize: '11px', fontWeight: 700, color: '#94a3b8', backgroundColor: dark ? '#1e293b' : '#f1f5f9', padding: '2px 6px', borderRadius: '5px' }}>
                {idx}
              </span>
            </td>
            <td style={TD_STYLE}>
              <span style={{ fontSize: '12px', fontWeight: 700, color: '#64748b', backgroundColor: dark ? '#1e293b' : '#f1f5f9', padding: '2px 7px', borderRadius: '6px' }}>
                #{shipmentId}
              </span>
            </td>
            <td style={TD_STYLE}>
              <span className="text-xs font-semibold px-2 py-1 rounded-md uppercase bg-red-50 text-red-600 border border-red-200">
                {INCIDENT_TYPES[Number(inc.incidentType)] ?? '—'}
              </span>
            </td>
            <td style={{ ...TD_STYLE, minWidth: '200px', whiteSpace: 'normal' }}>
              <span style={{ fontSize: '12px', color: dark ? '#cbd5e1' : '#475569' }}>{inc.description}</span>
            </td>
            <td style={TD_STYLE}>
              <code style={{ fontSize: '11px', fontFamily: 'monospace', color: dark ? '#94a3b8' : '#64748b', backgroundColor: dark ? '#1e293b' : '#f8fafc', border: `1px solid ${dark ? '#334155' : '#e2e8f0'}`, padding: '2px 6px', borderRadius: '5px' }}>
                {shortAddr(inc.reporter)}
              </code>
            </td>
            <td style={TD_STYLE}>
              <span style={{ fontSize: '11px', color: dark ? '#64748b' : '#94a3b8', fontWeight: 500 }}>{fmtTs(inc.timestamp)}</span>
            </td>
            <td style={{ ...TD_STYLE, textAlign: 'center' }}>
              {isResolved
                ? <span style={{ fontSize: '11px', fontWeight: 700, padding: '2px 8px', borderRadius: '6px', backgroundColor: '#dcfce7', color: '#16a34a', border: '1px solid #bbf7d0' }}>✅ Resuelta</span>
                : <span style={{ fontSize: '11px', fontWeight: 700, padding: '2px 8px', borderRadius: '6px', backgroundColor: '#fef2f2', color: '#dc2626', border: '1px solid #fecaca' }}>🔴 Abierta</span>
              }
            </td>
            <td style={{ ...TD_STYLE, textAlign: 'center' }}>
              {!isResolved && (
                resolveModal?.localIdx === idx && resolveModal?.incidentId === inc.id ? (
                  <div style={{ minWidth: '220px', padding: '8px', borderRadius: '8px', backgroundColor: dark ? '#0f172a' : '#f8fafc', border: `1px solid ${dark ? '#334155' : '#e2e8f0'}` }}>
                    <p style={{ margin: '0 0 6px', fontSize: '11px', fontWeight: 700, color: dark ? '#94a3b8' : '#64748b', textTransform: 'uppercase' }}>
                      Notas de resolución
                    </p>
                    <textarea
                      autoFocus
                      rows={3}
                      placeholder="Describe cómo se resolvió la incidencia…"
                      value={resolveNote}
                      onChange={e => setResolveNote(e.target.value)}
                      style={{ width: '100%', fontSize: '12px', padding: '6px 8px', borderRadius: '6px', border: `1px solid ${dark ? '#475569' : '#cbd5e1'}`, backgroundColor: dark ? '#1e293b' : '#fff', color: dark ? '#e2e8f0' : '#1e293b', resize: 'vertical', outline: 'none', boxSizing: 'border-box' }}
                    />
                    <div style={{ display: 'flex', gap: '6px', marginTop: '6px', justifyContent: 'flex-end' }}>
                      <button
                        onClick={() => setResolveModal(null)}
                        className="text-xs font-semibold px-3 py-1.5 rounded-lg border transition-colors bg-slate-50 text-slate-500 border-slate-200 hover:bg-slate-100"
                      >
                        Cancelar
                      </button>
                      <button
                        onClick={confirmResolve}
                        disabled={isResolving}
                        className="text-xs font-semibold px-3 py-1.5 rounded-lg uppercase border transition-colors disabled:opacity-50 bg-cyan-50 text-cyan-700 border-cyan-200 hover:bg-cyan-100"
                      >
                        {isResolving ? '⏳' : '✔ Confirmar'}
                      </button>
                    </div>
                  </div>
                ) : (
                  <button
                    onClick={() => openResolveModal(inc.id, idx)}
                    disabled={isResolving}
                    className="text-xs font-semibold px-3 py-1.5 rounded-lg uppercase border transition-colors disabled:opacity-50 bg-cyan-50 text-cyan-700 border-cyan-200 hover:bg-cyan-100"
                  >
                    {isResolving ? '⏳' : '✔ Resolver'}
                  </button>
                )
              )}
              {isResolved && (() => {
                const note = inc.resolutionNote as string | undefined
                return note ? (
                  <div style={{ maxWidth: '200px', padding: '4px 8px', borderRadius: '6px', backgroundColor: dark ? '#052e16' : '#f0fdf4', border: `1px solid ${dark ? '#166534' : '#bbf7d0'}` }}>
                    <p style={{ margin: 0, fontSize: '11px', color: dark ? '#86efac' : '#15803d', fontStyle: 'italic', whiteSpace: 'normal', lineHeight: '1.4' }}>
                      📋 {note}
                    </p>
                  </div>
                ) : null
              })()}
            </td>
          </tr>
        )
      })}
    </>
  )
}
