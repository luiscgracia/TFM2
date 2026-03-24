const fs = require('fs');
const path = require('path');

// 1. Ruta al archivo de broadcast de Foundry (ajusta el nombre de tu script de despliegue)
const BROADCAST_PATH = path.join(__dirname, 'broadcast/DeployLogistics.s.sol/31337/run-latest.json');

try {
  const data = JSON.parse(fs.readFileSync(BROADCAST_PATH, 'utf8'));
  
  // 2. Buscar la transacción de creación del contrato
  const contractAddress = data.transactions.find(
    tx => tx.transactionType === "CREATE" || tx.contractName === "LogisticsTracking"
  ).contractAddress;

  // 3. Escribir en el archivo .env de la raíz
  const envContent = `VITE_CONTRACT_ADDRESS=${contractAddress}\n`;
  fs.writeFileSync(path.join(__dirname, '.env'), envContent);

  console.log(`✅ Sincronizado: Contrato detectado en ${contractAddress}`);
} catch (error) {
  console.error("❌ Error al sincronizar el contrato:", error.message);
}
