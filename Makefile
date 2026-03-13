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

# Ejecutar todos los tests con reporte de gas
test :; forge test --gas-report

# Desplegar en Anvil (Local)
deploy-local :
	@forge script script/DeployLogistics.s.sol:DeployLogistics \
	--rpc-url $(ANVIL_RPC) \
	--private-key $(ANVIL_PK) \
	--broadcast -vvvv

# Desplegar en Sepolia (Requiere .env con RPC_URL, PRIVATE_KEY y ETHERSCAN_API_KEY)
deploy-sepolia :
	@forge script script/DeployLogistics.s.sol:DeployLogistics \
	--rpc-url $(RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvvv

# Limpiar los artefactos de compilación
clean :; forge clean