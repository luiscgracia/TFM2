// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {LogisticsTracking} from "../src/LogisticsTracking.sol";

/**
 * @title LogisticsTrackingTest
 * @notice Suite de pruebas Foundry con 15 escenarios de trazabilidad logistica.
 *
 * Escenarios incluidos:
 *  - Envios con cadena de frio y sin ella
 *  - Checkpoints de control en ruta (Hub, Transit, Pickup, Delivery)
 *  - Violaciones de temperatura (automaticas y manuales)
 *  - Incidencias por todos los tipos: Delay, Damage, Lost, TempViolation, Unauthorized
 *  - Todos los envios quedan en estado pendiente (no se llama confirmDelivery)
 *
 * Estructura de actores:
 *  admin     → despliega el contrato
 *  sender1/2 → remitentes (rol Sender)
 *  carrier1/2→ transportistas (rol Carrier)
 *  hub1      → centro de distribucion (rol Hub)
 *  recipient1..5 → destinatarios (rol Recipient)
 *  inspector1    → inspector (rol Inspector)
 */
contract LogisticsTrackingTest15 is Test {

    // -------------------------------------------------------------------------
    // Contrato bajo prueba
    // -------------------------------------------------------------------------
    LogisticsTracking public lt;

    // -------------------------------------------------------------------------
    // Actores
    // -------------------------------------------------------------------------
    address admin     = address(0xA0);
    address sender1   = address(0xA1);
    address sender2   = address(0xA2);
    address carrier1  = address(0xB1);
    address carrier2  = address(0xB2);
    address hub1      = address(0xC1);
    address recipient1 = address(0xD1);
    address recipient2 = address(0xD2);
    address recipient3 = address(0xD3);
    address recipient4 = address(0xD4);
    address recipient5 = address(0xD5);
    address inspector1 = address(0xE1);

    // Temperatura sentinel (sin lectura)
    int256 constant NO_TEMP = type(int256).min;

    // -------------------------------------------------------------------------
    // setUp: deploy + registro de actores
    // -------------------------------------------------------------------------
    function setUp() public {
        vm.startPrank(admin);
        lt = new LogisticsTracking();

        // Registrar remitentes
        lt.registerActor("Farmaceutica BioSalud",  LogisticsTracking.ActorRole.Sender,    "Bogota",     sender1);
        lt.registerActor("Alimentos FrescoNorte",   LogisticsTracking.ActorRole.Sender,    "Medellin",   sender2);

        // Registrar transportistas
        lt.registerActor("TransFria Express",       LogisticsTracking.ActorRole.Carrier,   "Bogota",     carrier1);
        lt.registerActor("Cargo Rapido SAS",        LogisticsTracking.ActorRole.Carrier,   "Cali",       carrier2);

        // Registrar hub
        lt.registerActor("Hub Logistico Central",   LogisticsTracking.ActorRole.Hub,       "Bucaramanga", hub1);

        // Registrar destinatarios
        lt.registerActor("Clinica San Rafael",      LogisticsTracking.ActorRole.Recipient, "Cali",       recipient1);
        lt.registerActor("Supermercado La 14",      LogisticsTracking.ActorRole.Recipient, "Pereira",    recipient2);
        lt.registerActor("Hospital El Tunal",       LogisticsTracking.ActorRole.Recipient, "Bogota",     recipient3);
        lt.registerActor("Restaurante Galeria",     LogisticsTracking.ActorRole.Recipient, "Barranquilla", recipient4);
        lt.registerActor("Drogueria Popular",       LogisticsTracking.ActorRole.Recipient, "Manizales",  recipient5);

        // Registrar inspector
        lt.registerActor("Inspector Sanitario INVIMA", LogisticsTracking.ActorRole.Inspector, "Bogota", inspector1);

        vm.stopPrank();
    }

    // =========================================================================
    // ESCENARIO 1
    // Vacunas en transito - cadena de frio correcta - sin incidencias
    // Estado final: OutForDelivery (pendiente de entrega)
    // =========================================================================
    function test_Escenario01_VacunasCadenaFrioSinIncidencias() public {
        console.log("=== ESCENARIO 1: Vacunas - cadena de frio OK ===");

        // Crear envio con cadena de frio
        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient1,
            "Vacunas COVID-19 (50 dosis)",
            "Bogota",
            "Cali",
            true // requiresColdChain
        );
        console.log("  Envio creado, ID:", shipId);

        // Carrier1 recoge el paquete - temperatura 4.5 °C (45 * 0.1)
        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Bodega BioSalud - Bogota",
            LogisticsTracking.CheckpointType.Pickup,
            "Recogida confirmada. Cadena de frio iniciada.",
            45
        );

        // Actualizar estado a InTransit
        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        // Checkpoint en autopista
        _checkpointAs(carrier1, shipId, "Autopista Bogota-Ibague Km 80",
            LogisticsTracking.CheckpointType.Transit,
            "Temperatura estable.", 42);

        // Arriba al hub
        _checkpointAs(carrier1, shipId, "Hub Bucaramanga",
            LogisticsTracking.CheckpointType.Hub,
            "Transferencia a hub intermedio.", 38);

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.AtHub);

        // Hub procesa y reenvia — asignamos hub1 al envio antes de su primer checkpoint
        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Bucaramanga - Sala Fria",
            LogisticsTracking.CheckpointType.Hub,
            "Verificacion de sellos OK.", 40);

        vm.prank(hub1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        // Checkpoint final antes de entrega
        _checkpointAs(carrier1, shipId, "Distribucion Cali Norte",
            LogisticsTracking.CheckpointType.Transit,
            "En ruta a destino final.", 44);

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.OutForDelivery);

        // Verificar cumplimiento de temperatura
        bool compliant = lt.verifyTemperatureCompliance(shipId);
        assertTrue(compliant, "Cadena de frio debe ser valida");

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(uint(s.status), uint(LogisticsTracking.ShipmentStatus.OutForDelivery));
        assertEq(s.incidentIds.length, 0);
        console.log("  Checkpoints registrados:", s.checkpointIds.length);
        console.log("  Incidencias:", s.incidentIds.length);
        console.log("  Estado: OutForDelivery - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 2
    // Insulina - violacion de temperatura detectada automaticamente
    // Estado final: InTransit (pendiente de entrega)
    // =========================================================================
    function test_Escenario02_InsulinaViolacionTemperatura() public {
        console.log("=== ESCENARIO 2: Insulina - violacion de temperatura ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient3,
            "Insulina NPH 100 UI/mL (200 viales)",
            "Bogota",
            "Bogota Sur",
            true
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Laboratorio BioSalud Bogota",
            LogisticsTracking.CheckpointType.Pickup,
            "Recogida con temperatura inicial correcta.", 50
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        // Temperatura normal
        _checkpointAs(carrier1, shipId, "Av. Boyaca Km 15",
            LogisticsTracking.CheckpointType.Transit, "Ruta normal.", 45);

        // ⚠️ VIOLACIoN: temperatura 12 °C (120) - fuera del rango [20, 80]
        // El contrato crea automaticamente una incidencia TempViolation
        _checkpointAs(carrier1, shipId, "Soacha - Parqueadero forzado",
            LogisticsTracking.CheckpointType.Transit,
            "Falla del sistema de refrigeracion. Temp elevada.", 120);

        // Verificar que se genero la incidencia automatica
        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(s.incidentIds.length, 1);

        LogisticsTracking.Incident memory inc = lt.getIncident(s.incidentIds[0]);
        assertEq(uint(inc.incidentType), uint(LogisticsTracking.IncidentType.TempViolation));
        assertFalse(inc.resolved, "Incidencia debe estar pendiente");

        bool compliant = lt.verifyTemperatureCompliance(shipId);
        assertFalse(compliant, "Cadena de frio debe estar violada");

        console.log("  Incidencia TempViolation generada automaticamente, ID:", inc.id);
        console.log("  Estado: InTransit - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 3
    // Carne fresca - multiples violaciones de temperatura + incidencia de daño
    // Estado final: AtHub (pendiente de entrega)
    // =========================================================================
    function test_Escenario03_CarneFrescaMultiplesViolaciones() public {
        console.log("=== ESCENARIO 3: Carne - multiples violaciones + Damage ===");

        vm.prank(sender2);
        uint256 shipId = lt.createShipment(
            recipient4,
            "Carne de res refrigerada (500 kg)",
            "Medellin",
            "Barranquilla",
            true
        );

        _assignActorAndCheckpoint(
            carrier2, shipId,
            "Planta FrescoNorte - Medellin",
            LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta al inicio.", 25
        );

        vm.prank(carrier2);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        // Primera violacion: demasiado frio (por debajo de 2 °C)
        _checkpointAs(carrier2, shipId, "Puerto Berrio",
            LogisticsTracking.CheckpointType.Transit,
            "Congelador en maxima potencia. Temperatura muy baja.", 5);

        // Segunda violacion: demasiado caliente
        _checkpointAs(carrier2, shipId, "Caucasia",
            LogisticsTracking.CheckpointType.Transit,
            "Unidad de refrigeracion con falla intermitente.", 95);

        // Checkpoint normal
        _checkpointAs(carrier2, shipId, "Planeta Rica",
            LogisticsTracking.CheckpointType.Transit, "Temperatura recuperada.", 35);

        // Hub recibe con daño visible — asignamos hub1 al envio antes de su primer checkpoint
        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Barranquilla",
            LogisticsTracking.CheckpointType.Hub,
            "Se observan empaques deteriorados.", NO_TEMP);

        vm.prank(hub1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.AtHub);

        // Incidencia manual por daño fisico
        vm.prank(carrier2);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Damage,
            "Empaques rotos detectados al abrir contenedor en hub Barranquilla");

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        // 2 violaciones automaticas + 1 daño manual
        assertEq(s.incidentIds.length, 3);

        console.log("  Total incidencias:", s.incidentIds.length, "(2 TempViolation + 1 Damage)");
        console.log("  Estado: AtHub - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 4
    // Electronicos - retraso en hub + incidencia de demora
    // Estado final: AtHub (pendiente de entrega)
    // =========================================================================
    function test_Escenario04_ElectronicosRetrasoEnHub() public {
        console.log("=== ESCENARIO 4: Electronicos - Delay en hub ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient2,
            "Tablets educativas (100 unidades)",
            "Bogota",
            "Pereira",
            false // sin cadena de frio
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Bodega Tecnologia BioSalud",
            LogisticsTracking.CheckpointType.Pickup,
            "Envio recogido sin novedad.", NO_TEMP
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier1, shipId, "Manizales - Peaje",
            LogisticsTracking.CheckpointType.Transit,
            "Sin novedades. Trafico fluido.", NO_TEMP);

        // Hub Armenia — asignamos hub1 al envio antes de su primer checkpoint
        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Armenia",
            LogisticsTracking.CheckpointType.Hub,
            "Paquete retenido por inspeccion aduanera.", NO_TEMP);

        vm.prank(hub1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.AtHub);

        // Simular paso del tiempo (48 horas)
        vm.warp(block.timestamp + 48 hours);

        // Incidencia por retraso
        vm.prank(hub1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Delay,
            "Retencion aduanera por falta de documentacion de importacion. Demora +48h.");

        _checkpointAs(hub1, shipId, "Hub Armenia - Sala de espera",
            LogisticsTracking.CheckpointType.Other,
            "Documentacion en tramite. Sin liberacion aun.", NO_TEMP);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(uint(s.status), uint(LogisticsTracking.ShipmentStatus.AtHub));
        assertEq(s.incidentIds.length, 1);

        console.log("  Incidencia Delay registrada.");
        console.log("  Estado: AtHub - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 5
    // Reactivos de laboratorio - paquete perdido en transito
    // Estado final: InTransit (pendiente de entrega)
    // =========================================================================
    function test_Escenario05_ReactivosPaquetePerdido() public {
        console.log("=== ESCENARIO 5: Reactivos - incidencia Lost ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient3,
            "Reactivos PCR (kit x500)",
            "Bogota",
            "Bogota",
            true
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Deposito Central Bogota",
            LogisticsTracking.CheckpointType.Pickup,
            "Recogida confirmada.", 30
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier1, shipId, "Calle 80 - Bodega temporal",
            LogisticsTracking.CheckpointType.Transit,
            "Cargamento documentado correctamente.", 28);

        // Despues de una parada, no se encuentra el paquete
        vm.warp(block.timestamp + 6 hours);

        vm.prank(carrier1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Lost,
            "Caja de reactivos no localizada al reiniciar ruta desde bodega temporal Calle 80.");

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(uint(incType(lt, s.incidentIds[0])),
            uint(LogisticsTracking.IncidentType.Lost));
        assertFalse(lt.getIncident(s.incidentIds[0]).resolved);

        console.log("  Incidencia Lost registrada, pendiente de resolucion.");
        console.log("  Estado: InTransit - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 6
    // Medicamentos - acceso no autorizado detectado por inspector
    // Estado final: InTransit (pendiente de entrega)
    // =========================================================================
    function test_Escenario06_MedicamentosAccesoNoAutorizado() public {
        console.log("=== ESCENARIO 6: Medicamentos - incidencia Unauthorized ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient5,
            "Antibioticos amoxicilina 500mg (1000 cajas)",
            "Bogota",
            "Manizales",
            false
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Planta Bogota Norte",
            LogisticsTracking.CheckpointType.Pickup,
            "Cargamento sellado y documentado.", NO_TEMP
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier1, shipId, "Autopista al Llano - Km 30",
            LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", NO_TEMP);

        // Asignar inspector al envio (el admin lo asigna via updateShipmentStatus no aplica -
        // el inspector se agrega al envio registrandole un checkpoint previo desde admin)
        // Usamos el sender1 para asignarle primero el envio al inspector1 (via admin mock)
        _addInspectorToShipment(inspector1, shipId);

        // Inspector reporta acceso no autorizado
        vm.prank(inspector1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Unauthorized,
            "Sello de seguridad violado en caja #47. Posible intervencion no autorizada durante parada.");

        _checkpointAs(inspector1, shipId, "Puesto de control INVIMA - Girardot",
            LogisticsTracking.CheckpointType.Other,
            "Inspeccion sanitaria de emergencia iniciada.", NO_TEMP);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(uint(incType(lt, s.incidentIds[0])),
            uint(LogisticsTracking.IncidentType.Unauthorized));

        console.log("  Incidencia Unauthorized registrada por inspector INVIMA.");
        console.log("  Estado: InTransit - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 7
    // Frutas tropicales - cadena de frio con multiples checkpoints en hub
    // Estado final: OutForDelivery (pendiente de entrega)
    // =========================================================================
    function test_Escenario07_FrutasMultiplesCheckpointsHub() public {
        console.log("=== ESCENARIO 7: Frutas - checkpoints de hub detallados ===");

        vm.prank(sender2);
        uint256 shipId = lt.createShipment(
            recipient2,
            "Fresas y arandanos frescos (300 kg)",
            "Medellin",
            "Pereira",
            true
        );

        _assignActorAndCheckpoint(
            carrier2, shipId,
            "Finca FrescoNorte - Rionegro",
            LogisticsTracking.CheckpointType.Pickup,
            "Fruta recogida. Temperatura inicial.", 60
        );

        vm.prank(carrier2);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier2, shipId, "Tunel de Occidente",
            LogisticsTracking.CheckpointType.Transit, "Sin novedad.", 58);

        _checkpointAs(carrier2, shipId, "Santa Fe de Antioquia",
            LogisticsTracking.CheckpointType.Transit, "Temperatura estable.", 55);

        // Hub con varios sub-checkpoints
        vm.prank(carrier2);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.AtHub);

        // Hub con varios sub-checkpoints — asignamos hub1 antes del primero
        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Pereira - Recepcion",
            LogisticsTracking.CheckpointType.Hub, "Recepcion registrada.", 57);

        _checkpointAs(hub1, shipId, "Hub Pereira - Sala clasificacion",
            LogisticsTracking.CheckpointType.Hub, "Clasificacion por destino.", 55);

        _checkpointAs(hub1, shipId, "Hub Pereira - Camara fria",
            LogisticsTracking.CheckpointType.Hub, "Almacenamiento temporal OK.", 40);

        _checkpointAs(hub1, shipId, "Hub Pereira - Despacho",
            LogisticsTracking.CheckpointType.Hub, "Reasignado a reparto local.", 52);

        vm.prank(hub1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.OutForDelivery);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertTrue(lt.verifyTemperatureCompliance(shipId));
        assertEq(s.incidentIds.length, 0);
        assertEq(uint(s.status), uint(LogisticsTracking.ShipmentStatus.OutForDelivery));

        console.log("  Checkpoints totales:", s.checkpointIds.length);
        console.log("  Temperatura en cumplimiento: SI");
        console.log("  Estado: OutForDelivery - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 8
    // Plasma sanguineo - violacion de temperatura por frio extremo + retraso
    // Estado final: AtHub (pendiente de entrega)
    // =========================================================================
    function test_Escenario08_PlasmaFrioExtremo() public {
        console.log("=== ESCENARIO 8: Plasma - frio extremo + Delay ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient1,
            "Plasma sanguineo grupo O+ (50 bolsas)",
            "Bogota",
            "Cali",
            true
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Banco de Sangre - Bogota",
            LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta.", 35
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        // ⚠️ VIOLACIoN: temperatura de 0 °C = (valor 0 en contrato, pero TEMPERATURE_NOT_SET != 0)
        // Temperatura -5 °C = -50 - por debajo de COLD_CHAIN_TEMP_MIN (20)
        _checkpointAs(carrier1, shipId, "Espinal - Parada de emergencia",
            LogisticsTracking.CheckpointType.Transit,
            "Sensor reporta temperatura negativa. Posible falla del equipo.", -50);

        // Demora por reparacion del equipo
        vm.warp(block.timestamp + 5 hours);

        vm.prank(carrier1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Delay,
            "Camion refrigerado averiado en Espinal. Espera de vehiculo de reemplazo: 5 horas.");

        _checkpointAs(carrier1, shipId, "Espinal - Trasvase a vehiculo sustituto",
            LogisticsTracking.CheckpointType.Other, "Temperatura recuperada en nuevo vehiculo.", 30);

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.AtHub);

        // Hub Cali — asignamos hub1 al envio antes de su primer checkpoint
        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Cali - Cuarentena fria",
            LogisticsTracking.CheckpointType.Hub,
            "Material retenido para evaluacion de integridad.", 28);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        // 1 TempViolation automatica + 1 Delay manual
        assertEq(s.incidentIds.length, 2);
        assertFalse(lt.verifyTemperatureCompliance(shipId));

        console.log("  Incidencias:", s.incidentIds.length, "(TempViolation + Delay)");
        console.log("  Estado: AtHub - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 9
    // Ropa - sin cadena de frio, retraso + daño en transito
    // Estado final: InTransit (pendiente de entrega)
    // =========================================================================
    function test_Escenario09_RopaRetrasoDanio() public {
        console.log("=== ESCENARIO 9: Ropa - Delay + Damage ===");

        vm.prank(sender2);
        uint256 shipId = lt.createShipment(
            recipient4,
            "Uniformes escolares (200 conjuntos)",
            "Medellin",
            "Barranquilla",
            false
        );

        _assignActorAndCheckpoint(
            carrier2, shipId,
            "Centro distribucion Medellin",
            LogisticsTracking.CheckpointType.Pickup,
            "Paquetes en buen estado.", NO_TEMP
        );

        vm.prank(carrier2);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier2, shipId, "Magangue",
            LogisticsTracking.CheckpointType.Transit, "Ruta normal.", NO_TEMP);

        // Accidente vial - daño en mercancia
        vm.prank(carrier2);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Damage,
            "Choque leve en via Magangue-Barranquilla. Cajas del compartimiento trasero afectadas.");

        // Retraso por tramites del accidente
        vm.warp(block.timestamp + 3 hours);

        vm.prank(carrier2);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Delay,
            "Procedimiento policial por accidente. Demora estimada 3 horas adicionales.");

        _checkpointAs(carrier2, shipId, "Barranquilla - Norte",
            LogisticsTracking.CheckpointType.Transit,
            unicode"Continuando ruta. Daños documentados.", NO_TEMP);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(s.incidentIds.length, 2);
        assertEq(uint(s.status), uint(LogisticsTracking.ShipmentStatus.InTransit));

        console.log("  Incidencias: Damage + Delay");
        console.log("  Estado: InTransit - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 10
    // Vacunas pediatricas - violacion alta de temperatura + acceso no autorizado
    // Estado final: OutForDelivery (pendiente de entrega)
    // =========================================================================
    function test_Escenario10_VacunasPediatricasMultiIncidencia() public {
        console.log("=== ESCENARIO 10: Vacunas pediatricas - TempViolation + Unauthorized ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient3,
            "Vacunas pentavalentes pediatricas (300 dosis)",
            "Bogota",
            "Bogota",
            true
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "ICBF Deposito Norte",
            LogisticsTracking.CheckpointType.Pickup,
            "Sellado y temperatura verificada.", 45
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        // ⚠️ Temperatura muy alta: 25 °C = 250
        _checkpointAs(carrier1, shipId, "Zona Industrial Bogota",
            LogisticsTracking.CheckpointType.Transit,
            "Vehiculo expuesto al sol durante carga cruzada. Temperatura elevada.", 250);

        // Inspector detecta sello violado
        _addInspectorToShipment(inspector1, shipId);

        vm.prank(inspector1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Unauthorized,
            "Precinto del lote 12 retirado sin autorizacion durante trasbordo en zona industrial.");

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.OutForDelivery);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(s.incidentIds.length, 2);
        assertFalse(lt.verifyTemperatureCompliance(shipId));

        console.log("  Incidencias: TempViolation (auto) + Unauthorized (manual)");
        console.log("  Estado: OutForDelivery - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 11
    // Dispositivos medicos - envio con multiples checkpoints de transito OK
    // Estado final: OutForDelivery (pendiente de entrega)
    // =========================================================================
    function test_Escenario11_DispositivosMedicosRutaLarga() public {
        console.log("=== ESCENARIO 11: Dispositivos medicos - ruta larga multi-checkpoint ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient1,
            "Marcapasos cardiacos (10 unidades)",
            "Bogota",
            "Cali",
            false
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Importadora Medica Bogota",
            LogisticsTracking.CheckpointType.Pickup,
            "Dispositivos verificados y embalados.", NO_TEMP
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        string[5] memory lugares = [
            "Soacha", "Fusagasuga", "Girardot", "Espinal", "Ibague"
        ];

        for (uint i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 1 hours);
            _checkpointAs(carrier1, shipId, lugares[i],
                LogisticsTracking.CheckpointType.Transit,
                "Control de ruta sin novedad.", NO_TEMP);
        }

        // Hub Armenia — asignamos hub1 al envio antes de su primer checkpoint
        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Armenia",
            LogisticsTracking.CheckpointType.Hub, "Transito por hub.", NO_TEMP);

        vm.prank(hub1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier1, shipId, "Buga", LogisticsTracking.CheckpointType.Transit,
            "ultimas horas de viaje.", NO_TEMP);

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.OutForDelivery);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(s.incidentIds.length, 0);
        assertEq(s.checkpointIds.length, 8);
        assertEq(uint(s.status), uint(LogisticsTracking.ShipmentStatus.OutForDelivery));

        console.log("  Checkpoints totales:", s.checkpointIds.length);
        console.log("  Sin incidencias.");
        console.log("  Estado: OutForDelivery - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 12
    // Bebidas gaseosas - sin cadena de frio, perdida parcial + retraso
    // Estado final: InTransit (pendiente de entrega)
    // =========================================================================
    function test_Escenario12_BebidasPerdidaParcial() public {
        console.log("=== ESCENARIO 12: Bebidas - Lost + Delay ===");

        vm.prank(sender2);
        uint256 shipId = lt.createShipment(
            recipient4,
            "Gaseosas Postobon surtidas (600 unidades)",
            "Medellin",
            "Barranquilla",
            false
        );

        _assignActorAndCheckpoint(
            carrier2, shipId,
            "Planta Postobon Medellin",
            LogisticsTracking.CheckpointType.Pickup,
            "Carga completa verificada: 600 unidades.", NO_TEMP
        );

        vm.prank(carrier2);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier2, shipId, "Valledupar - Parque industrial",
            LogisticsTracking.CheckpointType.Transit, "Sin novedad.", NO_TEMP);

        // Perdida de un pale en el transbordo
        vm.prank(carrier2);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Lost,
            "Pale #3 (150 unidades) no localizado tras transbordo nocturno en Valledupar.");

        vm.warp(block.timestamp + 8 hours);

        vm.prank(carrier2);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Delay,
            "Busqueda del pale perdido genera retraso de 8 horas en la ruta.");

        _checkpointAs(carrier2, shipId, "Barranquilla - Av. Circunvalar",
            LogisticsTracking.CheckpointType.Transit,
            "Continua ruta con carga parcial.", NO_TEMP);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(s.incidentIds.length, 2);

        console.log("  Incidencias: Lost + Delay");
        console.log("  Estado: InTransit - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 13
    // Material quirurgico - violacion de temperatura leve + daño en embalaje
    // Estado final: AtHub (pendiente de entrega)
    // =========================================================================
    function test_Escenario13_MaterialQuirurgicoViolacionLeve() public {
        console.log("=== ESCENARIO 13: Material quirurgico - TempViolation leve + Damage ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient5,
            "Suturas y material quirurgico esteril (50 cajas)",
            "Bogota",
            "Manizales",
            true
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Proveedor Medico Bogota",
            LogisticsTracking.CheckpointType.Pickup,
            "Material esteril sellado y verificado.", 30
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier1, shipId, "Honda",
            LogisticsTracking.CheckpointType.Transit, "Temperatura normal.", 35);

        // ⚠️ Temperatura 9 °C = 90 (ligeramente por encima de 8 °C = 80)
        _checkpointAs(carrier1, shipId, "La Dorada - Carga compartida",
            LogisticsTracking.CheckpointType.Transit,
            "Temperatura subio levemente por apertura de compuerta durante carga cruzada.", 90);

        // Daño en embalaje externo por humedad
        vm.prank(carrier1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Damage,
            unicode"Humedad exterior daño el embalaje de carton de 12 cajas. Contenido intacto pero empaque comprometido.");

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.AtHub);

        // Hub Manizales — asignamos hub1 al envio antes de su primer checkpoint
        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Manizales - Recepcion",
            LogisticsTracking.CheckpointType.Hub, "Revision de empaques en curso.", 28);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(s.incidentIds.length, 2);
        assertFalse(lt.verifyTemperatureCompliance(shipId));

        console.log("  Incidencias: TempViolation (auto) + Damage (manual)");
        console.log("  Estado: AtHub - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 14
    // Hormonas de crecimiento - ruta correcta sin incidencias, inspector verifica
    // Estado final: OutForDelivery (pendiente de entrega)
    // =========================================================================
    function test_Escenario14_HormonasInspectorVerifica() public {
        console.log("=== ESCENARIO 14: Hormonas - inspector valida - sin incidencias ===");

        vm.prank(sender1);
        uint256 shipId = lt.createShipment(
            recipient3,
            "Hormona de crecimiento somatropina (20 viales)",
            "Bogota",
            "Bogota Norte",
            true
        );

        _assignActorAndCheckpoint(
            carrier1, shipId,
            "Laboratorio Hormonal - Bogota",
            LogisticsTracking.CheckpointType.Pickup,
            "Temperatura verificada al inicio.", 45
        );

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        _checkpointAs(carrier1, shipId, "Autopista Norte Km 15",
            LogisticsTracking.CheckpointType.Transit, "Sin novedad.", 42);

        _checkpointAs(carrier1, shipId, "Centro de acopio Norte",
            LogisticsTracking.CheckpointType.Transit, "Temperatura estable.", 40);

        // Inspector verifica la cadena de frio en campo
        _addInspectorToShipment(inspector1, shipId);

        _checkpointAs(inspector1, shipId, "Puesto de inspeccion - Usaquen",
            LogisticsTracking.CheckpointType.Other,
            unicode"Inspeccion INVIMA: Temperatura 4.0°C, empaques integros, cadena de frio cumplida.", 40);

        vm.prank(carrier1);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.OutForDelivery);

        assertTrue(lt.verifyTemperatureCompliance(shipId));

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);
        assertEq(s.incidentIds.length, 0);

        console.log("  Inspector INVIMA valido la cadena de frio.");
        console.log("  Estado: OutForDelivery - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // ESCENARIO 15
    // Alimentos congelados - cuatro violaciones de temperatura + daño + demora
    // Estado final: AtHub (pendiente de entrega)
    // =========================================================================
    function test_Escenario15_AlimentosCongeladosCasosCriticos() public {
        console.log("=== ESCENARIO 15: Alimentos congelados - caso critico multi-incidencia ===");

        vm.prank(sender2);
        uint256 shipId = lt.createShipment(
            recipient2,
            "Helados artesanales premium (800 unidades)",
            "Medellin",
            "Pereira",
            true
        );

        _assignActorAndCheckpoint(
            carrier2, shipId,
            "Heladeria Premium - Planta Medellin",
            LogisticsTracking.CheckpointType.Pickup,
            unicode"Temperatura correcta -18°C externa. Cadena de frio activa.", 20
        );

        vm.prank(carrier2);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);

        // Checkpoint normal
        _checkpointAs(carrier2, shipId, "Caldas - Sur de Medellin",
            LogisticsTracking.CheckpointType.Transit, "Sin novedad.", 22);

        // ⚠️ Violacion 1: corte de energia temporal - 10 °C = 100
        _checkpointAs(carrier2, shipId, "La Pintada - Estacion de servicio",
            LogisticsTracking.CheckpointType.Transit,
            "Corte de energia 15 min. Temperatura sube.", 100);

        // Checkpoint recuperado
        _checkpointAs(carrier2, shipId, "Supia",
            LogisticsTracking.CheckpointType.Transit, "Temperatura bajando.", 75);

        // ⚠️ Violacion 2: atasco en calor - 15 °C = 150
        _checkpointAs(carrier2, shipId, "Riosucio - Trancon",
            LogisticsTracking.CheckpointType.Transit,
            "Trancon de 2h. Sistema de refrigeracion al limite.", 150);

        // Hub recibe con temperatura fuera de rango — asignamos hub1 antes de su primer checkpoint
        vm.prank(carrier2);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.AtHub);

        _assignActorToShipment(hub1, shipId);
        _checkpointAs(hub1, shipId, "Hub Pereira - Verificacion de llegada",
            LogisticsTracking.CheckpointType.Hub,
            unicode"Temperatura al llegar: 12°C. Cadena de frio comprometida.", 120);

        // Incidencia de daño reportada por hub
        vm.prank(hub1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Damage,
            "Helados derretidos parcialmente. Estimado 40% del lote comprometido.");

        // Incidencia de demora para reevaluacion del lote
        vm.warp(block.timestamp + 24 hours);

        vm.prank(hub1);
        lt.reportIncident(shipId, LogisticsTracking.IncidentType.Delay,
            "Lote retenido 24h por evaluacion de inocuidad alimentaria.");

        // Inspector evalua
        _addInspectorToShipment(inspector1, shipId);

        _checkpointAs(inspector1, shipId, "Hub Pereira - Laboratorio",
            LogisticsTracking.CheckpointType.Other,
            "Muestras tomadas. Resultado pendiente. Envio retenido en hub.", NO_TEMP);

        LogisticsTracking.Shipment memory s = lt.getShipment(shipId);

        // 3 TempViolation automaticas (100, 150, 120) + 1 Damage + 1 Delay = 5 incidencias
        assertEq(s.incidentIds.length, 5);
        assertFalse(lt.verifyTemperatureCompliance(shipId));
        assertEq(uint(s.status), uint(LogisticsTracking.ShipmentStatus.AtHub));

        console.log("  Total incidencias:", s.incidentIds.length,
            "(3 TempViolation auto + 1 Damage + 1 Delay)");
        console.log("  Cadena de frio comprometida: NO cumple");
        console.log("  Estado: AtHub - PENDIENTE DE ENTREGA");
    }

    // =========================================================================
    // HELPERS internos
    // =========================================================================

    /**
     * @dev Asigna el carrier al envio mediante updateShipmentStatus y luego
     *      registra un primer checkpoint (Pickup). Usado solo para el primer actor
     *      de un envio nuevo, ya que createShipment solo registra sender y recipient.
     */
    function _assignActorAndCheckpoint(
        address _actor,
        uint256 _shipId,
        string memory _loc,
        LogisticsTracking.CheckpointType _cpType,
        string memory _notes,
        int256 _temp
    ) internal {
        // El carrier/hub se auto-asigna al actualizar el estado.
        // Usamos InTransit en lugar de Created para que la transición sea válida
        // y _addActorShipment registre al actor antes del primer checkpoint.
        vm.prank(_actor);
        lt.updateShipmentStatus(_shipId, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(_actor);
        lt.recordCheckpoint(_shipId, _loc, _cpType, _notes, _temp);
    }

    /**
     * @dev Asigna un actor Hub/Carrier al envio mediante updateShipmentStatus con el
     *      estado actual. Necesario antes del primer checkpoint de cualquier actor que
     *      no haya sido asignado al envio todavía, ya que recordCheckpoint requiere
     *      que el actor esté en _actorHasShipment [C-2].
     */
    function _assignActorToShipment(address _actor, uint256 _shipId) internal {
        LogisticsTracking.ShipmentStatus current = lt.getShipment(_shipId).status;
        vm.prank(_actor);
        lt.updateShipmentStatus(_shipId, current);
    }

    /**
     * @dev Registra un checkpoint como un actor ya asignado al envio.
     */
    function _checkpointAs(
        address _actor,
        uint256 _shipId,
        string memory _loc,
        LogisticsTracking.CheckpointType _cpType,
        string memory _notes,
        int256 _temp
    ) internal {
        vm.prank(_actor);
        lt.recordCheckpoint(_shipId, _loc, _cpType, _notes, _temp);
    }

    /**
     * @dev Agrega un inspector al envio reutilizando updateShipmentStatus con carrier1.
     *      Como el inspector no puede actualizar estado, lo asignamos via el admin
     *      registrando un checkpoint temporal con carrier1 que no altera el flujo.
     *      En la practica, se requiere una llamada del admin para pre-asignar inspectores;
     *      aqui lo simulamos como lo permite el contrato: quien registra un checkpoint
     *      queda asignado. Usamos un prank de carrier1 para invocar updateShipmentStatus
     *      con el estado actual (no cambia nada) y luego el inspector se registra.
     *
     *      NOTA: El contrato no tiene funcion directa de asignacion de actores a envios
     *      para inspectores. La unica via es que el inspector llame a recordCheckpoint,
     *      pero primero debe estar en _actorHasShipment. Para lograrlo, el admin puede
     *      re-registrar al inspector como Carrier temporal - optamos por la solucion
     *      mas limpia: el admin registra el inspector como actor del envio llamando
     *      updateShipmentStatus desde carrier1 (que ya esta asignado) y luego el
     *      inspector llama recordCheckpoint desde su rol de Inspector ya que
     *      _actorHasShipment se llena cuando updateShipmentStatus lo invoca con _addActorShipment.
     *
     *      Solucion real: agregamos al inspector directamente via el admin en un checkpoint
     *      especial, re-usando carrier1 que llama updateShipmentStatus (lo que internamente
     *      llama _addActorShipment para carrier1) y luego re-registramos al inspector
     *      usando el admin como puente mediante reactivateActor + un trick de estado.
     *
     *      IMPLEMENTACIoN SIMPLIFICADA para el test: el inspector es registrado con rol
     *      Carrier temporalmente para poder registrar su checkpoint, y luego se restaura.
     */
    function _addInspectorToShipment(address _inspector, uint256 _shipId) internal {
        // Paso 1: desactivar inspector y re-registrar temporalmente como Hub
        //         para poder llamar updateShipmentStatus y quedar asignado al envio.
        vm.startPrank(admin);
        lt.deactivateActor(_inspector);
        lt.registerActor("Inspector Sanitario INVIMA",
            LogisticsTracking.ActorRole.Hub, "Bogota", _inspector);
        vm.stopPrank();

        // Paso 2: asignar al envio (updateShipmentStatus llama _addActorShipment)
        LogisticsTracking.ShipmentStatus current = lt.getShipment(_shipId).status;
        vm.prank(_inspector);
        lt.updateShipmentStatus(_shipId, current);

        // Paso 3: volver a dejar al inspector con su rol original activo.
        //         Desactivamos y re-registramos con rol Inspector.
        vm.startPrank(admin);
        lt.deactivateActor(_inspector);
        lt.registerActor("Inspector Sanitario INVIMA",
            LogisticsTracking.ActorRole.Inspector, "Bogota", _inspector);
        vm.stopPrank();
        // Tras registerActor el inspector queda isActive = true con rol Inspector.
    }

    /**
     * @dev Re-registra un actor (previamente desactivado) con nuevo rol.
     *      Solo funciona si el actor ya fue desactivado (isActive = false).
     */
    function _actorsReregister(
        address _addr,
        string memory _name,
        LogisticsTracking.ActorRole _role,
        string memory _location
    ) internal {
        // registerActor falla si isActive, pero como fue desactivado, el check
        // AlreadyRegisteredAndActive no se dispara (isActive = false).
        lt.registerActor(_name, _role, _location, _addr);
    }

    /**
     * @dev Helper para obtener el tipo de la primera incidencia de un envio.
     */
    function incType(LogisticsTracking _lt, uint256 incId)
        internal view returns (LogisticsTracking.IncidentType)
    {
        return _lt.getIncident(incId).incidentType;
    }
}
