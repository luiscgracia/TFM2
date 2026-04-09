all    :; dapp build
clean  :; dapp clean
test   :; dapp test
deploy :; dapp create Tfm2

# Incluye las variables del archivo .env
-include .env

.PHONY: all test clean deploy-anvil deploy-sepolia

# --- Variables predeterminadas para Anvil ---
ANVIL_RPC := http://127.0.0.1:8545
# Esta es la Private Key #0 por defecto de Anvil
ANVIL_PK := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --- Comandos ---

# Compilar el proyecto
build :; forge build

# Limpiar los artefactos de compilación
clean :; forge clean

# Ejecutar todos los tests con reporte de gas
test :; forge test --gas-report

# Desplegar en Anvil (Local)
deploy :
	@forge script script/DeployLogistics.s.sol:DeployLogistics \
	--rpc-url $(ANVIL_RPC) \
	--private-key $(ANVIL_PK) \
	--broadcast -vvvv

# --------------------------------------------------------------------------------------------------------------------------------------

# Desplegar en Sepolia (Requiere .env con RPC_URL, PRIVATE_KEY y ETHERSCAN_API_KEY)
deploy-sepolia :
	@forge script script/DeployLogistics.s.sol:DeployLogistics \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvvv

# --------------------------------------------------------------------------------------------------------------------------------------

# Desplegar script para cargar los actores y generar un evío de prueba
act-env :
	forge script script/SetupDemo.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --------------------------------------------------------------------------------------------------------------------------------------

# Desplegar script para cargar los checkpoints en el envio de prueba
chkpnt :
	forge script script/CheckpointsDemo.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--sig "run(uint256)" 1

# --------------------------------------------------------------------------------------------------------------------------------------

# Desplegar script para otro envio de prueba (se registran actores si no existen, se crea el envio y los checkpoints, se confirma la entrega
envio2 :
	forge script script/AlimentosCongelados.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --------------------------------------------------------------------------------------------------------------------------------------

# Desplegar script para envio de insulina con 2 violaciones de temperatura
insulina :
	forge script script/ViolacionTemperatura.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --------------------------------------------------------------------------------------------------------------------------------------

# setup para entregar a CodeCrypto
iniciar :
	# hago el despliegue local en anvil
	@forge script script/DeployLogistics.s.sol:DeployLogistics \
	--rpc-url $(ANVIL_RPC) \
	--private-key $(ANVIL_PK) \
	--broadcast -vvvv \

	# creo actores y genero el envio 1
	forge script script/SetupDemo.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \

	# creo los checkpoints del envio 1
	forge script script/CheckpointsDemo.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--sig "run(uint256)" 1 \

	# creo el envio 2 con los checkpoint correspondientes
	forge script script/AlimentosCongelados.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \

	# creo el envio 3 (insulina) con los checkpoints que muestran violación de temperatura (incidentes)
	forge script script/ViolacionTemperatura.s.sol \
	--rpc-url http://127.0.0.1:8545 \
	--broadcast \
	--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# --------------------------------------------------------------------------------------------------------------------------------------

# 15 envios de ejemplo
Demo15Shipments :
	# 1. Deploy del contrato (siempre en 0x5FbDB2315678afecb367f032d93F642f64180aa3)
	@forge script script/DeployLogistics.s.sol:DeployLogistics \
	--rpc-url $(ANVIL_RPC) \
	--private-key $(ANVIL_PK) \
	--broadcast -vvvv

	# 2. Seed: registra actores y carga los 15 envios
	forge script script/Demo15Shipments.s.sol \
	--rpc-url $(ANVIL_RPC) \
	--private-key $(ANVIL_PK) \
	--broadcast \
	--slow

# --------------------------------------------------------------------------------------------------------------------------------------


