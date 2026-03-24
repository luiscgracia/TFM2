// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {Script, console} from "lib/forge-std/src/Script.sol";
import "../src/LogisticsTracking.sol";

contract DeployLogistics is Script {
    function run() external {
        // Recuperar la clave privada de las variables de entorno
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Iniciar la transmisión de transacciones a la red
        vm.startBroadcast(deployerPrivateKey);

        // Desplegar el contrato
        LogisticsTracking logistics = new LogisticsTracking();

        console.log("Contrato desplegado en:", address(logistics));

        vm.stopBroadcast();
    }
}
