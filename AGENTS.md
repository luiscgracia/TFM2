# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

**LOGICHAIN v4** — An on-chain logistics traceability system. The core is a Solidity smart contract (`LogisticsTracking.sol`) that tracks the full lifecycle of shipments (creation, checkpoints, incidents, cold-chain validation, delivery). There are two frontend apps:
- `logistics-frontend/` — The active UI (Vite + React + wagmi + TanStack Query), branded as "LOGICHAIN v4"
- `web/` — A Next.js 16 skeleton (mostly a placeholder; not yet wired to the contract)

## Commands

### Smart Contract (Foundry — run from repo root)

```bash
forge build                        # Compile contracts → out/
forge test                         # Run all 72 tests with gas report
forge test --match-test <name>     # Run a single test by name (e.g. testRegisterSender)
forge test -vvvv                   # Verbose output for debugging reverts
forge clean                        # Remove build artifacts
```

### Local deployment with Anvil

```bash
anvil                              # Start local EVM node on port 8545
make deploy                        # Deploy LogisticsTracking to Anvil
make iniciar                       # Full demo: deploy + register actors + create 3 demo shipments
make act-env                       # Register actors and shipment #1 only
make chkpnt                        # Add checkpoints to shipment #1
make envio2                        # Create frozen-food shipment with cold chain
make insulina                      # Create insulin shipment with temperature violations
make deploy-sepolia                # Deploy to Sepolia (requires RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY in .env)
```

### logistics-frontend (Vite + React)

```bash
# From logistics-frontend/
npm run dev        # Start dev server (Vite)
npm run build      # TypeScript check + Vite build
npm run lint       # ESLint
npm run preview    # Preview production build
```

### web (Next.js 16)

```bash
# From web/
npm run dev        # Start Next.js dev server
npm run build      # Production build
npm run lint       # ESLint
```

## Architecture

### Contract (`src/LogisticsTracking.sol`)

Role-based access control with 5 actor roles (Sender, Carrier, Hub, Recipient, Inspector). Only the deployer is admin; the admin registers actors via `registerActor()`. Key design decisions:
- **Two-step admin transfer**: `proposeAdmin()` + `acceptAdmin()` to prevent lockout
- **Cold chain**: Temperature stored as `int256 × 10` (e.g., `45` = 4.5 °C). Range: 20–80 (2.0–8.0 °C). Pass `type(int256).min` (`TEMPERATURE_NOT_SET`) to skip temperature validation for a checkpoint. A out-of-range reading auto-generates a `TempViolation` incident.
- **Actor assignment**: An actor is only allowed to interact with a shipment if they were the one who created it or called `updateShipmentStatus()` for it (enforced by `_actorHasShipment` mapping).
- **Terminal states**: Delivered, Cancelled, Returned. Cancellation is only allowed from `Created` or `AtHub`.
- **Limits**: max 200 checkpoints and 50 incidents per shipment.
- Custom errors (not `require` strings) are used throughout for gas efficiency.

### logistics-frontend (`logistics-frontend/src/`)

Single-page app (`App.tsx`) with four tabs: Actores, Envíos, Operaciones, Trazabilidad.

- **Blockchain config**: `src/blockchain/config.ts` — contract address is **hardcoded** (the env-var approach via `VITE_CONTRACT_ADDRESS` is commented out). The ABI is imported directly from `../../out/LogisticsTracking.sol/LogisticsTracking.json`, so **`forge build` must be run before starting the frontend**.
- **Wagmi v3 + viem**: configured for the `anvil` chain only. MetaMask (injected connector) is required. All write calls simulate first via `publicClient.simulateContract()` to surface errors before opening MetaMask.
- **Error handling**: `parseContractError()` decodes custom error selectors (keccak256 4-byte selectors hardcoded in `ERROR_SELECTORS`) to human-readable Spanish messages.
- **Actor list persistence**: known actor addresses are stored in `localStorage` under the key `actors_<contractAddress>`. The "Sync desde chain" button re-fetches `ActorRegistered` events to refresh the list.
- **Dark mode**: driven by a React Context (`DarkContext`) rather than props; toggle in the header.

### Deployment sync flow

After deploying, `sync-contract.js` (invoked by `npm run deploy` in root `package.json`) reads `broadcast/DeployLogistics.s.sol/31337/run-latest.json` and writes the new contract address to `.env` as `VITE_CONTRACT_ADDRESS`. The frontend's `config.ts` currently ignores this and uses a hardcoded address — update it manually when redeploying.

### web (`web/src/`)

Boilerplate Next.js 16 App Router project. `web/src/app/page.tsx` is the default Next.js landing page — not connected to the contract. See `web/AGENTS.md` for important notes about this version of Next.js having breaking changes from prior versions.

### Scripts (`script/`)

Foundry broadcast scripts for demo data:
- `DeployLogistics.s.sol` — deploys the contract
- `SetupDemo.s.sol` — registers actors and creates shipment #1
- `CheckpointsDemo.s.sol` — adds checkpoints to a given shipment ID (`--sig "run(uint256)" <id>`)
- `AlimentosCongelados.s.sol` — cold-chain shipment #2
- `ViolacionTemperatura.s.sol` — shipment #3 with 2 temperature violations (triggers auto-incidents)

## Environment

`.env` (repo root) holds `RPC_URL`, `PRIVATE_KEY`, and optionally `ETHERSCAN_API_KEY` for Sepolia. The default values use Anvil's well-known account #0.
