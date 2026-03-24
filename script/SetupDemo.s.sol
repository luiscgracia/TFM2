// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "lib/forge-std/src/Script.sol";
import "../src/LogisticsTracking.sol";

/**
 * @title SetupDemo
 * @notice Script de Foundry que pre-carga todos los actores del demo
 *         y crea el envío de vacunas automáticamente.
 *
 * Uso:
 *   forge script script/SetupDemo.s.sol \
 *     --rpc-url http://127.0.0.1:8545 \
 *     --broadcast \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
 */
contract SetupDemo is Script {
    // Dirección del contrato desplegado — actualizar si cambia
    address constant CONTRACT_ADDR = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    // Cuentas de Anvil
    address constant ADMIN = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant SENDER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant CARRIER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant HUB_BOG = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant HUB_MED = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    address constant RECIPIENT = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;

    // Claves privadas de Anvil
    uint256 constant PK_ADMIN = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant PK_SENDER = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    function run() external {
        LogisticsTracking lt = LogisticsTracking(CONTRACT_ADDR);

        // ── 1. Registrar actores (desde admin) ──────────────────────────────
        vm.startBroadcast(PK_ADMIN);

        lt.registerActor("Laboratorio BioPharma", LogisticsTracking.ActorRole.Sender, "Bogota", SENDER);
        console.log("Actor 1 registrado: Laboratorio BioPharma (Sender)");

        lt.registerActor("Transportes FrioExpress", LogisticsTracking.ActorRole.Carrier, "Bogota", CARRIER);
        console.log("Actor 2 registrado: Transportes FrioExpress (Carrier)");

        lt.registerActor("Hub Bogota Fontibon", LogisticsTracking.ActorRole.Hub, "Bogota", HUB_BOG);
        console.log("Actor 3 registrado: Hub Bogota Fontibon (Hub)");

        lt.registerActor("Hub Medellin Itagui", LogisticsTracking.ActorRole.Hub, "Medellin", HUB_MED);
        console.log("Actor 4 registrado: Hub Medellin Itagui (Hub)");

        lt.registerActor("Clinica San Rafael", LogisticsTracking.ActorRole.Recipient, "Medellin", RECIPIENT);
        console.log("Actor 5 registrado: Clinica San Rafael (Recipient)");

        vm.stopBroadcast();

        // ── 2. Crear envío (desde sender) ───────────────────────────────────
        vm.startBroadcast(PK_SENDER);

        uint256 shipmentId = lt.createShipment(
            RECIPIENT,
            "Vacunas COVID-19 Lote VX-2024-089",
            "Bogota",
            "Medellin",
            true // requiresColdChain
        );

        console.log("Envio creado con ID:", shipmentId);
        console.log(unicode"ANOTA ESTE ID — lo necesitas para los checkpoints");

        vm.stopBroadcast();

        console.log("");
        console.log("=== SETUP COMPLETADO ===");
        console.log("5 actores registrados + 1 envio creado");
        console.log("ID del envio:", shipmentId);
        console.log("Continua con los 7 checkpoints desde el frontend");
    }
}
