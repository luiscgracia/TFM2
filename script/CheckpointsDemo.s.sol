// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import "../src/LogisticsTracking.sol";

/**
 * @title CheckpointsDemo
 * @notice Script de Foundry que registra los 7 checkpoints del demo
 *         de vacunas Bogota -> Medellin, incluyendo los 3 cambios de estado.
 *
 * PRE-REQUISITO: Haber ejecutado SetupDemo.s.sol primero.
 *
 * Uso:
 *   forge script script/CheckpointsDemo.s.sol \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     --sig "run(uint256)" 1
 *
 * NOTA: El contrato [C-2] requiere que cada actor llame updateShipmentStatus
 *       antes de poder registrar checkpoints o incidencias. Esto los registra
 *       en _actorHasShipment. Solo Carrier y Hub pueden llamar esta funcion.
 */
contract CheckpointsDemo is Script {
    address constant CONTRACT_ADDR = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    // Claves privadas de Anvil (cuentas 1-4)
    uint256 constant PK_SENDER = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant PK_CARRIER = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant PK_HUB_BOG = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 constant PK_HUB_MED = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;

    function run(uint256 shipmentId) external {
        LogisticsTracking lt = LogisticsTracking(CONTRACT_ADDR);

        console.log("=== INICIANDO REGISTRO DE 7 CHECKPOINTS ===");
        console.log("Envio ID:", shipmentId);
        console.log("");

        // Verificar actores antes de empezar
        _verificarActores(lt);

        // =====================================================================
        // CP1: Pickup — Sender (ya asignado al crear el envio)
        // =====================================================================
        console.log("--- CP1: Pickup (Sender) ---");
        vm.startBroadcast(PK_SENDER);
        uint256 cp1 = lt.recordCheckpoint(
            shipmentId,
            "Laboratorio BioPharma - Bogota, Zona Industrial",
            LogisticsTracking.CheckpointType.Pickup,
            "Lote: VX-2024-089 | Venc: 2025-08 | 500 dosis | Embalaje integro | Resp: J. Martinez",
            45
        );
        console.log("CP1 registrado, ID:", cp1);
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Hub Bogota: usa InTransit para no retroceder estado
        // =====================================================================
        console.log("--- Asignando Hub Bogota al envio ---");
        vm.startBroadcast(PK_HUB_BOG);
        lt.updateShipmentStatus(shipmentId, LogisticsTracking.ShipmentStatus.InTransit);
        console.log("Hub Bogota asignado, estado -> InTransit");
        vm.stopBroadcast();

        // =====================================================================
        // CP2: Hub Bogota Fontibon — Hub Bogota
        // =====================================================================
        console.log("--- CP2: Hub Bogota (Hub Bogota) ---");
        vm.startBroadcast(PK_HUB_BOG);
        uint256 cp2 = lt.recordCheckpoint(
            shipmentId,
            "Hub Bogota Fontibon - Recepcion",
            LogisticsTracking.CheckpointType.Hub,
            "Llegada: 10:35 | Embalaje: OK | 500/500 dosis | Veh: ABC-123 | Resp: C. Torres",
            38
        );
        console.log("CP2 registrado, ID:", cp2);
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Carrier al envio — ya queda estado InTransit
        // =====================================================================
        console.log("--- Asignando Carrier al envio ---");
        vm.startBroadcast(PK_CARRIER);
        lt.updateShipmentStatus(shipmentId, LogisticsTracking.ShipmentStatus.InTransit);
        console.log("Carrier asignado, estado -> InTransit");
        vm.stopBroadcast();

        // =====================================================================
        // CP3: Carga en transporte refrigerado — Carrier
        // =====================================================================
        console.log("--- CP3: Carga transporte (Carrier) ---");
        vm.startBroadcast(PK_CARRIER);
        uint256 cp3 = lt.recordCheckpoint(
            shipmentId,
            "Hub Bogota Fontibon - Muelle 3",
            LogisticsTracking.CheckpointType.Transit,
            "Placa: TRK-847 | Conductor: R. Gomez | Salida: 14:20 | Precinto: SP-4421 | ETA: 18:30",
            40
        );
        console.log("CP3 registrado, ID:", cp3, "Estado: InTransit");
        vm.stopBroadcast();

        // =====================================================================
        // CP4: Control en ruta — Carrier
        // =====================================================================
        console.log("--- CP4: Control en ruta (Carrier) ---");
        vm.startBroadcast(PK_CARRIER);
        uint256 cp4 = lt.recordCheckpoint(
            shipmentId,
            "Autopista Bogota-Medellin, km 142 - Peaje La Ye",
            LogisticsTracking.CheckpointType.Transit,
            "Hora: 16:45 | Precinto SP-4421: integro | Sin novedades | Temp exterior: 28C",
            52
        );
        console.log("CP4 registrado, ID:", cp4);
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Hub Medellin: usa AtHub
        // =====================================================================
        console.log("--- Asignando Hub Medellin al envio ---");
        vm.startBroadcast(PK_HUB_MED);
        lt.updateShipmentStatus(shipmentId, LogisticsTracking.ShipmentStatus.AtHub);
        console.log("Hub Medellin asignado, estado -> AtHub");
        vm.stopBroadcast();

        // =====================================================================
        // CP5: Arribo Hub Medellin — Hub Medellin
        // =====================================================================
        console.log("--- CP5: Hub Medellin (Hub Medellin) ---");
        vm.startBroadcast(PK_HUB_MED);
        uint256 cp5 = lt.recordCheckpoint(
            shipmentId,
            "Hub Medellin Itagui - Recepcion",
            LogisticsTracking.CheckpointType.Hub,
            "Llegada: 18:15 | Precinto SP-4421: integro | 500/500 dosis | Almacen R2: 3.8C | Resp: A. Rios",
            55
        );
        console.log("CP5 registrado, ID:", cp5, "Estado: AtHub");
        vm.stopBroadcast();

        // =====================================================================
        // CP6: Salida ultima milla — Carrier, cambio a OutForDelivery
        // =====================================================================
        console.log("--- CP6: Salida ultima milla (Carrier) ---");
        vm.startBroadcast(PK_CARRIER);
        uint256 cp6 = lt.recordCheckpoint(
            shipmentId,
            "Hub Medellin Itagui - Bahia 7",
            LogisticsTracking.CheckpointType.Transit,
            "Veh: VAN-291 | Repartidor: L. Perez | Salida: 08:10 | Precinto: SP-5530 | ETA: 09:00 | 500 dosis",
            50
        );
        lt.updateShipmentStatus(shipmentId, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("CP6 registrado, ID:", cp6, "Estado: OutForDelivery");
        vm.stopBroadcast();

        // =====================================================================
        // CP7: Entrega al destinatario — Carrier
        // =====================================================================
        console.log("--- CP7: Entrega destinatario (Carrier) ---");
        vm.startBroadcast(PK_CARRIER);
        uint256 cp7 = lt.recordCheckpoint(
            shipmentId,
            "Clinica San Rafael - Farmacia, Cr 45 #12-30, Medellin",
            LogisticsTracking.CheckpointType.Delivery,
            "Recibe: Dra. M. Castro | 500 dosis OK | Precinto SP-5530: integro | Acta: REC-2024-441",
            42
        );
        console.log("CP7 registrado, ID:", cp7);
        vm.stopBroadcast();

        // =====================================================================
        // RESUMEN FINAL
        // =====================================================================
        console.log("");
        console.log("=== 7 CHECKPOINTS COMPLETADOS ===");
        console.log("CP1 Pickup   :", cp1, "| 4.5C | Sender");
        console.log("CP2 Hub      :", cp2, "| 3.8C | Hub Bogota");
        console.log("CP3 Transit  :", cp3, "| 4.0C | Carrier -> InTransit");
        console.log("CP4 Transit  :", cp4, "| 5.2C | Carrier");
        console.log("CP5 Hub      :", cp5, "| 5.5C | Hub Medellin -> AtHub");
        console.log("CP6 Transit  :", cp6, "| 5.0C | Carrier -> OutForDelivery");
        console.log("CP7 Delivery :", cp7, "| 4.2C | Carrier");
        console.log("");
        console.log("Siguiente: Confirmar entrega desde cuenta Recipient");
        console.log("0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65");
    }

    function _verificarActores(LogisticsTracking lt) internal view {
        address sender = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address carrier = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        address hubBog = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
        address hubMed = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;

        require(lt.getActor(sender).isActive, "ERROR: Sender no esta activo. Ejecuta SetupDemo primero.");
        require(lt.getActor(carrier).isActive, "ERROR: Carrier no esta activo. Ejecuta SetupDemo primero.");
        require(lt.getActor(hubBog).isActive, "ERROR: Hub Bogota no esta activo. Ejecuta SetupDemo primero.");
        require(lt.getActor(hubMed).isActive, "ERROR: Hub Medellin no esta activo. Ejecuta SetupDemo primero.");

        console.log("Verificacion de actores: OK");
    }
}
