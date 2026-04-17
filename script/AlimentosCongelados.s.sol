// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {LogisticsTracking} from "../src/LogisticsTracking.sol";

/**
 * @title AlimentosCongelados
 * @notice Script de prueba: Envio de alimentos congelados Bogota -> Cali.
 *
 * Cadena de frio requerida: -18 °C a -15 °C (almacenada * 10 = -180 a -150)
 * El contrato LogisticsTracking valida entre COLD_CHAIN_TEMP_MIN=20 y COLD_CHAIN_TEMP_MAX=80
 * (2.0°C y 8.0°C), por lo que temperaturas negativas de congelados SIEMPRE
 * generaran TempViolation. Para demostrar el flujo sin incidencias se usan
 * temperaturas dentro del rango del contrato (-2°C simulado como 20 en el contrato).
 *
 * ACTORES (reutiliza los de Anvil, registrar previamente con SetupDemo o manualmente):
 *   Admin     0xf39F...2266  (cuenta 0)
 *   Sender    0x7099...79C8  (cuenta 1) — Frigorificos Del Valle
 *   Carrier   0x3C44...93BC  (cuenta 2) — Transportes FrioCargo
 *   Hub Bog   0x90F7...b906  (cuenta 3) — Hub Bogota Puente Aranda
 *   Hub Cali  0x14dC...9955  (cuenta 7) — Hub Cali Acopi
 *   Recipient 0x15d3...A65   (cuenta 4) — Supermercado La 14 Cali
 *
 * Uso:
 *   forge script script/AlimentosCongelados.s.sol \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 *
 * El script registra actores nuevos (si no existen), crea el envio y
 * registra 6 checkpoints con 2 cambios de estado.
 */
contract AlimentosCongelados is Script {
    address constant CONTRACT_ADDR = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    // Direcciones Anvil
    address constant ADMIN = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant SENDER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant CARRIER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant HUB_BOG = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant HUB_CALI = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    address constant RECIPIENT = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;

    // Claves privadas Anvil
    uint256 constant PK_ADMIN = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant PK_SENDER = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant PK_CARRIER = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant PK_HUB_BOG = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 constant PK_HUB_CALI = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;

    // Temperaturas (almacenadas * 10, rango valido del contrato: 20 a 80)
    // Para alimentos congelados usamos el limite inferior 20 (2.0 C)
    // NOTA: en produccion real se necesitaria modificar el contrato para
    //       soportar rangos negativos de congelacion.
    int256 constant T_PICKUP = 20; // 2.0 C — limite inferior cadena frio
    int256 constant T_HUB_BOG = 22; // 2.2 C
    int256 constant T_TRANSIT1 = 25; // 2.5 C — en transito carretera
    int256 constant T_HUB_CALI = 21; // 2.1 C
    int256 constant T_TRANSIT2 = 24; // 2.4 C — ultima milla
    int256 constant T_DELIVERY = 23; // 2.3 C — entrega OK

    function run() external {
        LogisticsTracking lt = LogisticsTracking(CONTRACT_ADDR);

        console.log("=== ENVIO ALIMENTOS CONGELADOS: Bogota -> Cali ===");
        console.log("");

        // =====================================================================
        // 1. REGISTRAR ACTORES (solo si no existen)
        // =====================================================================
        vm.startBroadcast(PK_ADMIN);

        if (!lt.getActor(SENDER).isActive) {
            lt.registerActor("Frigorificos Del Valle", LogisticsTracking.ActorRole.Sender, "Bogota", SENDER);
            console.log("Actor registrado: Frigorificos Del Valle (Sender)");
        } else {
            console.log("Sender ya existe: Frigorificos Del Valle");
        }

        if (!lt.getActor(CARRIER).isActive) {
            lt.registerActor("Transportes FrioCargo", LogisticsTracking.ActorRole.Carrier, "Bogota", CARRIER);
            console.log("Actor registrado: Transportes FrioCargo (Carrier)");
        } else {
            console.log("Carrier ya existe: Transportes FrioCargo");
        }

        if (!lt.getActor(HUB_BOG).isActive) {
            lt.registerActor("Hub Bogota Puente Aranda", LogisticsTracking.ActorRole.Hub, "Bogota", HUB_BOG);
            console.log("Actor registrado: Hub Bogota Puente Aranda (Hub)");
        } else {
            console.log("Hub Bogota ya existe");
        }

        if (!lt.getActor(HUB_CALI).isActive) {
            lt.registerActor("Hub Cali Acopi", LogisticsTracking.ActorRole.Hub, "Cali", HUB_CALI);
            console.log("Actor registrado: Hub Cali Acopi (Hub)");
        } else {
            console.log("Hub Cali ya existe");
        }

        if (!lt.getActor(RECIPIENT).isActive) {
            lt.registerActor("Supermercado La 14 Cali", LogisticsTracking.ActorRole.Recipient, "Cali", RECIPIENT);
            console.log("Actor registrado: Supermercado La 14 Cali (Recipient)");
        } else {
            console.log("Recipient ya existe: Supermercado La 14 Cali");
        }

        vm.stopBroadcast();
        console.log("");

        // =====================================================================
        // 2. CREAR ENVIO (Sender)
        // =====================================================================
        vm.startBroadcast(PK_SENDER);
        uint256 sid = lt.createShipment(
            RECIPIENT,
            "Pollo congelado IQF - Lote PC-2024-311 - 800 kg",
            "Bogota",
            "Cali",
            true // requiresColdChain = true
        );
        console.log("Envio creado - ID:", sid);
        console.log("Producto: Pollo congelado IQF - Lote PC-2024-311 - 800 kg");
        console.log("Ruta: Bogota -> Cali | Cadena de frio: SI");
        console.log("");
        vm.stopBroadcast();

        // =====================================================================
        // CP1: Pickup en frigorifico origen — Sender
        // =====================================================================
        vm.startBroadcast(PK_SENDER);
        uint256 cp1 = lt.recordCheckpoint(
            sid,
            "Frigorificos Del Valle - Bogota, Zona Industrial Montevideo",
            LogisticsTracking.CheckpointType.Pickup,
            "Lote: PC-2024-311 | 800 kg pollo IQF | Temp camara: -18C | Embalaje: 40 cajas OK | Precinto: FR-001 | Resp: H. Sanchez",
            T_PICKUP
        );
        console.log("CP1 Pickup registrado - ID:", cp1, "| Temp: 2.0C");
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Hub Bogota
        // =====================================================================
        vm.startBroadcast(PK_HUB_BOG);
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        console.log("Hub Bogota asignado al envio -> InTransit");
        vm.stopBroadcast();

        // =====================================================================
        // CP2: Ingreso Hub Bogota — Hub Bogota
        // =====================================================================
        vm.startBroadcast(PK_HUB_BOG);
        uint256 cp2 = lt.recordCheckpoint(
            sid,
            "Hub Bogota Puente Aranda - Anden de Recepcion",
            LogisticsTracking.CheckpointType.Hub,
            "Llegada: 09:20 | 40/40 cajas integras | Precinto FR-001: OK | Temp bodega: -18C | Asignado: Camion TRK-551 | Resp: P. Morales",
            T_HUB_BOG
        );
        console.log("CP2 Hub Bogota registrado - ID:", cp2, "| Temp: 2.2C");
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Carrier + cambio estado InTransit
        // =====================================================================
        vm.startBroadcast(PK_CARRIER);
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        console.log("Carrier asignado al envio -> InTransit");
        vm.stopBroadcast();

        // =====================================================================
        // CP3: En transito Bogota-Cali — Carrier
        // =====================================================================
        vm.startBroadcast(PK_CARRIER);
        uint256 cp3 = lt.recordCheckpoint(
            sid,
            "Autopista Bogota-Cali, km 198 - Alto de La Linea",
            LogisticsTracking.CheckpointType.Transit,
            "Hora: 13:45 | Placa: TRK-551 | Conductor: M. Lopez | Precinto FR-001: OK | Temp exterior: 15C | Temp carga: -17C",
            T_TRANSIT1
        );
        console.log("CP3 Transit Bogota-Cali registrado - ID:", cp3, "| Temp: 2.5C");
        vm.stopBroadcast();

        // =====================================================================
        // Asignar Hub Cali
        // =====================================================================
        vm.startBroadcast(PK_HUB_CALI);
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        console.log("Hub Cali asignado al envio -> AtHub");
        vm.stopBroadcast();

        // =====================================================================
        // CP4: Arribo Hub Cali — Hub Cali
        // =====================================================================
        vm.startBroadcast(PK_HUB_CALI);
        uint256 cp4 = lt.recordCheckpoint(
            sid,
            "Hub Cali Acopi - Recepcion Frigorifico",
            LogisticsTracking.CheckpointType.Hub,
            "Llegada: 17:30 | 40/40 cajas OK | Precinto FR-001: integro | Temp camara Acopi: -19C | Peso verificado: 800 kg | Resp: C. Valencia",
            T_HUB_CALI
        );
        console.log("CP4 Hub Cali registrado - ID:", cp4, "| Temp: 2.1C | Estado: AtHub");
        vm.stopBroadcast();

        // =====================================================================
        // CP5: Salida hacia entrega — Carrier, cambio a OutForDelivery
        // =====================================================================
        vm.startBroadcast(PK_CARRIER);
        uint256 cp5 = lt.recordCheckpoint(
            sid,
            "Hub Cali Acopi - Bahia de Despacho",
            LogisticsTracking.CheckpointType.Transit,
            "Salida: 07:15 | Veh: VAN-FRIO-22 | Conductor: R. Castillo | Precinto nuevo: FR-002 | 40 cajas | ETA Supermercado: 09:00",
            T_TRANSIT2
        );
        lt.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.OutForDelivery);
        console.log("CP5 Salida ultima milla registrado - ID:", cp5, "| Temp: 2.4C | Estado: OutForDelivery");
        vm.stopBroadcast();

        // =====================================================================
        // CP6: Entrega al Supermercado — Carrier
        // =====================================================================
        vm.startBroadcast(PK_CARRIER);
        uint256 cp6 = lt.recordCheckpoint(
            sid,
            "Supermercado La 14 Cali - Recepcion Carnes y Congelados, Av. 6N #28-00",
            LogisticsTracking.CheckpointType.Delivery,
            "Recibe: Jefe bodega J. Restrepo | 40/40 cajas OK | Precinto FR-002: integro | Temp recepcion: -17C | Acta: REC-CON-2024-089",
            T_DELIVERY
        );
        console.log("CP6 Entrega registrada - ID:", cp6, "| Temp: 2.3C");
        vm.stopBroadcast();

        // =====================================================================
        // RESUMEN FINAL
        // =====================================================================
        console.log("");
        console.log("=== FLUJO COMPLETADO ===");
        console.log("Envio ID          :", sid);
        console.log("Estado actual     : OutForDelivery");
        console.log("CP1 Pickup        :", cp1, "| 2.0C | Sender");
        console.log("CP2 Hub Bogota    :", cp2, "| 2.2C | Hub Bogota -> InTransit");
        console.log("CP3 Transit       :", cp3, "| 2.5C | Carrier");
        console.log("CP4 Hub Cali      :", cp4, "| 2.1C | Hub Cali -> AtHub");
        console.log("CP5 Ultima milla  :", cp5, "| 2.4C | Carrier -> OutForDelivery");
        console.log("CP6 Entrega       :", cp6, "| 2.3C | Carrier");
        console.log("");
        console.log("Confirmar entrega desde el frontend con la cuenta Recipient:");
        console.log("0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65");
    }
}
