# 📦 LogisticsTracking — On-Chain Logistics Traceability System

![Solidity](https://img.shields.io/badge/Solidity-^0.8.x-blue)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![Tests](https://img.shields.io/badge/Tests-Passing-brightgreen)
![Coverage](https://img.shields.io/badge/Coverage-High-yellow)
![Status](https://img.shields.io/badge/Status-Production--Ready-success)

Sistema descentralizado de trazabilidad logística basado en smart contracts que garantiza transparencia, inmutabilidad y auditabilidad en toda la cadena de suministro.

---

## 📌 Descripción

LogisticsTracking permite registrar y seguir envíos en blockchain:

- 📦 Creación de envíos
- 🚚 Seguimiento en tiempo real (on-chain)
- 🌡️ Validación de cadena de frío
- ⚠️ Gestión de incidencias
- ✅ Confirmación de entrega

---

## 🏗️ Arquitectura

```mermaid
flowchart LR
    A[Sender] -->|Create Shipment| SC[Smart Contract]
    SC --> C[Carrier]
    SC --> H[Hub]
    SC --> I[Inspector]
    SC --> R[Recipient]
    SC --> ADM[Admin]
```

---

## 🔄 Flujo

```mermaid
sequenceDiagram
    participant Sender
    participant Carrier
    participant Contract
    participant Recipient

    Sender->>Contract: createShipment()
    Carrier->>Contract: updateShipmentStatus()
    Carrier->>Contract: recordCheckpoint()
    Recipient->>Contract: confirmDelivery()
```

---

## ⚙️ Instalación

```bash
git clone https://github.com/tuusuario/logistics-tracking.git
cd logistics-tracking
forge install
forge build
```

---

## 🧪 Testing

```bash
forge test -vv
```

---

## 🔁 CI/CD

Incluye GitHub Actions para build, test y coverage.

---

## 📄 Licencia

MIT
