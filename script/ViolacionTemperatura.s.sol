// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import "../src/LogisticsTracking.sol";

/**
 * @title ViolacionTemperatura
 * @notice Script de demostracion: envio de vacunas con 2 violaciones de
 *         temperatura deliberadas para mostrar los avisos TempViolation.
 *
 * Limites del contrato:
 *   COLD_CHAIN_TEMP_MIN = 20  (2.0 C)
 *   COLD_CHAIN_TEMP_MAX = 80  (8.0 C)
 *
 * Violaciones incluidas:
 *   CP3 - temperatura 95 (9.5 C) -> supera el maximo -> TempViolation
 *   CP5 - temperatura 12 (1.2 C) -> bajo el minimo  -> TempViolation
 *
 * PRE-REQUISITO: Actores ya registrados (SetupDemo o registrados manualmente).
 *
 * Uso:
 *   forge script script/ViolacionTemperatura.s.sol \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 */
contract ViolacionTemperatura is Script {
    address constant CONTRACT_ADDR = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    address constant SENDER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant CARRIER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant HUB_BOG = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant HUB_MED = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    address constant RECIPIENT = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;

    uint256 constant PK_SENDER = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant PK_CARRIER = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant PK_HUB_BOG = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 constant PK_HUB_MED = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;

    function run() external {
        LogisticsTracking lt = LogisticsTracking(CONTRACT_ADDR);

        console.log("=== DEMO VIOLACION DE TEMPERATURA ===");
        console.log("Rango valido cadena frio: 2.0 C a 8.0 C");
        console.log("Violacion CP3: 9.5 C (supera maximo 8.0 C)");
        console.log("Violacion CP5: 1.2 C (bajo minimo 2.0 C)");
        console.log("");

        // =====================================================================
        // CREAR ENVIO (Sender)
        // =====================================================================
        vm.startBroadcast(PK_SENDER);
        uint256 sid = lt.createShipment(
            RECIPIENT, "Insulina Refrigerada - Lote INS-2024-077 - 200 unidades", "Bogota", "Medellin", true
        );
        console.log("Envio creado - ID:", sid);
        console.log("Producto: Insulina Refrigerada - Lote INS-2024-077");
        console.log("Cadena de frio: SI | Ruta: Bogota -> Medellin");
        console.log("");
        vm.stopBroadcast();

        // =====================================================================
        // CP1: Pickup — temperatura OK (4.5 C)
        // =====================================================================
        vm.startBroadcast(PK_SENDER);
        uint256 cp1 = lt.recordCheckpoint(
            sid,
            "Laboratorio BioPharma - Bogota, Zona Industrial",
            LogisticsTracking.CheckpointType.Pickup,
            "Lote INS-2024-077 | 200 unidades | Temp camara origen: 4.2C | Embalaje termico OK | Resp: J. Martinez",
            45 // 4.5 C — dentro del rango OK
        );
        console.log("CP1 Pickup OK - ID:", cp1, "| Temp: 4.5 C | SIN violacion");
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Hub Bogota
        // =====================================================================
        vm.startBroadcast(PK_HUB_BOG);
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        console.log("Hub Bogota asignado -> InTransit");
        vm.stopBroadcast();

        // =====================================================================
        // CP2: Hub Bogota — temperatura OK (3.8 C)
        // =====================================================================
        vm.startBroadcast(PK_HUB_BOG);
        uint256 cp2 = lt.recordCheckpoint(
            sid,
            "Hub Bogota Fontibon - Zona de Recepcion",
            LogisticsTracking.CheckpointType.Hub,
            "Llegada: 11:10 | Embalaje termico: OK | Temp bodega fria: 3.5C | 200/200 unidades | Resp: C. Torres",
            38 // 3.8 C — dentro del rango OK
        );
        console.log("CP2 Hub Bogota OK - ID:", cp2, "| Temp: 3.8 C | SIN violacion");
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Carrier
        // =====================================================================
        vm.startBroadcast(PK_CARRIER);
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        console.log("Carrier asignado -> InTransit");
        vm.stopBroadcast();

        // =====================================================================
        // CP3: Control en ruta — VIOLACION #1: 9.5 C (supera maximo 8.0 C)
        // Causa: puerta del frigorifico abierta durante parada no autorizada
        // =====================================================================
        console.log("");
        console.log(">>> VIOLACION #1 esperada en CP3: 9.5 C > 8.0 C maximo <<<");
        vm.startBroadcast(PK_CARRIER);
        uint256 cp3 = lt.recordCheckpoint(
            sid,
            "Autopista Bogota-Medellin, km 87 - Estacion de Servicio El Sisga",
            LogisticsTracking.CheckpointType.Transit,
            "ALERTA: Temperatura elevada | Parada no autorizada 25 min | Puerta abierta detectada | Precinto SP-771: OK | Conductor: R. Gomez",
            95 // 9.5 C — SUPERA MAXIMO (80) -> TempViolation automatica
        );
        console.log("CP3 Transit - ID:", cp3, "| Temp: 9.5 C | *** INCIDENTE TempViolation generado ***");
        vm.stopBroadcast();

        // =====================================================================
        // CP4: Control posterior — temperatura recuperada (5.0 C)
        // =====================================================================
        vm.startBroadcast(PK_CARRIER);
        uint256 cp4 = lt.recordCheckpoint(
            sid,
            "Autopista Bogota-Medellin, km 142 - Peaje La Ye",
            LogisticsTracking.CheckpointType.Transit,
            "Temperatura recuperada tras incidente | Equipo de frio reactivado | Precinto SP-771: OK | 200 unidades",
            50 // 5.0 C — vuelve al rango OK
        );
        console.log("CP4 Transit OK - ID:", cp4, "| Temp: 5.0 C | Temperatura recuperada");
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Hub Medellin
        // =====================================================================
        vm.startBroadcast(PK_HUB_MED);
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        console.log("Hub Medellin asignado -> AtHub");
        vm.stopBroadcast();

        // =====================================================================
        // CP5: Hub Medellin — VIOLACION #2: 1.2 C (bajo minimo 2.0 C)
        // Causa: falla en termostato del almacen frigorifico del hub
        // =====================================================================
        console.log("");
        console.log(">>> VIOLACION #2 esperada en CP5: 1.2 C < 2.0 C minimo <<<");
        vm.startBroadcast(PK_HUB_MED);
        uint256 cp5 = lt.recordCheckpoint(
            sid,
            "Hub Medellin Itagui - Camara Fria C2",
            LogisticsTracking.CheckpointType.Hub,
            "ALERTA: Temperatura bajo minimo | Falla termostato camara C2 | Producto trasladado a camara C3 | Resp: A. Rios | Mantenimiento notificado",
            12 // 1.2 C — BAJO MINIMO (20) -> TempViolation automatica
        );
        console.log("CP5 Hub Medellin - ID:", cp5, "| Temp: 1.2 C | *** INCIDENTE TempViolation generado ***");
        vm.stopBroadcast();

        // =====================================================================
        // CP6: Salida hacia entrega — temperatura normalizada (4.2 C)
        // =====================================================================
        vm.startBroadcast(PK_CARRIER);
        uint256 cp6 = lt.recordCheckpoint(
            sid,
            "Hub Medellin Itagui - Bahia 4",
            LogisticsTracking.CheckpointType.Transit,
            "Temperatura normalizada | Camara C3: 4.0C | Veh: VAN-291 | Precinto nuevo: SP-882 | 200 unidades | ETA: 09:30",
            42 // 4.2 C — dentro del rango OK
        );
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("CP6 Salida ultima milla OK - ID:", cp6, "| Temp: 4.2 C | Estado: OutForDelivery");
        vm.stopBroadcast();

        // =====================================================================
        // RESUMEN
        // =====================================================================
        console.log("");
        console.log("=== RESUMEN DEMO VIOLACION DE TEMPERATURA ===");
        console.log("Envio ID     :", sid);
        console.log("Estado actual: OutForDelivery");
        console.log("");
        console.log("CP1 Pickup   :", cp1, "| 4.5 C | OK");
        console.log("CP2 Hub Bog  :", cp2, "| 3.8 C | OK");
        console.log("CP3 Transit  :", cp3, "| 9.5 C | *** VIOLACION #1: supera maximo 8.0 C ***");
        console.log("CP4 Transit  :", cp4, "| 5.0 C | OK - temperatura recuperada");
        console.log("CP5 Hub Med  :", cp5, "| 1.2 C | *** VIOLACION #2: bajo minimo 2.0 C ***");
        console.log("CP6 Transit  :", cp6, "| 4.2 C | OK - temperatura normalizada");
        console.log("");
        console.log("Incidentes TempViolation generados: 2");
        console.log("Verificar en Trazabilidad con ID:", sid);
        console.log("Confirmar entrega desde el frontend con cuenta Recipient:");
        console.log("0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65");
    }
}
