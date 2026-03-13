// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "lib/forge-std/src/Script.sol";
import "../src/LogisticsTracking.sol";

contract DeployLogistics is Script {
    function run() external {
        // Recuperar la clave privada de las variables de entorno
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Iniciar la transmisión de transacciones a la red
        vm.startBroadcast(deployerPrivateKey);

        // Desplegar el contrato
        LogisticsTracking logistics = new LogisticsTracking();

        // (Opcional) Configuración inicial, como registrar al administrador
        // logistics.registerActor(0x..., "Admin", "Admin");

        vm.stopBroadcast();
        
        console.log("Contrato desplegado en:", address(logistics));
    }
}