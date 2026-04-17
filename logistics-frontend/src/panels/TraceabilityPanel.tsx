import { useState } from 'react'
import { useReadContract } from 'wagmi'
import { CONTRACT_ADDRESS, ABI } from '../blockchain/config'
import {
  useDark,
  btnPrimary,
  btnSecondary,
  inputStyle,
  labelStyle,
  TH_STYLE,
  TD_STYLE,
  CHECKPOINT_TYPES,
  SHIPMENT_STATUSES,
  INCIDENT_TYPES,
  STATUS_COLORS,
  tempIsUnset,
  tempIsOutOfRange,
  tempDisplay,
  shortAddr,
  fmtTs,
  Card,
  FieldError,
} from '../shared'

import { FONDO_BASE64 } from '../../public/fondoPDF64'

// ---------------------------------------------------------------------------
// loadJsPDF — carga jsPDF y autoTable dinámicamente
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

// ---------------------------------------------------------------------------
// TraceabilityPanel
// ---------------------------------------------------------------------------
export function TraceabilityPanel() {
  const { dark } = useDark()
  const [id, setId] = useState('')
  const [queried, setQueried] = useState(false)
  const [generando, setGenerando] = useState(false)
  const [idError, setIdError] = useState('')

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
      const H = doc.internal.pageSize.getHeight()
      const azul:      [number, number, number] = [5, 150, 105]
      const negro:     [number, number, number] = [0, 0, 0]
      const blanco:    [number, number, number] = [255, 255, 255]
      const grisClaro: [number, number, number] = [245, 247, 250]

      // Fondo con opacidad 12% — se aplica antes de cada sección de contenido
      const drawBg = () => {
        doc.saveGraphicsState()
        ;(doc as any).setGState(new (doc as any).GState({ opacity: 0.12 }))
        doc.addImage(FONDO_BASE64, 'JPEG', 0, 0, W, H)
        doc.restoreGraphicsState()
      }
      drawBg()

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
      doc.text(`Origen: ${shipment.origin}   —   Destino: ${shipment.destination}`, M, y)
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
          head: [['Tipo', 'Descripción', 'Reporter', 'Fecha', 'Estado', 'Notas resolución']],
          body: incidents.map((inc: any) => [INCIDENT_TYPES[Number(inc.incidentType)] ?? '—', inc.description, shortAddr(inc.reporter), fmtTs(inc.timestamp), inc.resolved ? 'Resuelto' : 'Abierto', (inc.resolved && inc.resolutionNote) ? inc.resolutionNote : '—']),
          headStyles: { fillColor: azul, textColor: blanco, fontStyle: 'bold', fontSize: 8, lineWidth: 0.5, lineColor: negro },
          bodyStyles: { fontSize: 8, textColor: negro, lineWidth: 0.5, lineColor: negro },
          alternateRowStyles: { fillColor: grisClaro },
          columnStyles: { 0: { cellWidth: 28 }, 1: { cellWidth: 60 }, 2: { cellWidth: 28 }, 3: { cellWidth: 30 }, 4: { cellWidth: 18 }, 5: { cellWidth: 'auto' } },
        })
      }

      const totalPages = (doc.internal as any).getNumberOfPages()
      for (let p = 1; p <= totalPages; p++) {
        doc.setPage(p)
        // Re-draw background on every page (page 1 already has it, extra pages need it)
        if (p > 1) drawBg()
        doc.setFontSize(7); doc.setTextColor(150, 150, 150); doc.setFont('helvetica', 'normal')
        doc.text(`Contrato: ${CONTRACT_ADDRESS}`, M, doc.internal.pageSize.getHeight() - M + 3)
        doc.text(`Página ${p} de ${totalPages}`, W - M, doc.internal.pageSize.getHeight() - M + 3, { align: 'right' })
      }
      doc.save(`Envio_#${id}-(trace).pdf`)
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
            <span className="text-xs text-slate-400 font-semibold uppercase">Envío #{String(shipment.id)} - </span>
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
                  {['Tipo', 'Descripción', 'Reporter', 'Fecha', 'Estado', 'Notas resolución'].map(h => (
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
                    <td style={{ ...TD_STYLE, minWidth: '160px', whiteSpace: 'normal' }}>
                      {inc.resolved && inc.resolutionNote
                        ? <span className="text-xs text-emerald-700 italic">📋 {inc.resolutionNote}</span>
                        : <span className="text-xs text-slate-300">—</span>
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
