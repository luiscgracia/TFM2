import { useState } from 'react'
import { useConnect, useAccount, useDisconnect } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { CONTRACT_ADDRESS } from './blockchain/config'
import { DarkContext, useToast, Toasts, btnPrimary, shortAddr } from './shared'
import { ActorsTab } from './panels/ActorsPanel'
import { ShippingPanel, ShipmentsTable } from './panels/ShipmentsPanel'
import { OperationsPanel } from './panels/OperationsPanel'
import { TraceabilityPanel } from './panels/TraceabilityPanel'

// ---------------------------------------------------------------------------
// Tab types
// ---------------------------------------------------------------------------
type TabId = 'actores' | 'envios' | 'operaciones' | 'trazabilidad'

const TABS: { id: TabId; label: string; icon: string }[] = [
  { id: 'actores',      label: 'Actores',       icon: '👥' },
  { id: 'envios',       label: 'Envíos',        icon: '📦' },
  { id: 'operaciones',  label: 'Operaciones',   icon: '⚙️' },
  { id: 'trazabilidad', label: 'Trazabilidad',  icon: '🔍' },
]

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------
export default function App() {
  const { connect, connectors } = useConnect()
  const { address, isConnected } = useAccount()
  const { disconnect } = useDisconnect()
  const { toasts, push } = useToast()
  const queryClient = useQueryClient()
  const [dark, setDark] = useState(true)
  const [activeTab, setActiveTab] = useState<TabId>('actores')

  const connectWallet = () => {
    const c = connectors.find(c => c.id === 'injected') ?? connectors[0]
    connect({ connector: c })
  }

  const handleDisconnect = () => {
    disconnect()
    queryClient.clear()
  }

  const GREEN_HEADER = '#166534'

  return (
    <DarkContext.Provider value={{ dark, toggle: () => setDark(d => !d) }}>
      <div style={{
        minHeight: '100vh',
        backgroundColor: dark ? '#0f172a' : '#f8fafc',
        color: dark ? '#f1f5f9' : '#1e293b',
        fontFamily: 'Inter, system-ui, sans-serif',
        fontSize: '15px',
        backgroundImage: 'url(/fondo.png)',
        backgroundSize: 'cover',
        backgroundPosition: 'center',
        backgroundAttachment: 'fixed',
        backgroundBlendMode: 'overlay',
      }}>
        {/* Capa de opacidad sobre la imagen de fondo */}
        <div style={{
          position: 'fixed',
          inset: 0,
          backgroundImage: 'url(/fondo.png)',
          backgroundSize: 'cover',
          backgroundPosition: 'center',
          backgroundAttachment: 'fixed',
          opacity: 0.04,
          zIndex: 0,
          pointerEvents: 'none',
        }} />
        <div style={{ position: 'relative', zIndex: 1 }}>

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
                      CONECTAR METAMASK
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
                      DESCONECTAR METAMASK
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
              {activeTab === 'actores'      && <ActorsTab push={push} />}
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
        </div> {/* fin div position:relative zIndex:1 */}
      </div>
    </DarkContext.Provider>
  )
}
