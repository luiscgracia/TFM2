// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24; // [S-1] Actualizado desde ^0.8.6 — mejoras de optimización EVM Shanghai (push0 opcode)

/**
 * @title LogisticsTracking (v4 - auditado)
 * @dev Sistema de trazabilidad logística con soporte para cadena de frío e incidencias.
 *
 * Cambios respecto a v3 (resultado de auditoría de seguridad):
 *
 *  [C-1]  recordCheckpoint / confirmDelivery: aplicado patrón Checks-Effects-Interactions.
 *         Todos los cambios de estado ocurren ANTES de emitir eventos, como blindaje preventivo
 *         ante posibles callbacks externos en futuras versiones del contrato.
 *
 *  [C-2]  recordCheckpoint / reportIncident: añadida validación de que el actor
 *         que llama está asignado al envío (_actorHasShipment). Error: ActorNotAssignedToShipment.
 *         Previene que actores ajenos contaminen la trazabilidad de envíos que no les corresponden.
 *
 *  [W-1]  cancelShipment: mejorado el set de estados cancelables. Se permite cancelar en
 *         Created y AtHub. Error diferenciado AlreadyClosedShipment para estados terminales.
 *
 *  [W-2]  getShipmentCheckpoints: añadido modifier shipmentExists para consistencia con
 *         getShipmentIncidents y para evitar retornos silenciosos en IDs inexistentes.
 *
 *  [W-3]  Temperatura 0 ignorada en validación de cadena de frío. Se usa el sentinel
 *         TEMPERATURE_NOT_SET (type(int256).min) para representar "sin lectura". Si el
 *         checkpoint no registra temperatura, no se valida ni se crea incidencia.
 *
 *  [W-4]  deactivateActor: añadida guarda de existencia (actorAddress != address(0))
 *         para simetría con reactivateActor y evitar desactivaciones silenciosas de
 *         addresses no registradas.
 *
 *  [S-2]  deactivateActor / reactivateActor: emiten evento ActorStatusChanged para
 *         facilitar monitoreo off-chain e indexación en subgraphs.
 *
 *  [S-3]  verifyTemperatureCompliance: añadido shipmentExists y skip de temperaturas
 *         TEMPERATURE_NOT_SET para evitar falsos positivos de cumplimiento.
 *
 * Optimizaciones previas de v3 (mantenidas):
 *  [GAS-1]  _addActorShipment en O(1) con mapping de presencia.
 *  [GAS-2]  recordCheckpoint: storage pointer cacheado.
 *  [GAS-3]  updateShipmentStatus: caché del rol del actor.
 *  [GAS-4]  Paginación en getShipmentCheckpoints / getShipmentIncidents.
 *  [GAS-5]  Custom errors en lugar de strings en require.
 *  [GAS-6]  CheckpointType como enum en lugar de string.
 *  [GAS-7]  Contadores privados con getters explícitos.
 *  [GAS-8]  Storage pointer reutilizado en createShipment.
 *  [FIX-1]  Campo actor restaurado en struct Checkpoint.
 */

contract LogisticsTracking {
    // -------------------------------------------------------------------------
    // Constantes
    // -------------------------------------------------------------------------

    /// @dev Temperatura mínima válida para cadena de frío: 2.0 °C (almacenada * 10)
    int256 public constant COLD_CHAIN_TEMP_MIN = 20;

    /// @dev Temperatura máxima válida para cadena de frío: 8.0 °C (almacenada * 10)
    int256 public constant COLD_CHAIN_TEMP_MAX = 80;

    /// @dev [W-3] Sentinel para "temperatura no registrada". Excluye el checkpoint
    ///      de la validación de cadena de frío. Pasar este valor para omitir la lectura.
    int256 public constant TEMPERATURE_NOT_SET = type(int256).min;

    /// @dev Límite de checkpoints por envío para evitar iteraciones costosas
    uint256 public constant MAX_CHECKPOINTS_PER_SHIPMENT = 200;

    /// @dev Límite de incidencias por envío
    uint256 public constant MAX_INCIDENTS_PER_SHIPMENT = 50;

    // -------------------------------------------------------------------------
    // Errores personalizados  [GAS-5]
    // -------------------------------------------------------------------------

    error OnlyAdmin();
    error NotPendingAdmin();
    error ActorInactive();
    error ShipmentNotFound(uint256 id);
    error AlreadyRegisteredAndActive();
    error InvalidAddress();
    error InvalidRole();
    error OnlySendersCanCreate();
    error OnlyCarrierOrHub();
    error CannotSetDeliveredDirectly();
    error OnlyRecipientCanConfirm();
    error AlreadyDelivered();
    error OnlySenderCanCancel();
    error CannotCancelAfterTransit(); // Mantenido por compatibilidad de interfaz
    error AlreadyClosedShipment(); // [W-1] Para estados terminales (Delivered, Returned, Cancelled)
    error MaxCheckpointsReached();
    error MaxIncidentsReached();
    error CheckpointNotFound(uint256 id);
    error IncidentNotFound(uint256 id);
    error ActorDoesNotExist();
    error ActorNotAssignedToShipment(); // [C-2] Actor no está asignado a este envío

    // -------------------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------------------

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

    /// @dev [GAS-6] checkpointType como enum elimina escrituras de string en storage.
    enum CheckpointType {
        Pickup,
        Hub,
        Transit,
        Delivery,
        Other
    }

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

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
        address actor; // [FIX-1] qué actor registró el checkpoint
        string location;
        CheckpointType checkpointType; // [GAS-6]
        uint256 timestamp;
        string notes;
        int256 temperature; // Celsius * 10. Usar TEMPERATURE_NOT_SET si no aplica.
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

    // -------------------------------------------------------------------------
    // Variables de estado
    // -------------------------------------------------------------------------

    address public admin;
    address public pendingAdmin;

    /// @dev [GAS-7] Contadores privados — getters explícitos abajo
    uint256 private _nextShipmentId = 1;
    uint256 private _nextCheckpointId = 1;
    uint256 private _nextIncidentId = 1;

    mapping(uint256 => Shipment) private _shipments;
    mapping(uint256 => Checkpoint) private _checkpoints;
    mapping(uint256 => Incident) private _incidents;
    mapping(address => Actor) private _actors;
    mapping(address => uint256[]) private _actorShipments;

    /// @dev [GAS-1] Índice de presencia para _addActorShipment en O(1)
    mapping(address => mapping(uint256 => bool)) private _actorHasShipment;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event ShipmentCreated(
        uint256 indexed shipmentId, address indexed sender, address indexed recipient, string product
    );
    event CheckpointRecorded(
        uint256 indexed checkpointId, uint256 indexed shipmentId, CheckpointType checkpointType, address actor
    );
    event ShipmentStatusChanged(uint256 indexed shipmentId, ShipmentStatus newStatus);
    event IncidentReported(uint256 indexed incidentId, uint256 indexed shipmentId, IncidentType incidentType);
    event IncidentResolved(uint256 indexed incidentId);
    event DeliveryConfirmed(uint256 indexed shipmentId, address indexed recipient, uint256 timestamp);
    event ActorRegistered(address indexed actorAddress, string name, ActorRole role);
    event ActorStatusChanged(address indexed actorAddress, bool isActive); // [S-2]
    event AdminTransferProposed(address indexed proposedAdmin);
    event AdminTransferAccepted(address indexed newAdmin);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() internal view {
        if (msg.sender != admin) revert OnlyAdmin();
    }

    modifier onlyActiveActor() {
        _onlyActiveActor();
        _;
    }

    function _onlyActiveActor() internal view {
        if (!_actors[msg.sender].isActive) revert ActorInactive();
    }

    modifier shipmentExists(uint256 _id) {
        _shipmentExists(_id);
        _;
    }

    function _shipmentExists(uint256 _id) internal view {
        if (_id == 0 || _id >= _nextShipmentId) revert ShipmentNotFound(_id);
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        admin = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Getters de contadores  [GAS-7]
    // -------------------------------------------------------------------------

    function nextShipmentId() external view returns (uint256) {
        return _nextShipmentId;
    }

    function nextCheckpointId() external view returns (uint256) {
        return _nextCheckpointId;
    }

    function nextIncidentId() external view returns (uint256) {
        return _nextIncidentId;
    }

    // -------------------------------------------------------------------------
    // Gestión de admin
    // -------------------------------------------------------------------------

    function proposeAdmin(address _newAdmin) external onlyAdmin {
        if (_newAdmin == address(0)) revert InvalidAddress();
        pendingAdmin = _newAdmin;
        emit AdminTransferProposed(_newAdmin);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferAccepted(msg.sender);
    }

    // -------------------------------------------------------------------------
    // Gestión de actores
    // -------------------------------------------------------------------------

    function registerActor(string memory _name, ActorRole _role, string memory _location, address _actorAddress)
        external
        onlyAdmin
    {
        if (_actorAddress == address(0)) revert InvalidAddress();
        if (_actors[_actorAddress].isActive) revert AlreadyRegisteredAndActive();
        if (_role == ActorRole.None) revert InvalidRole();

        _actors[_actorAddress] =
            Actor({actorAddress: _actorAddress, name: _name, role: _role, location: _location, isActive: true});

        emit ActorRegistered(_actorAddress, _name, _role);
    }

    /// @notice Devuelve el struct del actor. isActive = false si no existe.
    function getActor(address _actorAddress) external view returns (Actor memory) {
        return _actors[_actorAddress];
    }

    /// @notice Desactiva un actor existente.
    /// @dev [W-4] Añadida guarda de existencia para simetría con reactivateActor.
    ///      [S-2] Emite ActorStatusChanged para monitoreo off-chain.
    function deactivateActor(address _actorAddress) external onlyAdmin {
        if (_actors[_actorAddress].actorAddress == address(0)) revert ActorDoesNotExist(); // [W-4]
        _actors[_actorAddress].isActive = false;
        emit ActorStatusChanged(_actorAddress, false); // [S-2]
    }

    /// @notice Reactiva un actor previamente desactivado.
    /// @dev [S-2] Emite ActorStatusChanged para monitoreo off-chain.
    function reactivateActor(address _actorAddress) external onlyAdmin {
        if (_actors[_actorAddress].actorAddress == address(0)) revert ActorDoesNotExist();
        _actors[_actorAddress].isActive = true;
        emit ActorStatusChanged(_actorAddress, true); // [S-2]
    }

    // -------------------------------------------------------------------------
    // Gestión de envíos
    // -------------------------------------------------------------------------

    function createShipment(
        address _recipient,
        string memory _product,
        string memory _origin,
        string memory _destination,
        bool _requiresColdChain
    ) external onlyActiveActor returns (uint256) {
        if (_actors[msg.sender].role != ActorRole.Sender) revert OnlySendersCanCreate();

        uint256 id = _nextShipmentId++;

        // [GAS-8] Storage pointer reutilizado — un solo acceso al mapping
        Shipment storage s = _shipments[id];
        s.id = id;
        s.sender = msg.sender;
        s.recipient = _recipient;
        s.product = _product;
        s.origin = _origin;
        s.destination = _destination;
        s.dateCreated = block.timestamp;
        s.status = ShipmentStatus.Created;
        s.requiresColdChain = _requiresColdChain;

        _addActorShipment(msg.sender, id);
        if (_recipient != address(0)) {
            _addActorShipment(_recipient, id);
        }

        emit ShipmentCreated(id, msg.sender, _recipient, _product);
        return id;
    }

    function getShipment(uint256 _id) external view returns (Shipment memory) {
        return _shipments[_id];
    }

    function updateShipmentStatus(uint256 _shipmentId, ShipmentStatus _newStatus)
        external
        onlyActiveActor
        shipmentExists(_shipmentId)
    {
        // [GAS-3] Caché del rol — evita segundo SLOAD a _actors[msg.sender]
        ActorRole role = _actors[msg.sender].role;
        if (role != ActorRole.Carrier && role != ActorRole.Hub) revert OnlyCarrierOrHub();
        if (_newStatus == ShipmentStatus.Delivered) revert CannotSetDeliveredDirectly();

        _shipments[_shipmentId].status = _newStatus;
        _addActorShipment(msg.sender, _shipmentId);

        emit ShipmentStatusChanged(_shipmentId, _newStatus);
    }

    /// @notice El destinatario confirma la recepción del envío.
    /// @dev [C-1] Patrón Checks-Effects-Interactions aplicado: todos los cambios de
    ///      estado ocurren antes de emitir eventos, como blindaje preventivo.
    function confirmDelivery(uint256 _shipmentId) external shipmentExists(_shipmentId) {
        Shipment storage s = _shipments[_shipmentId];

        // --- Checks ---
        if (msg.sender != s.recipient) revert OnlyRecipientCanConfirm();
        if (s.status == ShipmentStatus.Delivered) revert AlreadyDelivered();

        // --- Effects (todos los cambios de estado primero) --- [C-1]
        s.status = ShipmentStatus.Delivered;
        s.dateDelivered = block.timestamp;

        // --- Interactions (eventos al final) --- [C-1]
        emit ShipmentStatusChanged(_shipmentId, ShipmentStatus.Delivered);
        emit DeliveryConfirmed(_shipmentId, msg.sender, block.timestamp);
    }

    /// @notice El sender cancela el envío.
    /// @dev [W-1] Cancelación permitida en estados Created y AtHub.
    ///      Estados terminales (Delivered, Returned, Cancelled) retornan AlreadyClosedShipment.
    ///      Estado InTransit u OutForDelivery retornan CannotCancelAfterTransit.
    function cancelShipment(uint256 _shipmentId) external shipmentExists(_shipmentId) {
        Shipment storage s = _shipments[_shipmentId];
        if (msg.sender != s.sender) revert OnlySenderCanCancel();

        ShipmentStatus currentStatus = s.status;

        // [W-1] Rechazar si el envío ya está cerrado permanentemente
        if (
            currentStatus == ShipmentStatus.Delivered || currentStatus == ShipmentStatus.Returned
                || currentStatus == ShipmentStatus.Cancelled
        ) revert AlreadyClosedShipment();

        // [W-1] Solo Created y AtHub son cancelables; InTransit/OutForDelivery no
        if (currentStatus != ShipmentStatus.Created && currentStatus != ShipmentStatus.AtHub) {
            revert CannotCancelAfterTransit();
        }

        s.status = ShipmentStatus.Cancelled;
        emit ShipmentStatusChanged(_shipmentId, ShipmentStatus.Cancelled);
    }

    // -------------------------------------------------------------------------
    // Gestión de checkpoints
    // -------------------------------------------------------------------------

    /// @notice Registra un checkpoint de posición/estado para el envío.
    /// @dev [C-1] Patrón Checks-Effects-Interactions: cambios de estado antes de eventos.
    ///      [C-2] Validación de que el actor está asignado al envío.
    ///      [W-3] Temperatura TEMPERATURE_NOT_SET omite la validación de cadena de frío.
    ///      [GAS-2] Storage pointer cacheado para evitar múltiples SLOADs.
    function recordCheckpoint(
        uint256 _shipmentId,
        string memory _location,
        CheckpointType _checkpointType,
        string memory _notes,
        int256 _temperature
    ) external onlyActiveActor shipmentExists(_shipmentId) returns (uint256) {
        // --- Checks ---
        // [C-2] El actor debe estar asignado al envío
        if (!_actorHasShipment[msg.sender][_shipmentId]) revert ActorNotAssignedToShipment();

        // [GAS-2] Storage pointer cacheado
        Shipment storage s = _shipments[_shipmentId];
        if (s.checkpointIds.length >= MAX_CHECKPOINTS_PER_SHIPMENT) revert MaxCheckpointsReached();

        uint256 cpId = _nextCheckpointId++;

        // --- Effects --- [C-1]
        _checkpoints[cpId] = Checkpoint({
            id: cpId,
            shipmentId: _shipmentId,
            actor: msg.sender,
            location: _location,
            checkpointType: _checkpointType,
            timestamp: block.timestamp,
            notes: _notes,
            temperature: _temperature
        });

        s.checkpointIds.push(cpId);

        // [W-3] Solo validar temperatura si se proporcionó una lectura real
        if (
            s.requiresColdChain && _temperature != TEMPERATURE_NOT_SET
                && (_temperature > COLD_CHAIN_TEMP_MAX || _temperature < COLD_CHAIN_TEMP_MIN)
        ) {
            _createIncident(_shipmentId, IncidentType.TempViolation, "Temperature out of range");
        }

        // --- Interactions (evento al final) --- [C-1]
        emit CheckpointRecorded(cpId, _shipmentId, _checkpointType, msg.sender);
        return cpId;
    }

    function getCheckpoint(uint256 _checkpointId) external view returns (Checkpoint memory) {
        if (_checkpointId == 0 || _checkpointId >= _nextCheckpointId) {
            revert CheckpointNotFound(_checkpointId);
        }
        return _checkpoints[_checkpointId];
    }

    /// @notice Devuelve checkpoints paginados. [GAS-4]
    /// @param _id     ID del envío.
    /// @param _offset Índice de inicio (0-based).
    /// @param _limit  Máximo de elementos a devolver.
    /// @dev [W-2] Añadido shipmentExists para consistencia con getShipmentIncidents.
    function getShipmentCheckpoints(uint256 _id, uint256 _offset, uint256 _limit)
        external
        view
        shipmentExists(_id) // [W-2]
        returns (Checkpoint[] memory)
    {
        uint256[] storage ids = _shipments[_id].checkpointIds;
        uint256 total = ids.length;
        if (_offset >= total) return new Checkpoint[](0);

        uint256 end = _offset + _limit > total ? total : _offset + _limit;
        Checkpoint[] memory results = new Checkpoint[](end - _offset);
        for (uint256 i = _offset; i < end; i++) {
            results[i - _offset] = _checkpoints[ids[i]];
        }
        return results;
    }

    /// @notice Devuelve todos los checkpoints del envío.
    ///         Usar solo off-chain. En llamadas on-chain preferir la versión paginada.
    function getAllShipmentCheckpoints(uint256 _id) external view shipmentExists(_id) returns (Checkpoint[] memory) {
        uint256[] storage ids = _shipments[_id].checkpointIds;
        Checkpoint[] memory results = new Checkpoint[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            results[i] = _checkpoints[ids[i]];
        }
        return results;
    }

    // -------------------------------------------------------------------------
    // Gestión de incidencias
    // -------------------------------------------------------------------------

    /// @notice Reporta una incidencia sobre un envío.
    /// @dev [C-2] Validación de que el actor está asignado al envío.
    function reportIncident(uint256 _shipmentId, IncidentType _type, string memory _desc)
        external
        onlyActiveActor
        shipmentExists(_shipmentId)
        returns (uint256)
    {
        // [C-2] El actor debe estar asignado al envío
        if (!_actorHasShipment[msg.sender][_shipmentId]) revert ActorNotAssignedToShipment();

        return _createIncident(_shipmentId, _type, _desc);
    }

    function _createIncident(uint256 _shipmentId, IncidentType _type, string memory _desc) internal returns (uint256) {
        Shipment storage s = _shipments[_shipmentId];
        if (s.incidentIds.length >= MAX_INCIDENTS_PER_SHIPMENT) revert MaxIncidentsReached();

        uint256 incId = _nextIncidentId++;
        _incidents[incId] = Incident({
            id: incId,
            shipmentId: _shipmentId,
            incidentType: _type,
            reporter: msg.sender,
            description: _desc,
            timestamp: block.timestamp,
            resolved: false
        });

        s.incidentIds.push(incId);
        emit IncidentReported(incId, _shipmentId, _type);
        return incId;
    }

    function resolveIncident(uint256 _incidentId) external onlyAdmin {
        if (_incidentId == 0 || _incidentId >= _nextIncidentId) {
            revert IncidentNotFound(_incidentId);
        }
        _incidents[_incidentId].resolved = true;
        emit IncidentResolved(_incidentId);
    }

    function getIncident(uint256 _incidentId) external view returns (Incident memory) {
        if (_incidentId == 0 || _incidentId >= _nextIncidentId) {
            revert IncidentNotFound(_incidentId);
        }
        return _incidents[_incidentId];
    }

    /// @notice Devuelve incidencias paginadas. [GAS-4]
    function getShipmentIncidents(uint256 _shipmentId, uint256 _offset, uint256 _limit)
        external
        view
        shipmentExists(_shipmentId)
        returns (Incident[] memory)
    {
        uint256[] storage ids = _shipments[_shipmentId].incidentIds;
        uint256 total = ids.length;
        if (_offset >= total) return new Incident[](0);

        uint256 end = _offset + _limit > total ? total : _offset + _limit;
        Incident[] memory results = new Incident[](end - _offset);
        for (uint256 i = _offset; i < end; i++) {
            results[i - _offset] = _incidents[ids[i]];
        }
        return results;
    }

    /// @notice Devuelve todas las incidencias del envío.
    ///         Usar solo off-chain. En llamadas on-chain preferir la versión paginada.
    function getAllShipmentIncidents(uint256 _shipmentId)
        external
        view
        shipmentExists(_shipmentId)
        returns (Incident[] memory)
    {
        uint256[] storage ids = _shipments[_shipmentId].incidentIds;
        Incident[] memory results = new Incident[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            results[i] = _incidents[ids[i]];
        }
        return results;
    }

    // -------------------------------------------------------------------------
    // Funciones auxiliares
    // -------------------------------------------------------------------------

    function getActorShipments(address _actor) external view returns (uint256[] memory) {
        return _actorShipments[_actor];
    }

    /// @notice Verifica que todos los checkpoints con lectura de temperatura
    ///         estén dentro del rango de cadena de frío.
    /// @dev [S-3] Añadido shipmentExists para evitar falsos positivos en IDs inexistentes.
    ///      [W-3] Checkpoints con TEMPERATURE_NOT_SET son ignorados en la validación.
    function verifyTemperatureCompliance(uint256 _shipmentId)
        external
        view
        shipmentExists(_shipmentId) // [S-3]
        returns (bool)
    {
        Shipment storage s = _shipments[_shipmentId];
        if (!s.requiresColdChain) return true;

        uint256 len = s.checkpointIds.length;
        for (uint256 i = 0; i < len; i++) {
            int256 temp = _checkpoints[s.checkpointIds[i]].temperature;
            // [W-3] Ignorar checkpoints sin lectura de temperatura
            if (temp == TEMPERATURE_NOT_SET) continue;
            if (temp > COLD_CHAIN_TEMP_MAX || temp < COLD_CHAIN_TEMP_MIN) return false;
        }
        return true;
    }

    function isIncidentResolved(uint256 _incidentId) external view returns (bool) {
        return _incidents[_incidentId].resolved;
    }

    // -------------------------------------------------------------------------
    // Helper interno  [GAS-1]
    // -------------------------------------------------------------------------

    /// @dev Añade _shipmentId al array del actor en O(1) usando mapping de presencia.
    function _addActorShipment(address _actor, uint256 _shipmentId) internal {
        if (!_actorHasShipment[_actor][_shipmentId]) {
            _actorHasShipment[_actor][_shipmentId] = true;
            _actorShipments[_actor].push(_shipmentId);
        }
    }
}
