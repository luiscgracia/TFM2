# Code Index

This file serves as a complete code index for the TFM2 repository. It contains all symbols, contracts, functions, enums, and their respective locations for better code navigation.

## Main Contract
### LogisticsTracking
- Location: `contracts/LogisticsTracking.sol`

## Enums
### ActorRole
- Location: `contracts/Enums.sol`
- Values: `Admin`, `Carrier`, `Receiver`

### ShipmentStatus
- Location: `contracts/Enums.sol`
- Values: `Pending`, `In Transit`, `Delivered`, `Cancelled`

### CheckpointType
- Location: `contracts/Enums.sol`
- Values: `Pickup`, `Delivery`, `Checkpoint`

### IncidentType
- Location: `contracts/Enums.sol`
- Values: `Delay`, `Damage`, `Lost`

## Structs
### Actor
- Location: `contracts/LogisticsTracking.sol`
- Details: Contains actor details relevant to logistics tracking.

### Shipment
- Location: `contracts/LogisticsTracking.sol`
- Details: Contains shipment details relevant to logistics.

### Checkpoint
- Location: `contracts/LogisticsTracking.sol`
- Details: Contains checkpoint details for a shipment.

### Incident
- Location: `contracts/LogisticsTracking.sol`
- Details: Contains incident details for a shipment.

## Functions
### Public Functions
- **createShipment()**
  - Location: `contracts/LogisticsTracking.sol`
  - Description: Create a new shipment.

- **getShipmentStatus()**
  - Location: `contracts/LogisticsTracking.sol`
  - Description: Get the status of a shipment.

### External Functions
- **updateShipmentStatus()**
  - Location: `contracts/LogisticsTracking.sol`
  - Description: Update the status of an existing shipment.

- **reportIncident()**
  - Location: `contracts/LogisticsTracking.sol`
  - Description: Report an incident related to a shipment.

---

*This index was automatically generated on 2026-04-10 14:49:05 UTC.*