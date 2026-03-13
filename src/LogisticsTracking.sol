// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LogisticsTracking
 * @dev Sistema de trazabilidad logística con soporte para cadena de frío e incidencias.
 */

contract LogisticsTracking {
    // --- Enums ---
    enum ShipmentStatus {
        Created,
        InTransit,
        AtHub,
        OutForDelivery,
        Delivered,
        Returned,
        Cancelled
    }
    enum ActorRole {
        None,
        Sender,
        Carrier,
        Hub,
        Recipient,
        Inspector
    }
    enum IncidentType {
        Delay,
        Damage,
        Lost,
        TempViolation,
        Unauthorized
    }

    // --- Structs ---
    struct Actor {
        address actorAddress;
        string name;
        ActorRole role;
        string location;
        bool isActive;
    }

    struct Shipment {
        uint256 id;
        address sender;
        address recipient;
        string product;
        string origin;
        string destination;
        uint256 dateCreated;
        uint256 dateDelivered;
        ShipmentStatus status;
        uint256[] checkpointIds;
        uint256[] incidentIds;
        bool requiresColdChain;
    }

    struct Checkpoint {
        uint256 id;
        uint256 shipmentId;
        address actor;
        string location;
        string checkpointType; // "Pickup", "Hub", "Transit", "Delivery"
        uint256 timestamp;
        string notes;
        int256 temperature; // Celsius * 10 (para decimales)
    }

    struct Incident {
        uint256 id;
        uint256 shipmentId;
        IncidentType incidentType;
        address reporter;
        string description;
        uint256 timestamp;
        bool resolved;
    }

    // --- State Variables ---
    address public admin;
    uint256 public nextShipmentId = 1;
    uint256 public nextCheckpointId = 1;
    uint256 public nextIncidentId = 1;

    mapping(uint256 => Shipment) public shipments;
    mapping(uint256 => Checkpoint) public checkpoints;
    mapping(uint256 => Incident) public incidents;
    mapping(address => Actor) public actors;
    mapping(address => uint256[]) public actorShipments;

    // --- Events ---
    event ShipmentCreated(
        uint256 indexed shipmentId, address indexed sender, address indexed recipient, string product
    );
    event CheckpointRecorded(uint256 indexed checkpointId, uint256 indexed shipmentId, string location, address actor);
    event ShipmentStatusChanged(uint256 indexed shipmentId, ShipmentStatus newStatus);
    event IncidentReported(uint256 indexed incidentId, uint256 indexed shipmentId, IncidentType incidentType);
    event IncidentResolved(uint256 indexed incidentId);
    event DeliveryConfirmed(uint256 indexed shipmentId, address indexed recipient, uint256 timestamp);
    event ActorRegistered(address indexed actorAddress, string name, ActorRole role);

    // --- Modifiers ---
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() internal view {
        require(msg.sender == admin, "Only admin");
    }

    modifier onlyActiveActor() {
        _onlyActiveActor();
        _;
    }

    function _onlyActiveActor() internal view {
        require(actors[msg.sender].isActive, "Actor not registered or inactive");
    }

    modifier shipmentExists(uint256 _id) {
        _shipmentExists(_id);
        _;
    }

    function _shipmentExists(uint256 _id) internal view {
        require(_id > 0 && _id < nextShipmentId, "Shipment does not exist");
    }

    constructor() {
        admin = msg.sender;
    }

    // --- Gestión de Actores ---
    function registerActor(string memory _name, ActorRole _role, string memory _location) public {
        require(!actors[msg.sender].isActive, "Already registered");
        actors[msg.sender] = Actor({ actorAddress: msg.sender, name: _name, role: _role, location: _location, isActive: true });
        emit ActorRegistered(msg.sender, _name, _role);
    }

    function getActor(address _actorAddress) public view returns (Actor memory) {
        return actors[_actorAddress];
    }

    function deactivateActor(address _actorAddress) public onlyAdmin {
        actors[_actorAddress].isActive = false;
    }

    // --- Gestión de Envíos ---
    function createShipment(
        address _recipient,
        string memory _product,
        string memory _origin,
        string memory _destination,
        bool _requiresColdChain
    ) public onlyActiveActor returns (uint256) {
        require(actors[msg.sender].role == ActorRole.Sender, "Only Senders can create");

        uint256 id = nextShipmentId++;
        Shipment storage s = shipments[id];
        s.id = id;
        s.sender = msg.sender;
        s.recipient = _recipient;
        s.product = _product;
        s.origin = _origin;
        s.destination = _destination;
        s.dateCreated = block.timestamp;
        s.status = ShipmentStatus.Created;
        s.requiresColdChain = _requiresColdChain;

        actorShipments[msg.sender].push(id);

        emit ShipmentCreated(id, msg.sender, _recipient, _product);
        return id;
    }

    function getShipment(uint256 _id) public view returns (Shipment memory) {
        return shipments[_id];
    }

    function updateShipmentStatus(uint256 _shipmentId, ShipmentStatus _newStatus)
        public
        onlyActiveActor
        shipmentExists(_shipmentId)
    {
        shipments[_shipmentId].status = _newStatus;
        emit ShipmentStatusChanged(_shipmentId, _newStatus);
    }

    function confirmDelivery(uint256 _shipmentId) public shipmentExists(_shipmentId) {
        Shipment storage s = shipments[_shipmentId];
        require(msg.sender == s.recipient, "Only recipient can confirm");
        require(s.status != ShipmentStatus.Delivered, "Already delivered");

        s.status = ShipmentStatus.Delivered;
        s.dateDelivered = block.timestamp;

        emit DeliveryConfirmed(_shipmentId, msg.sender, block.timestamp);
        emit ShipmentStatusChanged(_shipmentId, ShipmentStatus.Delivered);
    }

    function cancelShipment(uint256 _shipmentId) public shipmentExists(_shipmentId) {
        require(msg.sender == shipments[_shipmentId].sender, "Only sender can cancel");
        require(shipments[_shipmentId].status == ShipmentStatus.Created, "Cannot cancel after transit");

        shipments[_shipmentId].status = ShipmentStatus.Cancelled;
        emit ShipmentStatusChanged(_shipmentId, ShipmentStatus.Cancelled);
    }

    // --- Gestión de Checkpoints ---
    function recordCheckpoint(
        uint256 _shipmentId,
        string memory _location,
        string memory _checkpointType,
        string memory _notes,
        int256 _temperature
    ) public onlyActiveActor shipmentExists(_shipmentId) returns (uint256) {
        uint256 cpId = nextCheckpointId++;

        checkpoints[cpId] = Checkpoint({
            id: cpId,
            shipmentId: _shipmentId,
            actor: msg.sender,
            location: _location,
            checkpointType: _checkpointType,
            timestamp: block.timestamp,
            notes: _notes,
            temperature: _temperature
        });

        shipments[_shipmentId].checkpointIds.push(cpId);

        // Auto-reporte si hay violación de temperatura
        if (shipments[_shipmentId].requiresColdChain && (_temperature > 80 || _temperature < 20)) {
            reportIncident(_shipmentId, IncidentType.TempViolation, "Temperature out of range");
        }

        emit CheckpointRecorded(cpId, _shipmentId, _location, msg.sender);
        return cpId;
    }

    function getCheckpoint(uint256 _checkpointId) public view returns (Checkpoint memory) {
        require(_checkpointId > 0 && _checkpointId < nextCheckpointId, "Checkpoint does not exist");
        return checkpoints[_checkpointId];
    }

    function getShipmentCheckpoints(uint256 _id) public view returns (Checkpoint[] memory) {
        uint256[] memory ids = shipments[_id].checkpointIds;
        Checkpoint[] memory results = new Checkpoint[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            results[i] = checkpoints[ids[i]];
        }
        return results;
    }

    // --- Gestión de Incidencias ---
    function reportIncident(uint256 _shipmentId, IncidentType _type, string memory _desc)
        public
        onlyActiveActor
        shipmentExists(_shipmentId)
        returns (uint256)
    {
        uint256 incId = nextIncidentId++;
        incidents[incId] = Incident({ id: incId, shipmentId: _shipmentId, incidentType: _type, reporter: msg.sender, description: _desc, timestamp: block.timestamp, resolved: false });
        shipments[_shipmentId].incidentIds.push(incId);

        emit IncidentReported(incId, _shipmentId, _type);
        return incId;
    }

    function resolveIncident(uint256 _incidentId) public onlyAdmin {
        incidents[_incidentId].resolved = true;
        emit IncidentResolved(_incidentId);
    }

    function getIncident(uint256 _incidentId) public view returns (Incident memory) {
        require(_incidentId > 0 && _incidentId < nextIncidentId, "Incident does not exist");
        return incidents[_incidentId];
    }

    function getShipmentIncidents(uint256 _shipmentId)
        public
        view
        shipmentExists(_shipmentId)
        returns (Incident[] memory)
    {
        uint256[] memory ids = shipments[_shipmentId].incidentIds;
        Incident[] memory results = new Incident[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            results[i] = incidents[ids[i]];
        }
        return results;
    }

    // --- Funciones auxiliares ---
    function getActorShipments(address _actor) public view returns (uint256[] memory) {
        return actorShipments[_actor];
    }

    function verifyTemperatureCompliance(uint256 _shipmentId) public view returns (bool) {
        Shipment storage s = shipments[_shipmentId];
        if (!s.requiresColdChain) return true;

        for (uint256 i = 0; i < s.checkpointIds.length; i++) {
            int256 temp = checkpoints[s.checkpointIds[i]].temperature;
            if (temp > 80 || temp < 20) return false; // Rango ejemplo: 2.0°C a 8.0°C
        }
        return true;
    }

    function isIncidentResolved(uint256 incidentId) public view returns (bool) {
        return incidents[incidentId].resolved;
    }
}
