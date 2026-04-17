import { useState, useRef } from 'react'
import { useDark, Card } from '../shared'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const ANVIL_RPC = 'http://localhost:8545'

async function rpc(method: string, params: any[] = []): Promise<any> {
  const res = await fetch(ANVIL_RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', method, params, id: Date.now() }),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  if (json.error) throw new Error(json.error.message ?? 'RPC error')
  return json.result
}

function downloadJson(data: string, filename = 'anvil-state.json') {
  const blob = new Blob([data], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

// ---------------------------------------------------------------------------
// AnvilStatePanel
// ---------------------------------------------------------------------------
export function AnvilStatePanel() {
  const { dark } = useDark()

  // dump
  const [dumping, setDumping] = useState(false)
  const [dumpOk, setDumpOk] = useState(false)
  const [dumpErr, setDumpErr] = useState('')

  // load
  const [loading, setLoading] = useState(false)
  const [loadOk, setLoadOk] = useState(false)
  const [loadErr, setLoadErr] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  // ── DUMP ──────────────────────────────────────────────────────────────────
  const handleDump = async () => {
    setDumping(true)
    setDumpOk(false)
    setDumpErr('')
    try {
      const result = await rpc('anvil_dumpState')
      // result is a hex string; save as JSON wrapper for easy identification
      const payload = JSON.stringify({ anvilState: result, savedAt: new Date().toISOString() }, null, 2)
      const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
      downloadJson(payload, `anvil-state-${ts}.json`)
      setDumpOk(true)
      setTimeout(() => setDumpOk(false), 3500)
    } catch (e: any) {
      setDumpErr(e.message ?? 'Error al conectar con Anvil')
    } finally {
      setDumping(false)
    }
  }

  // ── LOAD ──────────────────────────────────────────────────────────────────
  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setLoading(true)
    setLoadOk(false)
    setLoadErr('')
    try {
      const text = await file.text()
      const parsed = JSON.parse(text)
      // accept both raw hex string and our wrapped format
      const stateHex: string = typeof parsed === 'string' ? parsed : parsed.anvilState
      if (!stateHex || typeof stateHex !== 'string') throw new Error('Formato de archivo inválido')
      await rpc('anvil_loadState', [stateHex])
      setLoadOk(true)
      setTimeout(() => setLoadOk(false), 3500)
    } catch (e: any) {
      setLoadErr(e.message ?? 'Error al cargar el estado')
    } finally {
      setLoading(false)
      // reset input so the same file can be re-selected
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  // ── Styles ────────────────────────────────────────────────────────────────
  const border = dark ? '#334155' : '#e2e8f0'
  const bg2    = dark ? '#1e293b' : '#f8fafc'
  const muted  = dark ? '#64748b' : '#94a3b8'
  const text   = dark ? '#e2e8f0' : '#1e293b'

  const sectionBox = {
    padding: '16px 20px',
    borderRadius: '12px',
    border: `1px solid ${border}`,
    backgroundColor: bg2,
  }

  const label14 = {
    fontSize: '13px',
    fontWeight: 700 as const,
    color: text,
    marginBottom: '4px',
    display: 'block' as const,
  }

  const hint = {
    fontSize: '11px',
    color: muted,
    marginBottom: '12px',
    lineHeight: '1.5',
  }

  const btnBase = {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '6px',
    padding: '7px 16px',
    borderRadius: '8px',
    fontSize: '12px',
    fontWeight: 700 as const,
    cursor: 'pointer',
    border: 'none',
    transition: 'opacity .15s',
  }

  const btnSave = {
    ...btnBase,
    backgroundColor: '#0e7490',
    color: '#fff',
  }

  const btnLoad = {
    ...btnBase,
    backgroundColor: dark ? '#1e3a5f' : '#dbeafe',
    color: dark ? '#93c5fd' : '#1d4ed8',
    border: `1px solid ${dark ? '#2563eb44' : '#bfdbfe'}`,
  }

  const tag = (ok: boolean, err: string) => {
    if (err) return (
      <span style={{ fontSize: '11px', fontWeight: 600, color: '#ef4444', backgroundColor: dark ? '#450a0a' : '#fef2f2', border: '1px solid #fca5a5', padding: '3px 8px', borderRadius: '6px' }}>
        ✗ {err}
      </span>
    )
    if (ok) return (
      <span style={{ fontSize: '11px', fontWeight: 600, color: '#16a34a', backgroundColor: dark ? '#052e16' : '#f0fdf4', border: '1px solid #86efac', padding: '3px 8px', borderRadius: '6px' }}>
        ✓ Listo
      </span>
    )
    return null
  }

  return (
    <Card accent="cyan">
      {/* Header */}
      <div style={{ marginBottom: '18px' }}>
        <h2 style={{ fontSize: '17px', fontWeight: 700, textTransform: 'uppercase', color: text, margin: '0 0 4px' }}>
          Estado Anvil{' '}
          <span style={{ fontSize: '13px', fontWeight: 400, color: muted, textTransform: 'none' }}>
            (Guardar y restaurar el estado de la blockchain local.)
          </span>
        </h2>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '6px' }}>
          <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#22c55e', display: 'inline-block', boxShadow: '0 0 0 3px #22c55e33' }} />
          <span style={{ fontSize: '11px', color: muted, fontWeight: 500 }}>
            Nodo local · {ANVIL_RPC}
          </span>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>

        {/* ── GUARDAR ── */}
        <div style={sectionBox}>
          <span style={label14}>💾 Guardar estado</span>
          <p style={hint}>
            Descarga un snapshot completo del estado actual de Anvil (contratos, balances, nonces, storage).<br />
            Úsalo con <code style={{ backgroundColor: dark ? '#0f172a' : '#f1f5f9', padding: '1px 5px', borderRadius: '4px', fontSize: '11px' }}>anvil --load-state</code> para restaurar.
          </p>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap' }}>
            <button
              onClick={handleDump}
              disabled={dumping}
              style={{ ...btnSave, opacity: dumping ? 0.6 : 1 }}
            >
              {dumping ? '⏳' : '⬇'} {dumping ? 'Exportando…' : 'Descargar snapshot'}
            </button>
            {tag(dumpOk, dumpErr)}
          </div>
        </div>

        {/* ── CARGAR ── */}
        <div style={sectionBox}>
          <span style={label14}>📂 Restaurar estado</span>
          <p style={hint}>
            Carga un snapshot previamente guardado directamente en la sesión de Anvil activa.<br />
            El estado del nodo se reemplaza de inmediato, no requiere reiniciar.
          </p>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap' }}>
            <button
              onClick={() => fileRef.current?.click()}
              disabled={loading}
              style={{ ...btnLoad, opacity: loading ? 0.6 : 1 }}
            >
              {loading ? '⏳' : '📁'} {loading ? 'Cargando…' : 'Seleccionar archivo'}
            </button>
            <input
              ref={fileRef}
              type="file"
              accept=".json"
              style={{ display: 'none' }}
              onChange={handleFileChange}
            />
            {tag(loadOk, loadErr)}
          </div>
        </div>

      </div>

      {/* Footer note */}
      <p style={{ fontSize: '11px', color: muted, marginTop: '14px', lineHeight: '1.6', borderTop: `1px solid ${border}`, paddingTop: '12px' }}>
        ⚠ <strong>Solo para desarrollo.</strong> Los snapshots son específicos a la versión de Anvil y la dirección del contrato desplegado. Si redespliega el contrato, genere un nuevo snapshot.
      </p>
    </Card>
  )
}
