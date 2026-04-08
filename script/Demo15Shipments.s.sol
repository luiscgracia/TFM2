// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import "../src/LogisticsTracking.sol";

/**
 * @title Demo15Shipments
 * @notice Despliega LogisticsTracking en Anvil y carga 15 escenarios de prueba.
 *
 * ─── Estrategia de ejecución ──────────────────────────────────────────────────
 *   Cada actor firma con su propia private key de Anvil usando
 *   vm.startBroadcast(uint256 privateKey). Esto evita tanto el error de prank
 *   dentro de broadcast como el error de "No associated wallet" que ocurre al
 *   pasar una address a startBroadcast sin --unlocked para esa cuenta.
 *
 * ─── Uso ──────────────────────────────────────────────────────────────────────
 *   # Terminal 1
 *   anvil
 *
 *   # Terminal 2
 *   forge script script/Demo15Shipments.s.sol \
 *       --rpc-url http://127.0.0.1:8545 \
 *       --broadcast
 *
 *   La dirección del contrato se imprime al final. Pégala en la UI.
 *
 * ─── Cuentas (mnemónico Anvil por defecto) ────────────────────────────────────
 *   [0] admin      0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
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

    // ─── Private keys Anvil (mnemónico estándar — solo para uso local) ────────
    uint256 constant PK_ADMIN      = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant PK_SENDER1    = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant PK_SENDER2    = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant PK_CARRIER1   = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 constant PK_CARRIER2   = 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a;
    uint256 constant PK_HUB1       = 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba;
    uint256 constant PK_RECIPIENT1 = 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e;
    uint256 constant PK_RECIPIENT2 = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;
    uint256 constant PK_RECIPIENT3 = 0xdbda1821b80551c9d65939329250132c444b83d1c5b2660f4a62f8c18c7d5b4a;
    uint256 constant PK_RECIPIENT4 = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;
    uint256 constant PK_RECIPIENT5 = 0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897;
    uint256 constant PK_INSPECTOR1 = 0x701b615bbdfb9de65240bc28bd21bbc0d996645a3dd57e7b12bc2bdf6f192c82;

    // ─── Direcciones derivadas (para referencias legibles) ────────────────────
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

    // =========================================================================
    // run()
    // =========================================================================
    function run() external {
        // Deploy + registro de actores como ADMIN
        vm.startBroadcast(PK_ADMIN);
        lt = new LogisticsTracking();
        lt.registerActor("Farmaceutica BioSalud",      LogisticsTracking.ActorRole.Sender,    "Bogota",       SENDER1);
        lt.registerActor("Alimentos FrescoNorte",      LogisticsTracking.ActorRole.Sender,    "Medellin",     SENDER2);
        lt.registerActor("TransFria Express",          LogisticsTracking.ActorRole.Carrier,   "Bogota",       CARRIER1);
        lt.registerActor("Cargo Rapido SAS",           LogisticsTracking.ActorRole.Carrier,   "Cali",         CARRIER2);
        lt.registerActor("Hub Logistico Central",      LogisticsTracking.ActorRole.Hub,       "Bucaramanga",  HUB1);
        lt.registerActor("Clinica San Rafael",         LogisticsTracking.ActorRole.Recipient, "Cali",         RECIPIENT1);
        lt.registerActor("Supermercado La 14",         LogisticsTracking.ActorRole.Recipient, "Pereira",      RECIPIENT2);
        lt.registerActor("Hospital El Tunal",          LogisticsTracking.ActorRole.Recipient, "Bogota",       RECIPIENT3);
        lt.registerActor("Restaurante Galeria",        LogisticsTracking.ActorRole.Recipient, "Barranquilla", RECIPIENT4);
        lt.registerActor("Drogueria Popular",          LogisticsTracking.ActorRole.Recipient, "Manizales",    RECIPIENT5);
        lt.registerActor("Inspector Sanitario INVIMA", LogisticsTracking.ActorRole.Inspector, "Bogota",       INSPECTOR1);
        vm.stopBroadcast();

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
    // HELPERS — cada uno firma con la private key del actor correspondiente
    // =========================================================================

    function _assignAndCheckpoint(
        uint256 pk, uint256 shipId,
        string memory loc, LogisticsTracking.CheckpointType cpType,
        string memory notes, int256 temp
    ) internal {
        vm.startBroadcast(pk);
        lt.updateShipmentStatus(shipId, LogisticsTracking.ShipmentStatus.InTransit);
        lt.recordCheckpoint(shipId, loc, cpType, notes, temp);
        vm.stopBroadcast();
    }

    function _checkpoint(
        uint256 pk, uint256 shipId,
        string memory loc, LogisticsTracking.CheckpointType cpType,
        string memory notes, int256 temp
    ) internal {
        vm.startBroadcast(pk);
        lt.recordCheckpoint(shipId, loc, cpType, notes, temp);
        vm.stopBroadcast();
    }

    function _status(uint256 pk, uint256 shipId, LogisticsTracking.ShipmentStatus s) internal {
        vm.startBroadcast(pk);
        lt.updateShipmentStatus(shipId, s);
        vm.stopBroadcast();
    }

    function _assign(uint256 pk, uint256 shipId) internal {
        LogisticsTracking.ShipmentStatus current = lt.getShipment(shipId).status;
        vm.startBroadcast(pk);
        lt.updateShipmentStatus(shipId, current);
        vm.stopBroadcast();
    }

    function _incident(
        uint256 pk, uint256 shipId,
        LogisticsTracking.IncidentType t, string memory desc
    ) internal {
        vm.startBroadcast(pk);
        lt.reportIncident(shipId, t, desc);
        vm.stopBroadcast();
    }

    /// @dev Re-registra INSPECTOR1 temporalmente como Hub para que pueda ser
    ///      asignado a un envio, luego restaura su rol Inspector.
    function _assignInspector(uint256 shipId) internal {
        vm.startBroadcast(PK_ADMIN);
        lt.deactivateActor(INSPECTOR1);
        lt.registerActor("Inspector Sanitario INVIMA",
            LogisticsTracking.ActorRole.Hub, "Bogota", INSPECTOR1);
        vm.stopBroadcast();

        LogisticsTracking.ShipmentStatus current = lt.getShipment(shipId).status;
        vm.startBroadcast(PK_INSPECTOR1);
        lt.updateShipmentStatus(shipId, current);
        vm.stopBroadcast();

        vm.startBroadcast(PK_ADMIN);
        lt.deactivateActor(INSPECTOR1);
        lt.registerActor("Inspector Sanitario INVIMA",
            LogisticsTracking.ActorRole.Inspector, "Bogota", INSPECTOR1);
        vm.stopBroadcast();
    }

    // =========================================================================
    // ESCENARIO 01 — Vacunas COVID-19 | cadena de frio OK | OutForDelivery
    // =========================================================================
    function _escenario01() internal {
        console.log("[E01] Vacunas COVID-19 - cadena de frio OK");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT1,
            "Vacunas COVID-19 (50 dosis)", "Bogota", "Cali", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Bodega BioSalud - Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Recogida confirmada. Cadena de frio iniciada.", 45);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Autopista Bogota-Ibague Km 80", LogisticsTracking.CheckpointType.Transit,
            "Temperatura estable.", 42);
        _checkpoint(PK_CARRIER1, id,
            "Hub Bucaramanga", LogisticsTracking.CheckpointType.Hub,
            "Transferencia a hub intermedio.", 38);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.AtHub);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Bucaramanga - Sala Fria", LogisticsTracking.CheckpointType.Hub,
            "Verificacion de sellos OK.", 40);
        _status(PK_HUB1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Distribucion Cali Norte", LogisticsTracking.CheckpointType.Transit,
            "En ruta a destino final.", 44);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.OutForDelivery);

        console.log("  -> Envio #", id, "| OutForDelivery | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 02 — Insulina | TempViolation automatica | InTransit
    // =========================================================================
    function _escenario02() internal {
        console.log("[E02] Insulina - violacion de temperatura automatica");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT3,
            "Insulina NPH 100 UI/mL (200 viales)", "Bogota", "Bogota Sur", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Laboratorio BioSalud Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Recogida con temperatura inicial correcta.", 50);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Av. Boyaca Km 15", LogisticsTracking.CheckpointType.Transit,
            "Ruta normal.", 45);
        _checkpoint(PK_CARRIER1, id,
            "Soacha - Parqueadero forzado", LogisticsTracking.CheckpointType.Transit,
            "Falla del sistema de refrigeracion. Temp elevada.", 120);

        console.log("  -> Envio #", id, "| InTransit | 1 TempViolation auto");
    }

    // =========================================================================
    // ESCENARIO 03 — Carne fresca | 2 TempViolation + Damage | AtHub
    // =========================================================================
    function _escenario03() internal {
        console.log("[E03] Carne fresca - multiples violaciones + Damage");
        vm.startBroadcast(PK_SENDER2);
        uint256 id = lt.createShipment(RECIPIENT4,
            "Carne de res refrigerada (500 kg)", "Medellin", "Barranquilla", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER2, id,
            "Planta FrescoNorte - Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta al inicio.", 25);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER2, id,
            "Puerto Berrio", LogisticsTracking.CheckpointType.Transit,
            "Congelador en maxima potencia. Temperatura muy baja.", 5);
        _checkpoint(PK_CARRIER2, id,
            "Caucasia", LogisticsTracking.CheckpointType.Transit,
            "Unidad de refrigeracion con falla intermitente.", 95);
        _checkpoint(PK_CARRIER2, id,
            "Planeta Rica", LogisticsTracking.CheckpointType.Transit,
            "Temperatura recuperada.", 35);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Barranquilla", LogisticsTracking.CheckpointType.Hub,
            "Se observan empaques deteriorados.", NO_TEMP);
        _status(PK_HUB1, id, LogisticsTracking.ShipmentStatus.AtHub);
        _incident(PK_CARRIER2, id, LogisticsTracking.IncidentType.Damage,
            "Empaques rotos detectados al abrir contenedor en hub Barranquilla.");

        console.log("  -> Envio #", id, "| AtHub | 2 TempViolation + 1 Damage");
    }

    // =========================================================================
    // ESCENARIO 04 — Electronicos | Delay en hub | AtHub
    // =========================================================================
    function _escenario04() internal {
        console.log("[E04] Electronicos - Delay en hub");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT2,
            "Tablets educativas (100 unidades)", "Bogota", "Pereira", false);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Bodega Tecnologia BioSalud", LogisticsTracking.CheckpointType.Pickup,
            "Envio recogido sin novedad.", NO_TEMP);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Manizales - Peaje", LogisticsTracking.CheckpointType.Transit,
            "Sin novedades. Trafico fluido.", NO_TEMP);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Armenia", LogisticsTracking.CheckpointType.Hub,
            "Paquete retenido por inspeccion aduanera.", NO_TEMP);
        _status(PK_HUB1, id, LogisticsTracking.ShipmentStatus.AtHub);
        _incident(PK_HUB1, id, LogisticsTracking.IncidentType.Delay,
            "Retencion aduanera por documentacion incompleta. Demora estimada 48h.");

        console.log("  -> Envio #", id, "| AtHub | 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 05 — Leche en polvo | Delivered completo
    // =========================================================================
    function _escenario05() internal {
        console.log("[E05] Leche en polvo - entrega completa");
        vm.startBroadcast(PK_SENDER2);
        uint256 id = lt.createShipment(RECIPIENT2,
            "Leche en polvo entera (200 kg)", "Medellin", "Pereira", false);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER2, id,
            "Planta FrescoNorte - Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Carga verificada y sellada.", NO_TEMP);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER2, id,
            "Santa Barbara", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", NO_TEMP);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Pereira - Clasificacion", LogisticsTracking.CheckpointType.Hub,
            "Listo para reparto.", NO_TEMP);
        _status(PK_HUB1, id, LogisticsTracking.ShipmentStatus.OutForDelivery);
        _checkpoint(PK_CARRIER2, id,
            "Supermercado La 14 - Pereira", LogisticsTracking.CheckpointType.Delivery,
            "Entrega en puerta.", NO_TEMP);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.OutForDelivery);

        vm.startBroadcast(PK_RECIPIENT2);
        lt.confirmDelivery(id);
        vm.stopBroadcast();

        console.log("  -> Envio #", id, "| Delivered | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 06 — Medicamentos | Unauthorized (inspector) | InTransit
    // =========================================================================
    function _escenario06() internal {
        console.log("[E06] Medicamentos - acceso no autorizado (inspector)");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT5,
            "Antibioticos amoxicilina 500mg (1000 cajas)", "Bogota", "Manizales", false);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Planta Bogota Norte", LogisticsTracking.CheckpointType.Pickup,
            "Cargamento sellado y documentado.", NO_TEMP);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Autopista al Llano - Km 30", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", NO_TEMP);
        _assignInspector(id);
        _incident(PK_INSPECTOR1, id, LogisticsTracking.IncidentType.Unauthorized,
            "Sello de seguridad violado en caja #47. Posible intervencion no autorizada durante parada.");
        _checkpoint(PK_INSPECTOR1, id,
            "Puesto de control INVIMA - Girardot", LogisticsTracking.CheckpointType.Other,
            "Inspeccion sanitaria de emergencia iniciada.", NO_TEMP);

        console.log("  -> Envio #", id, "| InTransit | 1 Unauthorized");
    }

    // =========================================================================
    // ESCENARIO 07 — Frutas tropicales | checkpoints detallados hub | OutForDelivery
    // =========================================================================
    function _escenario07() internal {
        console.log("[E07] Frutas tropicales - multiples checkpoints en hub");
        vm.startBroadcast(PK_SENDER2);
        uint256 id = lt.createShipment(RECIPIENT2,
            "Fresas y arandanos frescos (300 kg)", "Medellin", "Pereira", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER2, id,
            "Finca FrescoNorte - Rionegro", LogisticsTracking.CheckpointType.Pickup,
            "Fruta recogida. Temperatura inicial.", 60);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER2, id,
            "Tunel de Occidente", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", 58);
        _checkpoint(PK_CARRIER2, id,
            "Santa Fe de Antioquia", LogisticsTracking.CheckpointType.Transit,
            "Temperatura estable.", 55);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.AtHub);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Pereira - Recepcion", LogisticsTracking.CheckpointType.Hub,
            "Recepcion registrada.", 57);
        _checkpoint(PK_HUB1, id,
            "Hub Pereira - Sala clasificacion", LogisticsTracking.CheckpointType.Hub,
            "Clasificacion por destino.", 55);
        _checkpoint(PK_HUB1, id,
            "Hub Pereira - Camara fria", LogisticsTracking.CheckpointType.Hub,
            "Almacenamiento temporal OK.", 40);
        _checkpoint(PK_HUB1, id,
            "Hub Pereira - Despacho", LogisticsTracking.CheckpointType.Hub,
            "Reasignado a reparto local.", 52);
        _status(PK_HUB1, id, LogisticsTracking.ShipmentStatus.OutForDelivery);

        console.log("  -> Envio #", id, "| OutForDelivery | 7 checkpoints | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 08 — Plasma sanguineo | frio extremo + Delay | AtHub
    // =========================================================================
    function _escenario08() internal {
        console.log("[E08] Plasma sanguineo - frio extremo + Delay");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT1,
            "Plasma sanguineo grupo O+ (50 bolsas)", "Bogota", "Cali", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Banco de Sangre - Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta.", 35);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Espinal - Parada de emergencia", LogisticsTracking.CheckpointType.Transit,
            "Sensor reporta temperatura negativa. Posible falla del equipo.", -50);
        _incident(PK_CARRIER1, id, LogisticsTracking.IncidentType.Delay,
            "Camion refrigerado averiado en Espinal. Espera de vehiculo de reemplazo: 5 horas.");
        _checkpoint(PK_CARRIER1, id,
            "Espinal - Trasvase a vehiculo sustituto", LogisticsTracking.CheckpointType.Other,
            "Temperatura recuperada en nuevo vehiculo.", 30);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.AtHub);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Cali - Cuarentena fria", LogisticsTracking.CheckpointType.Hub,
            "Material retenido para evaluacion de integridad.", 28);

        console.log("  -> Envio #", id, "| AtHub | 1 TempViolation + 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 09 — Uniformes | Damage + Delay | InTransit
    // =========================================================================
    function _escenario09() internal {
        console.log("[E09] Uniformes escolares - Damage + Delay");
        vm.startBroadcast(PK_SENDER2);
        uint256 id = lt.createShipment(RECIPIENT4,
            "Uniformes escolares (200 conjuntos)", "Medellin", "Barranquilla", false);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER2, id,
            "Centro distribucion Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Paquetes en buen estado.", NO_TEMP);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER2, id,
            "Magangue", LogisticsTracking.CheckpointType.Transit,
            "Ruta normal.", NO_TEMP);
        _incident(PK_CARRIER2, id, LogisticsTracking.IncidentType.Damage,
            "Choque leve en via Magangue-Barranquilla. Cajas del compartimiento trasero afectadas.");
        _incident(PK_CARRIER2, id, LogisticsTracking.IncidentType.Delay,
            "Procedimiento policial por accidente. Demora estimada 3 horas adicionales.");
        _checkpoint(PK_CARRIER2, id,
            "Barranquilla - Norte", LogisticsTracking.CheckpointType.Transit,
            "Continuando ruta. Danos documentados.", NO_TEMP);

        console.log("  -> Envio #", id, "| InTransit | 1 Damage + 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 10 — Vacunas pediatricas | TempViolation + Unauthorized | OutForDelivery
    // =========================================================================
    function _escenario10() internal {
        console.log("[E10] Vacunas pediatricas - TempViolation + Unauthorized");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT3,
            "Vacunas pentavalentes pediatricas (300 dosis)", "Bogota", "Bogota", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "ICBF Deposito Norte", LogisticsTracking.CheckpointType.Pickup,
            "Sellado y temperatura verificada.", 45);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Zona Industrial Bogota", LogisticsTracking.CheckpointType.Transit,
            "Vehiculo expuesto al sol durante carga cruzada. Temperatura elevada.", 250);
        _assignInspector(id);
        _incident(PK_INSPECTOR1, id, LogisticsTracking.IncidentType.Unauthorized,
            "Precinto del lote 12 retirado sin autorizacion durante trasbordo en zona industrial.");
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.OutForDelivery);

        console.log("  -> Envio #", id, "| OutForDelivery | 1 TempViolation + 1 Unauthorized");
    }

    // =========================================================================
    // ESCENARIO 11 — Marcapasos | ruta larga multi-checkpoint | OutForDelivery
    // =========================================================================
    function _escenario11() internal {
        console.log("[E11] Marcapasos cardiacos - ruta larga multi-checkpoint");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT1,
            "Marcapasos cardiacos (10 unidades)", "Bogota", "Cali", false);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Importadora Medica Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Dispositivos verificados y embalados.", NO_TEMP);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);

        string[5] memory lugares = ["Soacha", "Fusagasuga", "Girardot", "Espinal", "Ibague"];
        for (uint i = 0; i < lugares.length; i++) {
            _checkpoint(PK_CARRIER1, id,
                lugares[i], LogisticsTracking.CheckpointType.Transit,
                "Control de ruta sin novedad.", NO_TEMP);
        }

        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Armenia", LogisticsTracking.CheckpointType.Hub,
            "Transito por hub.", NO_TEMP);
        _status(PK_HUB1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Buga", LogisticsTracking.CheckpointType.Transit,
            "Ultimas horas de viaje.", NO_TEMP);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.OutForDelivery);

        console.log("  -> Envio #", id, "| OutForDelivery | 8 checkpoints | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 12 — Bebidas gaseosas | Lost + Delay | InTransit
    // =========================================================================
    function _escenario12() internal {
        console.log("[E12] Bebidas gaseosas - Lost + Delay");
        vm.startBroadcast(PK_SENDER2);
        uint256 id = lt.createShipment(RECIPIENT4,
            "Gaseosas Postobon surtidas (600 unidades)", "Medellin", "Barranquilla", false);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER2, id,
            "Planta Postobon Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Carga completa verificada: 600 unidades.", NO_TEMP);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER2, id,
            "Valledupar - Parque industrial", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", NO_TEMP);
        _incident(PK_CARRIER2, id, LogisticsTracking.IncidentType.Lost,
            "Pale #3 (150 unidades) no localizado tras transbordo nocturno en Valledupar.");
        _incident(PK_CARRIER2, id, LogisticsTracking.IncidentType.Delay,
            "Busqueda del pale perdido genera retraso de 8 horas en la ruta.");
        _checkpoint(PK_CARRIER2, id,
            "Barranquilla - Av. Circunvalar", LogisticsTracking.CheckpointType.Transit,
            "Continua ruta con carga parcial.", NO_TEMP);

        console.log("  -> Envio #", id, "| InTransit | 1 Lost + 1 Delay");
    }

    // =========================================================================
    // ESCENARIO 13 — Material quirurgico | TempViolation leve + Damage | AtHub
    // =========================================================================
    function _escenario13() internal {
        console.log("[E13] Material quirurgico - TempViolation leve + Damage");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT5,
            "Suturas y material quirurgico esteril (50 cajas)", "Bogota", "Manizales", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Proveedor Medico Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Material esteril sellado y verificado.", 30);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Honda", LogisticsTracking.CheckpointType.Transit,
            "Temperatura normal.", 35);
        _checkpoint(PK_CARRIER1, id,
            "La Dorada - Carga compartida", LogisticsTracking.CheckpointType.Transit,
            "Temperatura subio levemente por apertura de compuerta durante carga cruzada.", 90);
        _incident(PK_CARRIER1, id, LogisticsTracking.IncidentType.Damage,
            "Humedad exterior dano el embalaje de carton de 12 cajas. Contenido intacto.");
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.AtHub);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Manizales - Recepcion", LogisticsTracking.CheckpointType.Hub,
            "Revision de empaques en curso.", 28);

        console.log("  -> Envio #", id, "| AtHub | 1 TempViolation + 1 Damage");
    }

    // =========================================================================
    // ESCENARIO 14 — Somatropina | inspector valida | 0 incidencias | OutForDelivery
    // =========================================================================
    function _escenario14() internal {
        console.log("[E14] Somatropina - inspector INVIMA valida cadena de frio");
        vm.startBroadcast(PK_SENDER1);
        uint256 id = lt.createShipment(RECIPIENT3,
            "Hormona de crecimiento somatropina (20 viales)", "Bogota", "Bogota Norte", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER1, id,
            "Laboratorio Hormonal - Bogota", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura verificada al inicio.", 45);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER1, id,
            "Autopista Norte Km 15", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", 42);
        _checkpoint(PK_CARRIER1, id,
            "Centro de acopio Norte", LogisticsTracking.CheckpointType.Transit,
            "Temperatura estable.", 40);
        _assignInspector(id);
        _checkpoint(PK_INSPECTOR1, id,
            "Puesto de inspeccion - Usaquen", LogisticsTracking.CheckpointType.Other,
            "Inspeccion INVIMA: Temperatura 4.0C, empaques integros, cadena de frio cumplida.", 40);
        _status(PK_CARRIER1, id, LogisticsTracking.ShipmentStatus.OutForDelivery);

        console.log("  -> Envio #", id, "| OutForDelivery | inspector activo | 0 incidencias");
    }

    // =========================================================================
    // ESCENARIO 15 — Helados | 3 TempViolation + Damage + Delay | AtHub
    // =========================================================================
    function _escenario15() internal {
        console.log("[E15] Helados artesanales - caso critico multi-incidencia");
        vm.startBroadcast(PK_SENDER2);
        uint256 id = lt.createShipment(RECIPIENT2,
            "Helados artesanales premium (800 unidades)", "Medellin", "Pereira", true);
        vm.stopBroadcast();

        _assignAndCheckpoint(PK_CARRIER2, id,
            "Heladeria Premium - Planta Medellin", LogisticsTracking.CheckpointType.Pickup,
            "Temperatura correcta -18C externa. Cadena de frio activa.", 20);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.InTransit);
        _checkpoint(PK_CARRIER2, id,
            "Caldas - Sur de Medellin", LogisticsTracking.CheckpointType.Transit,
            "Sin novedad.", 22);
        _checkpoint(PK_CARRIER2, id,
            "La Pintada - Estacion de servicio", LogisticsTracking.CheckpointType.Transit,
            "Corte de energia 15 min. Temperatura sube.", 100);
        _checkpoint(PK_CARRIER2, id,
            "Supia", LogisticsTracking.CheckpointType.Transit,
            "Temperatura bajando.", 75);
        _checkpoint(PK_CARRIER2, id,
            "Riosucio - Trancon", LogisticsTracking.CheckpointType.Transit,
            "Trancon de 2h. Sistema de refrigeracion al limite.", 150);
        _status(PK_CARRIER2, id, LogisticsTracking.ShipmentStatus.AtHub);
        _assign(PK_HUB1, id);
        _checkpoint(PK_HUB1, id,
            "Hub Pereira - Verificacion de llegada", LogisticsTracking.CheckpointType.Hub,
            "Temperatura al llegar: 12C. Cadena de frio comprometida.", 120);
        _incident(PK_HUB1, id, LogisticsTracking.IncidentType.Damage,
            "Helados derretidos parcialmente. Estimado 40% del lote comprometido.");
        _incident(PK_HUB1, id, LogisticsTracking.IncidentType.Delay,
            "Lote retenido 24h por evaluacion de inocuidad alimentaria.");
        _assignInspector(id);
        _checkpoint(PK_INSPECTOR1, id,
            "Hub Pereira - Laboratorio", LogisticsTracking.CheckpointType.Other,
            "Muestras tomadas. Resultado pendiente. Envio retenido en hub.", NO_TEMP);

        console.log("  -> Envio #", id, "| AtHub | 3 TempViolation + 1 Damage + 1 Delay");
    }
}
