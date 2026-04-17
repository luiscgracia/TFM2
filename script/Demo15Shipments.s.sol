// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {LogisticsTracking} from "../src/LogisticsTracking.sol";

/**
 * @title Demo15Shipments
 * @notice Seed de 15 envíos sobre el contrato ya desplegado por DeployLogistics.s.sol.
 *         NO despliega un contrato nuevo — usa la address determinista de Anvil.
 *
 * ─── Estrategia de ejecución ──────────────────────────────────────────────────
 *   Un único broadcaster: ADMIN (cuenta 0 de Anvil, PK hardcodeada en el Makefile).
 *   ADMIN se re-registra temporalmente con el rol necesario para cada operación
 *   (Sender, Carrier, Hub, Inspector) sin necesidad de multi-wallet.
 *
 * ─── Uso (vía Makefile) ───────────────────────────────────────────────────────
 *   make Demo15Shipments
 *
 *   Esto ejecuta primero DeployLogistics.s.sol (deploy) y luego este script
 *   (seed), ambos con la PK de ADMIN. El contrato queda siempre en:
 *   0x5FbDB2315678afecb367f032d93F642f64180aa3  ← address fija en config.ts
 *
 * ─── Cuentas registradas ──────────────────────────────────────────────────────
 *   [0] admin      0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266  <- broadcaster
 *   [1] sender1    0x70997970C51812dc3A010C7d01b50e0d17dc79C8
 *   [2] sender2    0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
 *   [3] carrier1   0x90F79bf6EB2c4f870365E785982E1f101E93b906
 *   [4] carrier2   0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
 *   [5] hub1       0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc
 *   [6] recipient1 0x976EA74026E726554dB657fA54763abd0C3a0aa9
 *   [7] recipient2 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955
 *   [8] recipient3 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f
 *   [9] recipient4 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
 *  [10] recipient5 0xBcd4042DE499D14e55001CcbB24a551F3b954096
 *  [11] inspector1 0x71bE63f3384f5fb98995898A86B02Fb2426c5788
 */
contract Demo15Shipments is Script {

    // ─── Direcciones Anvil ────────────────────────────────────────────────────
    address constant ADMIN      = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant SENDER1    = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant SENDER2    = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant CARRIER1   = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant CARRIER2   = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    address constant HUB1       = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
    address constant RECIPIENT1 = 0x976EA74026E726554dB657fA54763abd0C3a0aa9;
    address constant RECIPIENT2 = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    address constant RECIPIENT3 = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f;
    address constant RECIPIENT4 = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    address constant RECIPIENT5 = 0xBcd4042DE499D14e55001CcbB24a551F3b954096;
    address constant INSPECTOR1 = 0x71bE63f3384f5fb98995898A86B02Fb2426c5788;

    int256 constant NO_TEMP = type(int256).min;

    LogisticsTracking lt;

    // ─── Rol activo de ADMIN en el contrato ───────────────────────────────────
    // Rastrea el rol actual de ADMIN para no re-registrar si ya es el correcto.
    LogisticsTracking.ActorRole currentAdminRole = LogisticsTracking.ActorRole.None;

    // =========================================================================
    // run() — único broadcast, solo ADMIN firma
    // =========================================================================
    function run() external {
        // Usa el contrato ya desplegado por DeployLogistics.s.sol.
        // La address es determinista: ADMIN (nonce 0) siempre despliega aquí.
        lt = LogisticsTracking(0x5FbDB2315678afecb367f032d93F642f64180aa3);

        vm.startBroadcast(ADMIN);

        // ── Registro de actores reales (usados en la UI) ────────────────────
        lt.registerActor("Farmaceutica BioSalud",      LogisticsTracking.ActorRole.Sender,    "Bogota",    					   SENDER1);
        lt.registerActor("Alimentos FrescoNorte",      LogisticsTracking.ActorRole.Sender,    "Medellin",  					   SENDER2);
        lt.registerActor("TransFria Express",          LogisticsTracking.ActorRole.Carrier,   "Bogota",    					   CARRIER1);
        lt.registerActor("Cargo Rapido SAS",           LogisticsTracking.ActorRole.Carrier,   "Cali",      					   CARRIER2);
        lt.registerActor("Hub Logistico Central",      LogisticsTracking.ActorRole.Hub,       "Bucaramanga",				   HUB1);
        lt.registerActor("Clinica San Rafael",         LogisticsTracking.ActorRole.Recipient, "Cali",      					   RECIPIENT1);
        lt.registerActor("Supermercado La 14",         LogisticsTracking.ActorRole.Recipient, "Pereira",   					   RECIPIENT2);
        lt.registerActor("Hospital El Tunal",          LogisticsTracking.ActorRole.Recipient, "Bogota",       				   RECIPIENT3);
        lt.registerActor("Restaurante Galeria",        LogisticsTracking.ActorRole.Recipient, "Buenaventura, Valle del Cauca", RECIPIENT4);
        lt.registerActor("Drogueria Popular",          LogisticsTracking.ActorRole.Recipient, "Manizales", 					   RECIPIENT5);
        lt.registerActor("Inspector Sanitario INVIMA", LogisticsTracking.ActorRole.Inspector, "Bogota",    					   INSPECTOR1);

        // ── Escenarios ───────────────────────────────────────────────────────
        _escenario01();
        _escenario02();
        _escenario03();
        _escenario04();
        _escenario05();
        _escenario06();
        _escenario07();
        _escenario08();
        _escenario09();
        _escenario10();
        _escenario11();
        _escenario12();
        _escenario13();
        _escenario14();
        _escenario15();

        // ── Limpiar rol de ADMIN al final ────────────────────────────────────
        _removeAdminRole();

        vm.stopBroadcast();

        console.log("===========================================");
        console.log(" Contrato desplegado en:");
        console.log("  ", address(lt));
        console.log(" Envios cargados:", lt.nextShipmentId() - 1);
        console.log("===========================================");
        console.log(" Cuentas para la UI:");
        console.log("  admin      ", ADMIN);
        console.log("  sender1    ", SENDER1);
        console.log("  sender2    ", SENDER2);
        console.log("  carrier1   ", CARRIER1);
        console.log("  carrier2   ", CARRIER2);
        console.log("  hub1       ", HUB1);
        console.log("  recipient1 ", RECIPIENT1);
        console.log("  recipient2 ", RECIPIENT2);
        console.log("  recipient3 ", RECIPIENT3);
        console.log("  recipient4 ", RECIPIENT4);
        console.log("  recipient5 ", RECIPIENT5);
        console.log("  inspector1 ", INSPECTOR1);
        console.log("===========================================");
    }

    // =========================================================================
    // HELPERS de rol — re-registran ADMIN con el rol necesario
    // =========================================================================

    function _asRole(LogisticsTracking.ActorRole role, string memory name) internal {
        if (currentAdminRole == role) return;
        if (currentAdminRole != LogisticsTracking.ActorRole.None) {
            lt.deactivateActor(ADMIN);
        }
        lt.registerActor(name, role, "Bogota", ADMIN);
        currentAdminRole = role;
    }

    function _asSender()   internal { _asRole(LogisticsTracking.ActorRole.Sender,   "ADMIN-Sender"); }
    function _asCarrier()  internal { _asRole(LogisticsTracking.ActorRole.Carrier,  "ADMIN-Carrier"); }
    function _asHub()      internal { _asRole(LogisticsTracking.ActorRole.Hub,      "ADMIN-Hub"); }
    function _asRecipient()internal { _asRole(LogisticsTracking.ActorRole.Recipient,"ADMIN-Recipient"); }
    function _asInspector()internal { _asRole(LogisticsTracking.ActorRole.Inspector,"ADMIN-Inspector"); }

    function _removeAdminRole() internal {
        if (currentAdminRole != LogisticsTracking.ActorRole.None) {
            lt.deactivateActor(ADMIN);
            currentAdminRole = LogisticsTracking.ActorRole.None;
        }
    }

    // =========================================================================
    // HELPERS de operación
    // Los "actor" params son solo para documentar quién sería en producción.
    // En el seed, ADMIN ejecuta todo cambiando de rol según se necesite.
    // =========================================================================

    /// @dev ADMIN como Carrier: updateStatus(InTransit) + recordCheckpoint
    function _assignAndCheckpoint(
        bool asCarrier, uint256 shipId,
        string memory loc, LogisticsTracking.CheckpointType cpType,
        string memory notes, int256 temp
    ) internal {
        if (asCarrier) _asCarrier(); else _asHub();
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);
        lt.recordCheckpoint(shipId, loc, cpType, notes, temp);
    }

    function _checkpointCarrier(uint256 shipId, string memory loc,
        LogisticsTracking.CheckpointType cpType, string memory notes, int256 temp) internal {
        _asCarrier();
        lt.recordCheckpoint(shipId, loc, cpType, notes, temp);
    }

    function _checkpointHub(uint256 shipId, string memory loc,
        LogisticsTracking.CheckpointType cpType, string memory notes, int256 temp) internal {
        _asHub();
        lt.recordCheckpoint(shipId, loc, cpType, notes, temp);
    }

    function _checkpointInspector(uint256 shipId, string memory loc,
        LogisticsTracking.CheckpointType cpType, string memory notes, int256 temp) internal {
        _asInspector();
        lt.recordCheckpoint(shipId, loc, cpType, notes, temp);
    }

    function _statusCarrier(uint256 shipId, LogisticsTracking.ShipmentStatus s) internal {
        _asCarrier(); lt.updateShipmentStatus(shipId, s);
    }

    function _statusHub(uint256 shipId, LogisticsTracking.ShipmentStatus s) internal {
        _asHub(); lt.updateShipmentStatus(shipId, s);
    }

    function _assignHub(uint256 shipId) internal {
        _asHub();
        lt.updateShipmentStatus(shipId, lt.getShipment(shipId).status);
    }

    function _incidentCarrier(uint256 shipId, LogisticsTracking.IncidentType t, string memory d) internal {
        _asCarrier(); lt.reportIncident(shipId, t, d);
    }

    function _incidentHub(uint256 shipId, LogisticsTracking.IncidentType t, string memory d) internal {
        _asHub(); lt.reportIncident(shipId, t, d);
    }

    function _incidentInspector(uint256 shipId, LogisticsTracking.IncidentType t, string memory d) internal {
        _asInspector(); lt.reportIncident(shipId, t, d);
    }

    /// @dev Para confirmDelivery: ADMIN actúa como Recipient
    function _confirmDelivery(uint256 shipId) internal {
        _asRecipient();
        lt.confirmDelivery(shipId);
    }

    /// @dev Asigna ADMIN como Inspector al envío (sin cambiar rol permanente)
    function _assignInspectorAndCheckpoint(uint256 shipId, string memory loc,
        LogisticsTracking.CheckpointType cpType, string memory notes, int256 temp) internal {
        _asHub(); // Inspector no puede updateShipmentStatus, usa Hub temporalmente
        lt.updateShipmentStatus(shipId, lt.getShipment(shipId).status);
        _asInspector();
        lt.recordCheckpoint(shipId, loc, cpType, notes, temp);
    }

    // =========================================================================
    // ESCENARIO 01 — Vacunas COVID-19 | cadena de frio OK | OutForDelivery
    // =========================================================================
    function _escenario01() internal {
        console.log("[E01] Vacunas COVID-19 - cadena de frio OK");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT1, "Vacunas COVID-19 (50 dosis)", "Bogota", "Cali", true);

        _assignAndCheckpoint(true, id, "Bodega BioSalud - Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Recogida confirmada. Cadena de frio iniciada.", 45);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Autopista Bogota-Ibague Km 80", LogisticsTracking.CheckpointType.Transit,
            "Temperatura estable.", 42);
        _checkpointCarrier(id, "Hub Bucaramanga", LogisticsTracking.CheckpointType.Hub,
            "Transferencia a hub intermedio.", 38);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.AtHub);
        _assignHub(id);
        _checkpointHub(id, "Hub Bucaramanga - Sala Fria", LogisticsTracking.CheckpointType.Hub,
            "Verificacion de sellos OK.", 40);
        _statusHub(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Distribucion Cali Norte", LogisticsTracking.CheckpointType.Transit,
            "En ruta a destino final.", 44);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("  -> Envio #", id, "| OutForDelivery | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 02 — Insulina | TempViolation automatica | InTransit
    // =========================================================================
    function _escenario02() internal {
        console.log("[E02] Insulina - violacion de temperatura automatica");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT3, "Insulina NPH 100 UI/mL (200 viales)", "Bogota", "Bogota Sur", true);

        _assignAndCheckpoint(true, id, "Laboratorio BioSalud Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Recogida con temperatura inicial correcta.", 50);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Av. Boyaca Km 15", LogisticsTracking.CheckpointType.Transit, "Ruta normal.", 45);
        _checkpointCarrier(id, "Soacha - Parqueadero forzado", LogisticsTracking.CheckpointType.Transit,
            "Falla del sistema de refrigeracion. Temp elevada.", 120);
        console.log("  -> Envio #", id, "| InTransit | 1 TempViolation auto");
    }

    // =========================================================================
    // ESCENARIO 03 — Carne fresca | 2 TempViolation + Damage | AtHub
    // =========================================================================
    function _escenario03() internal {
        console.log("[E03] Carne fresca - multiples violaciones + Damage");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT4, "Carne de res refrigerada (500 kg)", "Medellin, Antioquia", "Barranquilla, Atlantico", true);

        _assignAndCheckpoint(true, id, "Planta FrescoNorte - Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta al inicio.", 25);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Puerto Berrio", LogisticsTracking.CheckpointType.Transit,
            "Congelador en maxima potencia. Temperatura muy baja.", 5);
        _checkpointCarrier(id, "Caucasia", LogisticsTracking.CheckpointType.Transit,
            "Unidad de refrigeracion con falla intermitente.", 95);
        _checkpointCarrier(id, "Planeta Rica", LogisticsTracking.CheckpointType.Transit, "Temperatura recuperada.", 35);
        _assignHub(id);
        _checkpointHub(id, "Hub Barranquilla", LogisticsTracking.CheckpointType.Hub,
            "Se observan empaques deteriorados.", NO_TEMP);
        _statusHub(id, LogisticsTracking.ShipmentStatus.AtHub);
        _incidentCarrier(id, LogisticsTracking.IncidentType.Damage,
            "Empaques rotos detectados al abrir contenedor en hub Barranquilla.");
        console.log("  -> Envio #", id, "| AtHub | 2 TempViolation + 1 Damage");
    }

    // =========================================================================
    // ESCENARIO 04 — Electronicos | Delay en hub | AtHub
    // =========================================================================
    function _escenario04() internal {
        console.log("[E04] Electronicos - Delay en hub");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT2, "Tablets educativas (100 unidades)", "Bogota", "Pereira", false);

        _assignAndCheckpoint(true, id, "Bodega Tecnologia BioSalud", LogisticsTracking.CheckpointType.Pickup,
            "Envio recogido sin novedad.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Manizales - Peaje", LogisticsTracking.CheckpointType.Transit,
            "Sin novedades. Trafico fluido.", NO_TEMP);
        _assignHub(id);
        _checkpointHub(id, "Hub Armenia", LogisticsTracking.CheckpointType.Hub,
            "Paquete retenido por inspeccion aduanera.", NO_TEMP);
        _statusHub(id, LogisticsTracking.ShipmentStatus.AtHub);
        _incidentHub(id, LogisticsTracking.IncidentType.Delay,
            "Retencion aduanera por documentacion incompleta. Demora estimada 48h.");
        console.log("  -> Envio #", id, "| AtHub | 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 05 — Leche en polvo | Delivered completo
    // =========================================================================
    function _escenario05() internal {
        console.log("[E05] Leche en polvo - entrega completa");
        // Shipment creado con ADMIN como recipient para que pueda confirmar la entrega.
        _asSender();
        uint256 id = lt.createShipment(ADMIN, "Leche en polvo entera (200 kg)", "Medellin", "Pereira", false);

        _assignAndCheckpoint(true, id, "Planta FrescoNorte - Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Carga verificada y sellada.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Santa Barbara", LogisticsTracking.CheckpointType.Transit, "Sin novedad.", NO_TEMP);
        _assignHub(id);
        _checkpointHub(id, "Hub Pereira - Clasificacion", LogisticsTracking.CheckpointType.Hub,
            "Listo para reparto.", NO_TEMP);
        _statusHub(id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        _checkpointCarrier(id, "Supermercado La 14 - Pereira", LogisticsTracking.CheckpointType.Delivery,
            "Entrega en puerta.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        lt.confirmDelivery(id); // ADMIN es el recipient de este envio
        console.log("  -> Envio #", id, "| Delivered | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 06 — Medicamentos | Unauthorized (inspector) | InTransit
    // =========================================================================
    function _escenario06() internal {
        console.log("[E06] Medicamentos - acceso no autorizado (inspector)");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT5,
            "Antibioticos amoxicilina 500mg (1000 cajas)", "Bogota", "Manizales", false);

        _assignAndCheckpoint(true, id, "Planta Bogota Norte", LogisticsTracking.CheckpointType.Pickup,
            "Cargamento sellado y documentado.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Autopista al Llano - Km 30", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", NO_TEMP);
        _assignInspectorAndCheckpoint(id, "Puesto de control INVIMA - Girardot",
            LogisticsTracking.CheckpointType.Other, "Inspeccion sanitaria de emergencia iniciada.", NO_TEMP);
        _incidentInspector(id, LogisticsTracking.IncidentType.Unauthorized,
            "Sello de seguridad violado en caja #47. Posible intervencion no autorizada durante parada.");
        console.log("  -> Envio #", id, "| InTransit | 1 Unauthorized");
    }

    // =========================================================================
    // ESCENARIO 07 — Frutas tropicales | checkpoints detallados hub | OutForDelivery
    // =========================================================================
    function _escenario07() internal {
        console.log("[E07] Frutas tropicales - multiples checkpoints en hub");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT2, "Fresas y arandanos frescos (300 kg)", "Medellin", "Pereira", true);

        _assignAndCheckpoint(true, id, "Finca FrescoNorte - Rionegro", LogisticsTracking.CheckpointType.Pickup,
            "Fruta recogida. Temperatura inicial.", 60);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Tunel de Occidente", LogisticsTracking.CheckpointType.Transit, "Sin novedad.", 58);
        _checkpointCarrier(id, "Santa Fe de Antioquia", LogisticsTracking.CheckpointType.Transit,
            "Temperatura estable.", 55);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.AtHub);
        _assignHub(id);
        _checkpointHub(id, "Hub Pereira - Recepcion",       LogisticsTracking.CheckpointType.Hub, "Recepcion registrada.", 57);
        _checkpointHub(id, "Hub Pereira - Sala clasificacion", LogisticsTracking.CheckpointType.Hub, "Clasificacion por destino.", 55);
        _checkpointHub(id, "Hub Pereira - Camara fria",     LogisticsTracking.CheckpointType.Hub, "Almacenamiento temporal OK.", 40);
        _checkpointHub(id, "Hub Pereira - Despacho",        LogisticsTracking.CheckpointType.Hub, "Reasignado a reparto local.", 52);
        _statusHub(id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("  -> Envio #", id, "| OutForDelivery | 7 checkpoints | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 08 — Plasma sanguineo | frio extremo + Delay | AtHub
    // =========================================================================
    function _escenario08() internal {
        console.log("[E08] Plasma sanguineo - frio extremo + Delay");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT1, "Plasma sanguineo grupo O+ (50 bolsas)", "Bogota", "Cali", true);

        _assignAndCheckpoint(true, id, "Banco de Sangre - Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta.", 35);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Espinal - Parada de emergencia", LogisticsTracking.CheckpointType.Transit,
            "Sensor reporta temperatura negativa. Posible falla del equipo.", -50);
        _incidentCarrier(id, LogisticsTracking.IncidentType.Delay,
            "Camion refrigerado averiado en Espinal. Espera de vehiculo de reemplazo: 5 horas.");
        _checkpointCarrier(id, "Espinal - Trasvase a vehiculo sustituto", LogisticsTracking.CheckpointType.Other,
            "Temperatura recuperada en nuevo vehiculo.", 30);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.AtHub);
        _assignHub(id);
        _checkpointHub(id, "Hub Cali - Cuarentena fria", LogisticsTracking.CheckpointType.Hub,
            "Material retenido para evaluacion de integridad.", 28);
        console.log("  -> Envio #", id, "| AtHub | 1 TempViolation + 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 09 — Uniformes | Damage + Delay | InTransit
    // =========================================================================
    function _escenario09() internal {
        console.log("[E09] Uniformes escolares - Damage + Delay");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT4, "Uniformes escolares (200 conjuntos)", "Medellin", "Barranquilla", false);

        _assignAndCheckpoint(true, id, "Centro distribucion Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Paquetes en buen estado.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Magangue", LogisticsTracking.CheckpointType.Transit, "Ruta normal.", NO_TEMP);
        _incidentCarrier(id, LogisticsTracking.IncidentType.Damage,
            "Choque leve en via Magangue-Barranquilla. Cajas del compartimiento trasero afectadas.");
        _incidentCarrier(id, LogisticsTracking.IncidentType.Delay,
            "Procedimiento policial por accidente. Demora estimada 3 horas adicionales.");
        _checkpointCarrier(id, "Barranquilla - Norte", LogisticsTracking.CheckpointType.Transit,
            "Continuando ruta. Danos documentados.", NO_TEMP);
        console.log("  -> Envio #", id, "| InTransit | 1 Damage + 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 10 — Vacunas pediatricas | TempViolation + Unauthorized | OutForDelivery
    // =========================================================================
    function _escenario10() internal {
        console.log("[E10] Vacunas pediatricas - TempViolation + Unauthorized");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT3,
            "Vacunas pentavalentes pediatricas (300 dosis)", "Bogota", "Bogota", true);

        _assignAndCheckpoint(true, id, "ICBF Deposito Norte", LogisticsTracking.CheckpointType.Pickup,
            "Sellado y temperatura verificada.", 45);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Zona Industrial Bogota", LogisticsTracking.CheckpointType.Transit,
            "Vehiculo expuesto al sol durante carga cruzada. Temperatura elevada.", 250);
        _assignInspectorAndCheckpoint(id, "Puesto inspeccion - Zona Industrial",
            LogisticsTracking.CheckpointType.Other, "Inspeccion INVIMA iniciada.", NO_TEMP);
        _incidentInspector(id, LogisticsTracking.IncidentType.Unauthorized,
            "Precinto del lote 12 retirado sin autorizacion durante trasbordo en zona industrial.");
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("  -> Envio #", id, "| OutForDelivery | 1 TempViolation + 1 Unauthorized");
    }

    // =========================================================================
    // ESCENARIO 11 — Marcapasos | ruta larga multi-checkpoint | OutForDelivery
    // =========================================================================
    function _escenario11() internal {
        console.log("[E11] Marcapasos cardiacos - ruta larga multi-checkpoint");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT1, "Marcapasos cardiacos (10 unidades)", "Bogota", "Cali", false);

        _assignAndCheckpoint(true, id, "Importadora Medica Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Dispositivos verificados y embalados.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);

        string[5] memory lugares = ["Soacha", "Fusagasuga", "Girardot", "Espinal", "Ibague"];
        for (uint i = 0; i < lugares.length; i++) {
            _checkpointCarrier(id, lugares[i], LogisticsTracking.CheckpointType.Transit,
                "Control de ruta sin novedad.", NO_TEMP);
        }

        _assignHub(id);
        _checkpointHub(id, "Hub Armenia", LogisticsTracking.CheckpointType.Hub, "Transito por hub.", NO_TEMP);
        _statusHub(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Buga", LogisticsTracking.CheckpointType.Transit, "Ultimas horas de viaje.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("  -> Envio #", id, "| OutForDelivery | 8 checkpoints | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 12 — Bebidas gaseosas | Lost + Delay | InTransit
    // =========================================================================
    function _escenario12() internal {
        console.log("[E12] Bebidas gaseosas - Lost + Delay");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT4,
            "Gaseosas Postobon surtidas (600 unidades)", "Medellin, Antioquia", "Buenaventura, Valle del Cauca", false);

        _assignAndCheckpoint(true, id, "Planta Postobon Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Carga completa verificada: 600 unidades.", NO_TEMP);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Valledupar - Parque industrial", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", NO_TEMP);
        _incidentCarrier(id, LogisticsTracking.IncidentType.Lost,
            "Pale #3 (150 unidades) no localizado tras transbordo nocturno en Valledupar.");
        _incidentCarrier(id, LogisticsTracking.IncidentType.Delay,
            "Busqueda del pale perdido genera retraso de 8 horas en la ruta.");
        _checkpointCarrier(id, "Barranquilla - Av. Circunvalar", LogisticsTracking.CheckpointType.Transit,
            "Continua ruta con carga parcial.", NO_TEMP);
        console.log("  -> Envio #", id, "| InTransit | 1 Lost + 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 13 — Material quirurgico | TempViolation leve + Damage | AtHub
    // =========================================================================
    function _escenario13() internal {
        console.log("[E13] Material quirurgico - TempViolation leve + Damage");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT5,
            "Suturas y material quirurgico esteril (50 cajas)", "Bogota", "Manizales", true);

        _assignAndCheckpoint(true, id, "Proveedor Medico Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Material esteril sellado y verificado.", 30);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Honda", LogisticsTracking.CheckpointType.Transit, "Temperatura normal.", 35);
        _checkpointCarrier(id, "La Dorada - Carga compartida", LogisticsTracking.CheckpointType.Transit,
            "Temperatura subio levemente por apertura de compuerta durante carga cruzada.", 90);
        _incidentCarrier(id, LogisticsTracking.IncidentType.Damage,
            "Humedad exterior dano el embalaje de carton de 12 cajas. Contenido intacto.");
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.AtHub);
        _assignHub(id);
        _checkpointHub(id, "Hub Manizales - Recepcion", LogisticsTracking.CheckpointType.Hub,
            "Revision de empaques en curso.", 28);
        console.log("  -> Envio #", id, "| AtHub | 1 TempViolation + 1 Damage");
    }

    // =========================================================================
    // ESCENARIO 14 — Somatropina | inspector valida | 0 incidencias | OutForDelivery
    // =========================================================================
    function _escenario14() internal {
        console.log("[E14] Somatropina - inspector INVIMA valida cadena de frio");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT3,
            "Hormona de crecimiento somatropina (20 viales)", "Bogota", "Bogota Norte", true);

        _assignAndCheckpoint(true, id, "Laboratorio Hormonal - Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura verificada al inicio.", 45);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Autopista Norte Km 15", LogisticsTracking.CheckpointType.Transit, "Sin novedad.", 42);
        _checkpointCarrier(id, "Centro de acopio Norte", LogisticsTracking.CheckpointType.Transit,
            "Temperatura estable.", 40);
        _assignInspectorAndCheckpoint(id, "Puesto de inspeccion - Usaquen",
            LogisticsTracking.CheckpointType.Other,
            "Inspeccion INVIMA: Temperatura 4.0C, empaques integros, cadena de frio cumplida.", 40);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("  -> Envio #", id, "| OutForDelivery | inspector activo | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 15 — Helados | 3 TempViolation + Damage + Delay | AtHub
    // =========================================================================
    function _escenario15() internal {
        console.log("[E15] Helados artesanales - caso critico multi-incidencia");
        _asSender();
        uint256 id = lt.createShipment(RECIPIENT2,
            "Helados artesanales premium (800 unidades)", "Medellin", "Pereira", true);

        _assignAndCheckpoint(true, id, "Heladeria Premium - Planta Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta -18C externa. Cadena de frio activa.", 20);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpointCarrier(id, "Caldas - Sur de Medellin", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", 22);
        _checkpointCarrier(id, "La Pintada - Estacion de servicio", LogisticsTracking.CheckpointType.Transit,
            "Corte de energia 15 min. Temperatura sube.", 100);
        _checkpointCarrier(id, "Supia", LogisticsTracking.CheckpointType.Transit, "Temperatura bajando.", 75);
        _checkpointCarrier(id, "Riosucio - Trancon", LogisticsTracking.CheckpointType.Transit,
            "Trancon de 2h. Sistema de refrigeracion al limite.", 150);
        _statusCarrier(id, LogisticsTracking.ShipmentStatus.AtHub);
        _assignHub(id);
        _checkpointHub(id, "Hub Pereira - Verificacion de llegada", LogisticsTracking.CheckpointType.Hub,
            "Temperatura al llegar: 12C. Cadena de frio comprometida.", 120);
        _incidentHub(id, LogisticsTracking.IncidentType.Damage,
            "Helados derretidos parcialmente. Estimado 40% del lote comprometido.");
        _incidentHub(id, LogisticsTracking.IncidentType.Delay,
            "Lote retenido 24h por evaluacion de inocuidad alimentaria.");
        _assignInspectorAndCheckpoint(id, "Hub Pereira - Laboratorio",
            LogisticsTracking.CheckpointType.Other,
            "Muestras tomadas. Resultado pendiente. Envio retenido en hub.", NO_TEMP);
        console.log("  -> Envio #", id, "| AtHub | 3 TempViolation + 1 Damage + 1 Delay");
    }
}
