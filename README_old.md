# LogisticsTracking — Contrato Inteligente v4

Sistema de trazabilidad logística on-chain desarrollado en Solidity. Permite registrar el ciclo de vida completo de un envío: creación, checkpoints de posición, cambios de estado, incidencias, cadena de frío y confirmación de entrega.

---

## Índice

- [Descripción](#descripción)
- [Arquitectura](#arquitectura)
- [Roles de actores](#roles-de-actores)
- [Ciclo de vida de un envío](#ciclo-de-vida-de-un-envío)
- [Funciones principales](#funciones-principales)
- [Eventos](#eventos)
- [Errores personalizados](#errores-personalizados)
- [Cadena de frío](#cadena-de-frío)
- [Seguridad y auditoría v4](#seguridad-y-auditoría-v4)
- [Optimizaciones de gas](#optimizaciones-de-gas)
- [Constantes](#constantes)
- [Despliegue y tests](#despliegue-y-tests)

---

## Descripción

`LogisticsTracking` es un contrato inteligente que actúa como registro inmutable de trazabilidad logística. Cada envío tiene un identificador único, un conjunto de checkpoints georreferenciados, incidencias reportadas y validación automática de cadena de frío.

El contrato está diseñado para ser desplegado en cualquier red EVM compatible. La versión 4 incorpora correcciones de seguridad resultado de una auditoría formal.

---

## Arquitectura

```
Admin
 └── Registra actores (Sender, Carrier, Hub, Recipient, Inspector)

Sender
 └── Crea envíos → createShipment()
 └── Cancela envíos → cancelShipment()

Carrier / Hub
 └── Actualiza estado → updateShipmentStatus()
 └── Registra checkpoints → recordCheckpoint()
 └── Reporta incidencias → reportIncident()

Recipient
 └── Confirma entrega → confirmDelivery()

Admin
 └── Resuelve incidencias → resolveIncident()
```

---

## Roles de actores

| Rol | Valor enum | Descripción |
|-----|-----------|-------------|
| `None` | 0 | Sin rol asignado |
| `Sender` | 1 | Remitente. Crea y cancela envíos |
| `Carrier` | 2 | Transportista. Mueve el envío y registra checkpoints |
| `Hub` | 3 | Centro logístico. Recibe y despacha envíos |
| `Recipient` | 4 | Destinatario. Confirma la entrega |
| `Inspector` | 5 | Reservado para uso futuro |

> Un actor debe estar **activo** (`isActive = true`) para interactuar con el contrato. El admin puede desactivar y reactivar actores en cualquier momento.

---

## Ciclo de vida de un envío

```
Created
  │
  ├──► InTransit    (Carrier/Hub)
  │       │
  │       ├──► AtHub          (Carrier/Hub)  ◄── cancelable
  │       │       │
  │       │       └──► InTransit / OutForDelivery
  │       │
  │       └──► OutForDelivery (Carrier/Hub)
  │               │
  │               └──► Delivered  (Recipient — confirmDelivery)
  │
  └──► Cancelled   (Sender — solo desde Created o AtHub)
```

### Estados disponibles

| Estado | Valor | Quién lo asigna |
|--------|-------|----------------|
| `Created` | 0 | Automático al crear |
| `InTransit` | 1 | Carrier / Hub |
| `AtHub` | 2 | Carrier / Hub |
| `OutForDelivery` | 3 | Carrier / Hub |
| `Delivered` | 4 | Solo mediante `confirmDelivery()` |
| `Returned` | 5 | Carrier / Hub |
| `Cancelled` | 6 | Sender (desde Created o AtHub) |

> El estado `Delivered` **no puede** ser asignado directamente por `updateShipmentStatus`. Solo se alcanza mediante `confirmDelivery()`.

---

## Funciones principales

### Gestión de admin

```solidity
proposeAdmin(address _newAdmin)
acceptAdmin()
```

Transferencia de admin en dos pasos para evitar pérdida accidental de control.

### Gestión de actores

```solidity
registerActor(string name, ActorRole role, string location, address actorAddress)
deactivateActor(address actorAddress)
reactivateActor(address actorAddress)
getActor(address actorAddress) → Actor
```

Solo el admin puede registrar, desactivar y reactivar actores.

### Gestión de envíos

```solidity
createShipment(address recipient, string product, string origin, string destination, bool requiresColdChain) → uint256
getShipment(uint256 id) → Shipment
updateShipmentStatus(uint256 shipmentId, ShipmentStatus newStatus)
confirmDelivery(uint256 shipmentId)
cancelShipment(uint256 shipmentId)
```

### Checkpoints

```solidity
recordCheckpoint(uint256 shipmentId, string location, CheckpointType checkpointType, string notes, int256 temperature) → uint256
getCheckpoint(uint256 checkpointId) → Checkpoint
getShipmentCheckpoints(uint256 id, uint256 offset, uint256 limit) → Checkpoint[]
getAllShipmentCheckpoints(uint256 id) → Checkpoint[]
```

#### Tipos de checkpoint

| Tipo | Valor | Descripción |
|------|-------|-------------|
| `Pickup` | 0 | Recogida en origen |
| `Hub` | 1 | Paso por centro logístico |
| `Transit` | 2 | En tránsito |
| `Delivery` | 3 | En proceso de entrega |
| `Other` | 4 | Otro tipo de registro |

### Incidencias

```solidity
reportIncident(uint256 shipmentId, IncidentType type, string description) → uint256
resolveIncident(uint256 incidentId)
getIncident(uint256 incidentId) → Incident
getShipmentIncidents(uint256 shipmentId, uint256 offset, uint256 limit) → Incident[]
getAllShipmentIncidents(uint256 shipmentId) → Incident[]
isIncidentResolved(uint256 incidentId) → bool
```

#### Tipos de incidencia

| Tipo | Valor | Descripción |
|------|-------|-------------|
| `Delay` | 0 | Retraso en la entrega |
| `Damage` | 1 | Daño en la mercancía |
| `Lost` | 2 | Paquete perdido |
| `TempViolation` | 3 | Violación de temperatura (cadena de frío) — **generado automáticamente** |
| `Unauthorized` | 4 | Acceso o manipulación no autorizada |

### Consultas auxiliares

```solidity
verifyTemperatureCompliance(uint256 shipmentId) → bool
getActorShipments(address actor) → uint256[]
nextShipmentId() → uint256
nextCheckpointId() → uint256
nextIncidentId() → uint256
```

---

## Eventos

| Evento | Cuándo se emite |
|--------|----------------|
| `ShipmentCreated(shipmentId, sender, recipient, product)` | Al crear un envío |
| `ShipmentStatusChanged(shipmentId, newStatus)` | Al cambiar estado o cancelar |
| `CheckpointRecorded(checkpointId, shipmentId, checkpointType, actor)` | Al registrar checkpoint |
| `DeliveryConfirmed(shipmentId, recipient, timestamp)` | Al confirmar entrega |
| `IncidentReported(incidentId, shipmentId, incidentType)` | Al reportar incidencia |
| `IncidentResolved(incidentId)` | Al resolver incidencia |
| `ActorRegistered(actorAddress, name, role)` | Al registrar actor |
| `ActorStatusChanged(actorAddress, isActive)` | Al activar/desactivar actor |
| `AdminTransferProposed(proposedAdmin)` | Al proponer nuevo admin |
| `AdminTransferAccepted(newAdmin)` | Al aceptar transferencia de admin |

---

## Errores personalizados

| Error | Causa |
|-------|-------|
| `OnlyAdmin` | Función restringida al admin |
| `NotPendingAdmin` | Solo el pending admin puede aceptar |
| `ActorInactive` | El actor no está activo |
| `ActorDoesNotExist` | La dirección no tiene actor registrado |
| `ActorNotAssignedToShipment` | El actor no está asignado a este envío |
| `AlreadyRegisteredAndActive` | El actor ya está registrado y activo |
| `InvalidAddress` | Dirección cero no permitida |
| `InvalidRole` | Rol `None` no permitido al registrar |
| `ShipmentNotFound(id)` | El ID de envío no existe |
| `CheckpointNotFound(id)` | El ID de checkpoint no existe |
| `IncidentNotFound(id)` | El ID de incidencia no existe |
| `OnlySendersCanCreate` | Solo actores con rol Sender pueden crear envíos |
| `OnlyCarrierOrHub` | Solo Carrier o Hub pueden cambiar estado |
| `OnlyRecipientCanConfirm` | Solo el destinatario registrado puede confirmar |
| `OnlySenderCanCancel` | Solo el remitente puede cancelar |
| `AlreadyDelivered` | El envío ya fue entregado |
| `AlreadyClosedShipment` | El envío está en estado terminal |
| `CannotCancelAfterTransit` | No se puede cancelar desde InTransit u OutForDelivery |
| `CannotSetDeliveredDirectly` | No se puede asignar Delivered con updateShipmentStatus |
| `MaxCheckpointsReached` | Se alcanzó el límite de 200 checkpoints por envío |
| `MaxIncidentsReached` | Se alcanzó el límite de 50 incidencias por envío |

---

## Cadena de frío

Los envíos marcados con `requiresColdChain = true` requieren que la temperatura de cada checkpoint esté entre **2.0 °C y 8.0 °C** (almacenada como `int256` multiplicada por 10, es decir entre 20 y 80).

Si un checkpoint registra una temperatura fuera de rango, el contrato genera automáticamente una incidencia de tipo `TempViolation`.

Para omitir la lectura de temperatura en un checkpoint, se pasa el valor sentinel `TEMPERATURE_NOT_SET = type(int256).min`. Ese checkpoint no es validado.

```solidity
// Ejemplo: registrar sin lectura de temperatura
recordCheckpoint(shipmentId, "Hub Central", CheckpointType.Hub, "Sin sensor", TEMPERATURE_NOT_SET);

// Ejemplo: registrar temperatura de 4.5 °C
recordCheckpoint(shipmentId, "Camión frigorífico", CheckpointType.Transit, "OK", 45);
```

---

## Seguridad y auditoría v4

### Críticos resueltos

**[C-1] Checks-Effects-Interactions** — `recordCheckpoint` y `confirmDelivery` aplican todos los cambios de estado antes de emitir eventos, previniendo ataques de reentrancia.

**[C-2] Control de asignación de actores** — `recordCheckpoint` y `reportIncident` verifican que el actor esté asignado al envío mediante `_actorHasShipment`. Un actor se asigna al envío al crearlo (`createShipment`) o al actualizar su estado (`updateShipmentStatus`).

### Advertencias resueltas

**[W-1] Cancelación mejorada** — Solo se puede cancelar desde `Created` o `AtHub`. Los estados terminales devuelven `AlreadyClosedShipment`; los estados en tránsito devuelven `CannotCancelAfterTransit`.

**[W-2] Modifier shipmentExists en paginación** — `getShipmentCheckpoints` ahora verifica que el envío exista antes de devolver resultados.

**[W-3] Sentinel de temperatura** — El valor `TEMPERATURE_NOT_SET` excluye el checkpoint de la validación de cadena de frío sin generar falsos positivos.

**[W-4] Guarda de existencia en deactivateActor** — Se verifica que la dirección tenga un actor registrado antes de desactivarlo.

---

## Optimizaciones de gas

| Código | Descripción |
|--------|-------------|
| `[GAS-1]` | `_addActorShipment` en O(1) con mapping de presencia |
| `[GAS-2]` | Storage pointer cacheado en `recordCheckpoint` |
| `[GAS-3]` | Caché del rol del actor en `updateShipmentStatus` |
| `[GAS-4]` | Paginación en `getShipmentCheckpoints` / `getShipmentIncidents` |
| `[GAS-5]` | Custom errors en lugar de strings en `require` |
| `[GAS-6]` | `CheckpointType` como enum en lugar de string |
| `[GAS-7]` | Contadores privados con getters explícitos |
| `[GAS-8]` | Storage pointer reutilizado en `createShipment` |

---

## Constantes

| Constante | Valor | Descripción |
|-----------|-------|-------------|
| `COLD_CHAIN_TEMP_MIN` | `20` | Temperatura mínima cadena de frío (2.0 °C × 10) |
| `COLD_CHAIN_TEMP_MAX` | `80` | Temperatura máxima cadena de frío (8.0 °C × 10) |
| `TEMPERATURE_NOT_SET` | `type(int256).min` | Sentinel para "sin lectura de temperatura" |
| `MAX_CHECKPOINTS_PER_SHIPMENT` | `200` | Límite de checkpoints por envío |
| `MAX_INCIDENTS_PER_SHIPMENT` | `50` | Límite de incidencias por envío |

---

## Despliegue y tests

### Requisitos

- [Foundry](https://getfoundry.sh/) (forge, anvil)
- Solidity `^0.8.24`

### Compilar

```bash
forge build
```

### Ejecutar tests

```bash
forge test
```

### Desplegar en red local (Anvil)

```bash
anvil
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

### Cobertura de tests

72 tests cubren: gestión de actores, transferencia de admin, creación de envíos, checkpoints, temperatura, confirmación de entrega, incidencias, cancelación, control de acceso y flujos completos end-to-end.

---

## Licencia

MIT — ver `SPDX-License-Identifier: MIT` en el encabezado del contrato.

---

*LogisticsTracking v4 — Luis Carlos Gracia Puentes — TFM2 CodeCrypto — 2026*
