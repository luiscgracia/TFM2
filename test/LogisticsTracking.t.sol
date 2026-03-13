// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import "../src/LogisticsTracking.sol";

contract LogisticsTrackingTest is Test {
    LogisticsTracking public logistics;

    // Usuarios de prueba
    address admin = address(0xAD);
    address sender = address(0x1);
    address carrier = address(0x2);
    address hub = address(0x3);
    address recipient = address(0x4);
    address stranger = address(0x5);

    function setUp() public {
        vm.prank(admin);
        logistics = new LogisticsTracking();
    }

    // --- Tests de Gestión de Actores ---
    function testRegisterSender() public {
        vm.prank(sender);
        logistics.registerActor("Sender Corp", LogisticsTracking.ActorRole.Sender, "Madrid");
        LogisticsTracking.Actor memory a = logistics.getActor(sender);
        assertEq(uint256(a.role), uint256(LogisticsTracking.ActorRole.Sender));
        assertTrue(a.isActive);
    }

    function testRegisterCarrier() public {
        vm.prank(carrier);
        logistics.registerActor("Fast Truck", LogisticsTracking.ActorRole.Carrier, "Valencia");
        assertEq(uint256(logistics.getActor(carrier).role), uint256(LogisticsTracking.ActorRole.Carrier));
    }

    function testRegisterHub() public {
        vm.prank(hub);
        logistics.registerActor("Main Hub", LogisticsTracking.ActorRole.Hub, "Zaragoza");
        assertEq(uint256(logistics.getActor(hub).role), uint256(LogisticsTracking.ActorRole.Hub));
    }

    function testRegisterRecipient() public {
        vm.prank(recipient);
        logistics.registerActor("End User", LogisticsTracking.ActorRole.Recipient, "Barcelona");
        assertEq(uint256(logistics.getActor(recipient).role), uint256(LogisticsTracking.ActorRole.Recipient));
    }

    function testDeactivateActor() public {
        vm.prank(sender);
        logistics.registerActor("Temp", LogisticsTracking.ActorRole.Sender, "Loc");

        vm.prank(admin);
        logistics.deactivateActor(sender);

        LogisticsTracking.Actor memory a = logistics.getActor(sender);
        assertFalse(a.isActive);
    }

    // --- Tests de Creación de Envíos ---
    function testCreateShipment() public {
        _setupActors();
        vm.prank(sender);
        uint256 id = logistics.createShipment(recipient, "iPhone 15", "Store", "Home", false);

        assertEq(id, 1);
        LogisticsTracking.Shipment memory s = logistics.getShipment(id);
        assertEq(s.product, "iPhone 15");
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Created));
    }

    function testCreateShipmentWithColdChain() public {
        _setupActors();
        vm.prank(sender);

        uint256 sid = logistics.createShipment(
            recipient,
            "Vacunas Termosensibles",
            "Laboratorio Bio",
            "Hospital Central",
            true // requiresColdChain = true
        );

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertTrue(s.requiresColdChain, "The shipment should require a cold chain");
        assertEq(s.product, "Vacunas Termosensibles");
    }

    function testShipmentIdIncrementation() public {
        _setupActors();
        vm.startPrank(sender);

        uint256 id1 = logistics.createShipment(recipient, "Prod 1", "O", "D", false);
        uint256 id2 = logistics.createShipment(recipient, "Prod 2", "O", "D", false);
        uint256 id3 = logistics.createShipment(recipient, "Prod 3", "O", "D", false);

        vm.stopPrank();

        assertEq(id1, 1, "The first ID should be 1");
        assertEq(id2, 2, "The second ID should be 2");
        assertEq(id3, 3, "The third ID should be 3");
        assertEq(logistics.nextShipmentId(), 4, "The global counter should be at 4");
    }

    function testGetShipment() public {
        _setupActors();
        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Laptop", "Almacen", "Oficina", false);

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);

        assertEq(s.id, sid);
        assertEq(s.sender, sender);
        assertEq(s.recipient, recipient);
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Created));
        assertEq(s.checkpointIds.length, 0, "There shouldn't be any checkpoints at the start");
    }

    function testOnlySenderCanCreateShipment() public {
        _setupActors();
        vm.prank(carrier); // Un carrier no puede crear envíos
        vm.expectRevert("Only Senders can create");
        logistics.createShipment(recipient, "Bad", "A", "B", false);
    }

    // --- Tests de Checkpoints ---
    function testRecordPickupCheckpoint() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Warehouse A", "Pickup", "Picked up by truck 1", 250);

        LogisticsTracking.Checkpoint[] memory cps = logistics.getShipmentCheckpoints(sid);
        assertEq(cps.length, 1);
        assertEq(cps[0].checkpointType, "Pickup");
    }

    function testRecordHubCheckpoint() public {
        uint256 sid = _createStandardShipment();
        vm.prank(hub); // Usamos el actor registrado como Hub

        uint256 cid = logistics.recordCheckpoint(
            sid,
            "Hub Logistico Norte",
            "Hub",
            "Paquete clasificado y en espera de ruta",
            220 // 22.0°C
        );

        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(cp.checkpointType, "Hub");
        assertEq(cp.actor, hub);
        assertEq(logistics.getShipmentCheckpoints(sid).length, 1);
    }

    function testRecordTransitCheckpoint() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier); // El transportista registra el evento en ruta

        uint256 cid = logistics.recordCheckpoint(
            sid,
            "Autopista AP-7",
            "Transit",
            "Camion en movimiento - Mitad de trayecto",
            215 // 21.5°C
        );

        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(cp.checkpointType, "Transit");
        assertEq(cp.location, "Autopista AP-7");
    }

    function testRecordDeliveryCheckpoint() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier);

        uint256 cid = logistics.recordCheckpoint(
            sid,
            "Puerta del Destinatario",
            "Delivery",
            "Repartidor en direccion final",
            230 // 23.0°C
        );

        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(cp.checkpointType, "Delivery");

        // Verificamos que el historial del envío ahora contiene este último paso
        LogisticsTracking.Checkpoint[] memory history = logistics.getShipmentCheckpoints(sid);
        assertEq(history[history.length - 1].checkpointType, "Delivery");
    }

    function testRecordCheckpointWithTemperature() public {
        uint256 sid = _createColdChainShipment();
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Fridge Truck", "Transit", "Stable", 42); // 4.2°C

        LogisticsTracking.Checkpoint[] memory cps = logistics.getShipmentCheckpoints(sid);
        assertEq(cps[0].temperature, 42);
    }

    function testGetShipmentCheckpoints() public {
        uint256 sid = _createStandardShipment();

        vm.startPrank(carrier);
        logistics.recordCheckpoint(sid, "Origen", "Pickup", "Carga", 200);
        logistics.recordCheckpoint(sid, "Ruta 1", "Transit", "En viaje", 210);
        logistics.recordCheckpoint(sid, "Hub A", "Hub", "Descarga", 205);
        vm.stopPrank();

        LogisticsTracking.Checkpoint[] memory allCheckpoints = logistics.getShipmentCheckpoints(sid);

        assertEq(allCheckpoints.length, 3, "There should be 3 checkpoints");
        assertEq(allCheckpoints[0].location, "Origen");
        assertEq(allCheckpoints[1].location, "Ruta 1");
        assertEq(allCheckpoints[2].location, "Hub A");
    }

    function testCheckpointTimeline() public {
        uint256 sid = _createStandardShipment();

        // Registro 1: T = 1000
        vm.warp(1000);
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Punto A", "Pickup", "Inicio", 200);

        // Registro 2: T = 2000
        vm.warp(2000);
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Punto B", "Transit", "Sigue", 210);

        LogisticsTracking.Checkpoint[] memory timeline = logistics.getShipmentCheckpoints(sid);

        assertEq(timeline[0].timestamp, 1000);
        assertEq(timeline[1].timestamp, 2000);
        assertTrue(timeline[1].timestamp > timeline[0].timestamp, "The second event must occur after the first");
    }

    // --- Tests de Temperatura ---
    /**
     * @dev Verifica que un envío con múltiples checkpoints dentro del rango de temperatura sea marcado como conforme (Valid).
     */
    function testVerifyTemperatureComplianceValid() public {
        // 1. Creamos un envío que requiere cadena de frío
        uint256 sid = _createColdChainShipment();

        vm.startPrank(carrier);

        // 2. Registramos varios checkpoints con temperaturas correctas
        // Recordatorio: 20 = 2.0°C, 80 = 8.0°C
        logistics.recordCheckpoint(sid, "Origen", "Pickup", "Carga fria", 40); // 4.0°C
        logistics.recordCheckpoint(sid, "Ruta A", "Transit", "En trayecto", 55); // 5.5°C
        logistics.recordCheckpoint(sid, "Hub", "Hub", "Almacenaje temporal", 30); // 3.0°C

        vm.stopPrank();

        // 3. Validamos que el contrato confirme el cumplimiento
        bool isCompliant = logistics.verifyTemperatureCompliance(sid);
        assertTrue(isCompliant, "El envio deberia cumplir con la cadena de frio");

        // 4. Aseguramos que NO se hayan generado incidencias automáticas
        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.incidentIds.length, 0, "No deberia haber incidencias para un envio valido");
    }

    function testVerifyTemperatureComplianceViolation() public {
        uint256 sid = _createColdChainShipment();
        vm.prank(carrier);
        // Grabamos una temperatura de 15°C (150), asumiendo rango 2-8°C
        logistics.recordCheckpoint(sid, "Sun Exposure", "Transit", "Hot", 150);

        assertFalse(logistics.verifyTemperatureCompliance(sid));
    }

    /**
     * @dev Simula una monitorización activa donde la temperatura es correcta al inicio pero sufre una desviación crítica en un punto intermedio.
     */
    function testColdChainMonitoring() public {
        // 1. Iniciamos un envío de productos biológicos
        uint256 sid = _createColdChainShipment();

        vm.startPrank(carrier);

        // Checkpoint 1: Todo correcto (5.0°C)
        logistics.recordCheckpoint(sid, "Laboratorio", "Pickup", "Carga inicial", 50);
        assertTrue(logistics.verifyTemperatureCompliance(sid), "It should be valid initially");

        // Checkpoint 2: Desviación crítica (12.0°C -> 120)
        // Nota: El rango es 20 a 80 (2°C a 8°C)
        logistics.recordCheckpoint(sid, "Aduana", "Transit", "Waiting on the tarmac without air conditioning", 120);

        // Checkpoint 3: Se recupera la temperatura (4.0°C)
        logistics.recordCheckpoint(sid, "Hub Destino", "Hub", "Return to the cold room", 40);

        vm.stopPrank();

        // 2. Verificación final de integridad
        // Aunque el último checkpoint sea correcto, la "historia" está manchada
        bool isCompliant = logistics.verifyTemperatureCompliance(sid);

        assertFalse(isCompliant, "The monitoring system should detect that the chain broke in step 2");

        // 3. Verificar que la incidencia automática persiste
        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertTrue(s.incidentIds.length > 0, "There must be a record of the thermal breach");

        LogisticsTracking.Incident memory inc = logistics.getIncident(s.incidentIds[0]);
        assertEq(uint256(inc.incidentType), uint256(LogisticsTracking.IncidentType.TempViolation));
    }

    // --- Tests de Confirmación de Entrega ---
    function testConfirmDeliveryByRecipient() public {
        uint256 sid = _createStandardShipment();
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
        assertTrue(s.dateDelivered > 0);
    }

    function testOnlyRecipientCanConfirmDelivery() public {
        uint256 sid = _createStandardShipment();
        vm.prank(stranger);
        vm.expectRevert("Only recipient can confirm");
        logistics.confirmDelivery(sid);
    }

    function testDeliveryUpdatesTimestamp() public {
        uint256 sid = _createStandardShipment();

        // Simulamos que la entrega ocurre en el segundo 5000
        uint256 deliveryTime = 5000;
        vm.warp(deliveryTime);

        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.dateDelivered, deliveryTime, "The delivery timestamp does not match");
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
    }

    function testCannotConfirmDeliveryTwice() public {
        uint256 sid = _createStandardShipment();

        // Primera entrega: Exitosa
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        // Segunda entrega: Debe fallar
        vm.prank(recipient);
        vm.expectRevert("Already delivered");
        logistics.confirmDelivery(sid);
    }

    // --- Tests de Incidencias ---
    function testReportDelayIncident() public {
        uint256 sid = _createStandardShipment();

        string memory delayReason = "Delay due to customs congestion";

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, delayReason);

        // Verificamos los datos de la incidencia
        LogisticsTracking.Incident memory incident = logistics.getIncident(incId);
        assertEq(uint256(incident.incidentType), uint256(LogisticsTracking.IncidentType.Delay));
        assertEq(incident.description, delayReason);
        assertEq(incident.reporter, carrier);
        assertFalse(incident.resolved);

        // Verificamos que el envio tenga el ID de la incidencia vinculado
        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.incidentIds.length, 1);
        assertEq(s.incidentIds[0], incId);
    }

    function testReportDamageIncident() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Damaged box");

        LogisticsTracking.Incident memory i = logistics.getIncident(incId);
        assertEq(i.description, "Damaged box");
        assertFalse(i.resolved);
    }

    function testReportLostIncident() public {
        uint256 sid = _createStandardShipment();

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(
            sid, LogisticsTracking.IncidentType.Lost, "Package not found on the truck after unloading"
        );

        LogisticsTracking.Incident memory incident = logistics.getIncident(incId);
        assertEq(uint256(incident.incidentType), uint256(LogisticsTracking.IncidentType.Lost));
        assertEq(incident.reporter, carrier);

        // El envío debe reflejar que tiene una incidencia vinculada
        assertEq(logistics.getShipment(sid).incidentIds.length, 1);
    }

    /**
     * @dev Verifica que el contrato genere una incidencia AUTOMÁTICA si la temperatura es inválida
     * Rango permitido en contrato: 2.0°C a 8.0°C (20 a 80)
     */
    function testReportTempViolation() public {
        // Creamos un envío que REQUIERE cadena de frío
        uint256 sid = _createColdChainShipment();

        // El transportista registra un checkpoint con 15.0°C (150), lo cual es una violación
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Almacen Transito", "Hub", "Failure in the cooling system", 150);

        // 1. Verificamos que la función de cumplimiento devuelva false
        assertFalse(logistics.verifyTemperatureCompliance(sid), "The cold chain must be broken");

        // 2. Verificamos que se haya creado una incidencia automáticamente
        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.incidentIds.length, 1, "There should be an automatic notification");

        uint256 autoIncId = s.incidentIds[0];
        LogisticsTracking.Incident memory inc = logistics.getIncident(autoIncId);

        assertEq(uint256(inc.incidentType), uint256(LogisticsTracking.IncidentType.TempViolation));
        assertEq(inc.description, "Temperature out of range");
    }

    function testResolveIncident() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Broken");

        vm.prank(admin);
        logistics.resolveIncident(incId);

        assertTrue(logistics.isIncidentResolved(incId));
    }

    function testGetShipmentIncidents() public {
        uint256 sid = _createStandardShipment();

        vm.startPrank(carrier);
        // Reportamos dos incidencias distintas
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, "Heavy traffic");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Damaged box");
        vm.stopPrank();

        LogisticsTracking.Incident[] memory incs = logistics.getShipmentIncidents(sid);

        assertEq(incs.length, 2, "There should be 2 incidents logged");
        assertEq(uint256(incs[0].incidentType), uint256(LogisticsTracking.IncidentType.Delay));
        assertEq(uint256(incs[1].incidentType), uint256(LogisticsTracking.IncidentType.Damage));
    }

    function testUnresolvedIncidentsList() public {
        uint256 sid = _createStandardShipment();

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Lost, "It doesn't appear");

        // Verificamos que inicialmente no está resuelta
        LogisticsTracking.Incident memory incBefore = logistics.getIncident(incId);
        assertFalse(incBefore.resolved, "The incident should be open initially");

        // El administrador la resuelve
        vm.prank(admin);
        logistics.resolveIncident(incId);

        // Verificamos que ahora aparezca como resuelta
        LogisticsTracking.Incident memory incAfter = logistics.getIncident(incId);
        assertTrue(incAfter.resolved, "The incident should be marked as resolved");
    }

    // --- Tests de Cancelación ---
    function testCancelShipment() public {
        uint256 sid = _createStandardShipment();
        vm.prank(sender);
        logistics.cancelShipment(sid);

        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Cancelled));
    }

    function testOnlySenderCanCancelShipment() public {
        uint256 sid = _createStandardShipment();

        // Intentamos cancelar con la cuenta del transportista (debe fallar)
        vm.prank(carrier);
        vm.expectRevert("Only sender can cancel");
        logistics.cancelShipment(sid);

        // Intentamos con una dirección externa aleatoria (debe fallar)
        vm.prank(address(0x999));
        vm.expectRevert("Only sender can cancel");
        logistics.cancelShipment(sid);

        // Verificamos que el estado sigue siendo "Created"
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Created));
    }

    function testCannotCancelDeliveredShipment() public {
        uint256 sid = _createStandardShipment();

        // 1. Completamos el flujo hasta la entrega
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        // Verificamos estado Delivered
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Delivered));

        // 2. El remitente intenta cancelar un envío ya entregado
        vm.prank(sender);
        // Según la lógica de nuestro contrato, solo se puede cancelar en estado "Created"
        vm.expectRevert("Cannot cancel after transit");
        logistics.cancelShipment(sid);
    }

    // --- Tests de Validaciones ---
    function testCannotRecordCheckpointForNonExistentShipment() public {
        _setupActors();
        uint256 nonExistentId = 999;

        vm.prank(carrier);
        // El modificador shipmentExists(_id) debe disparar el revert
        vm.expectRevert("Shipment does not exist");
        logistics.recordCheckpoint(nonExistentId, "Madrid", "Transit", "Error test", 200);
    }

    function testCannotReportIncidentForNonExistentShipment() public {
        _setupActors();
        uint256 nonExistentId = 888;

        vm.prank(carrier);
        vm.expectRevert("Shipment does not exist");
        logistics.reportIncident(nonExistentId, LogisticsTracking.IncidentType.Damage, "Derrame");
    }

    function testInactiveActorCannotRecordCheckpoint() public {
        uint256 sid = _createStandardShipment();

        // 1. El admin desactiva al transportista
        vm.prank(admin);
        logistics.deactivateActor(carrier);

        // 2. El transportista intenta registrar un movimiento
        vm.prank(carrier);
        // El modificador onlyActiveActor debe bloquearlo
        vm.expectRevert("Actor not registered or inactive");
        logistics.recordCheckpoint(sid, "Ruta", "Transit", "Intento ilegal", 200);
    }

    // --- Tests de casos EDGE ---
    /**
     * @dev Verifica que un envío pueda acumular múltiples movimientos sin errores.
     * Esto valida el crecimiento dinámico del array de checkpoints.
     */
    function testMultipleCheckpointsForSameShipment() public {
        uint256 sid = _createStandardShipment();
        vm.startPrank(carrier);

        // Registramos una secuencia de 5 movimientos
        for (uint256 i = 1; i <= 5; i++) {
            logistics.recordCheckpoint(
                sid, string(abi.encodePacked("Punto ", vm.toString(i))), "Transit", "Routine movement", 200
            );
        }
        vm.stopPrank();

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.checkpointIds.length, 5, "There should be 5 checkpoints");

        LogisticsTracking.Checkpoint[] memory history = logistics.getShipmentCheckpoints(sid);
        assertEq(history[4].location, "Punto 5", "The last checkpoint does not match");
    }

    /**
     * @dev Valida que un envío pueda registrar varias incidencias simultáneas
     * (p.ej. un retraso que luego deriva en un daño).
     */
    function testShipmentWithMultipleIncidents() public {
        uint256 sid = _createStandardShipment();
        vm.startPrank(carrier);

        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, "Traffic jam");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Wet box");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Unauthorized, "Broken seal");

        vm.stopPrank();

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.incidentIds.length, 3, "The shipment should have 3 associated issues");

        LogisticsTracking.Incident[] memory incs = logistics.getShipmentIncidents(sid);
        assertEq(uint256(incs[2].incidentType), uint256(LogisticsTracking.IncidentType.Unauthorized));
    }

    /**
     * @dev Verifica que el contrato acepte notas vacías. (a veces el sensor IoT no envía comentarios, solo datos).
     */
    function testEmptyCheckpointNotes() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier);

        // Enviamos una cadena vacía ""
        uint256 cid = logistics.recordCheckpoint(sid, "Hub", "Transit", "", 200);

        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(bytes(cp.notes).length, 0, "The field should be empty, but the save operation must succeed");
    }

    // --- Tests de Flujo Completo ---
    /**
     * @dev Test de Integración: Simula el ciclo de vida completo de un envío.
     * Flujo: Registro -> Creación -> Recogida -> Hub -> Reparto -> Entrega.
     */
    function testCompleteShippingFlow() public {
        // 1. Configuración de actores (Admin registra a todos)
        _setupActors();

        // 2. Origen: El remitente crea el envío
        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Smartphone X1", "Fabrica Shenzhen", "Tienda Madrid", false);
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Created));

        // 3. Recogida: El transportista lo recoge y cambia el estado a InTransit
        vm.startPrank(carrier);
        logistics.recordCheckpoint(sid, "Factory Outlet", "Pickup", "Loading onto a truck", 250);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        vm.stopPrank();
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.InTransit));

        // 4. Hub: El paquete llega al centro de distribución internacional
        vm.startPrank(hub);
        logistics.recordCheckpoint(sid, "Puerto Hong Kong", "Hub", "Customs clearance", 240);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        vm.stopPrank();
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.AtHub));

        // 5. Reparto: El transportista local lo marca como listo para entrega
        vm.startPrank(carrier);
        logistics.recordCheckpoint(sid, "Almacen Madrid", "Transit", "In a delivery truck", 220);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.OutForDelivery);
        vm.stopPrank();
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.OutForDelivery));

        // 6. Entrega Final: El destinatario confirma la recepción
        vm.warp(block.timestamp + 1 days); // Simulamos que pasó un día
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        // --- Verificaciones Finales ---
        LogisticsTracking.Shipment memory finalShipment = logistics.getShipment(sid);

        assertEq(uint256(finalShipment.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
        assertEq(finalShipment.checkpointIds.length, 3, "There should be 3 checkpoints recorded");
        assertTrue(
            finalShipment.dateDelivered > finalShipment.dateCreated,
            "The delivery date must be after the creation date"
        );

        // El historial debe ser legible y coherente
        LogisticsTracking.Checkpoint[] memory history = logistics.getShipmentCheckpoints(sid);
        assertEq(history[0].checkpointType, "Pickup");
        assertEq(history[2].checkpointType, "Transit");
    }

    function testPharmaceuticalColdChainFlow() public {
        _setupActors();

        // 1. Creación
        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Insulin", "Lab", "Clinic", true);

        // 2. Pickup
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Lab Loading Dock", "Pickup", "Temp check OK", 50);

        // 3. Hub
        vm.prank(hub);
        logistics.recordCheckpoint(sid, "Main Cold Hub", "Hub", "In fridge", 48);

        // 4. Delivery confirm
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        // Verificaciones
        assertTrue(logistics.verifyTemperatureCompliance(sid));
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
    }

    /**
     * @dev Simula un envío que pasa por múltiples Hubs logísticos.
     * Verifica la acumulación de datos y el cambio de actores en una ruta compleja.
     */
    function testMultiHubLogisticsFlow() public {
        _setupActors();

        // 1. Inicio: Envío internacional
        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Electronic Components", "Shanghai", "CDMX", false);

        // 2. Hub 1: Centro de consolidación en origen
        vm.prank(hub);
        logistics.recordCheckpoint(sid, "Hub Shanghai Port", "Hub", "Freight consolidation", 200);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);

        // 3. Tránsito Internacional: El transportista toma el relevo
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Pacific Ocean", "Transit", "On cargo ship", 180);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        // 4. Hub 2: Aduana y distribución en destino
        // Simulamos un segundo actor tipo Hub (usando una dirección distinta si fuera necesario)
        vm.prank(hub);
        logistics.recordCheckpoint(sid, "Hub Puerto Manzanillo", "Hub", "Customs clearance completed", 280);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);

        // 5. Última Milla: Transportista local
        vm.prank(carrier);
        logistics.recordCheckpoint(
            sid, "Local Distribution Center", "Transit", "Loaded onto a delivery truck", 250
        );
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.OutForDelivery);

        // 6. Finalización
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        // --- Validaciones de Complejidad ---
        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);

        // Verificamos que se hayan acumulado los 4 checkpoints de la ruta larga
        assertEq(s.checkpointIds.length, 4, "The route should have 4 checkpoints");

        // Verificamos el estado final de éxito
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));

        // Verificamos que el historial mantiene el orden de los Hubs
        LogisticsTracking.Checkpoint[] memory history = logistics.getShipmentCheckpoints(sid);
        assertEq(history[0].location, "Hub Shanghai Port");
        assertEq(history[2].location, "Hub Puerto Manzanillo");
    }

    // --- Helpers ---
    function _setupActors() internal {
        vm.prank(sender);
        logistics.registerActor("S", LogisticsTracking.ActorRole.Sender, "O");
        vm.prank(carrier);
        logistics.registerActor("C", LogisticsTracking.ActorRole.Carrier, "T");
        vm.prank(hub);
        logistics.registerActor("H", LogisticsTracking.ActorRole.Hub, "Z");
        vm.prank(recipient);
        logistics.registerActor("R", LogisticsTracking.ActorRole.Recipient, "D");
    }

    function _createStandardShipment() internal returns (uint256) {
        _setupActors();
        vm.prank(sender);
        return logistics.createShipment(recipient, "P", "O", "D", false);
    }

    function _createColdChainShipment() internal returns (uint256) {
        _setupActors();
        vm.prank(sender);
        return logistics.createShipment(recipient, "M", "O", "D", true);
    }

    /**
     * @dev Verifica que los datos almacenados en un checkpoint sean exactos.
     * Valida la correspondencia entre los argumentos de entrada y la estructura almacenada.
     */
    function testGetCheckpointData() public {
        // 1. Preparamos el escenario
        uint256 sid = _createStandardShipment();

        string memory expectedLocation = "Cargo Terminal T4";
        string memory expectedType = "Hub";
        string memory expectedNotes = "Package inspected by X-ray";
        int256 expectedTemp = 215; // 21.5°C

        // 2. Ejecutamos la acción como un actor registrado (Carrier)
        vm.prank(carrier);
        uint256 cid = logistics.recordCheckpoint(sid, expectedLocation, expectedType, expectedNotes, expectedTemp);

        // 3. Recuperamos los datos usando la función getCheckpoint
        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);

        // 4. Verificaciones (Assertions)
        assertEq(cp.id, cid, "Checkpoint ID does not match");
        assertEq(cp.shipmentId, sid, "Linked shipment ID is incorrect");
        assertEq(cp.location, expectedLocation, "Location does not match");
        assertEq(cp.checkpointType, expectedType, "Checkpoint type is incorrect");
        assertEq(cp.notes, expectedNotes, "The notes does not match");
        assertEq(cp.temperature, expectedTemp, "Recorded temperature is incorrect");
        assertEq(cp.actor, carrier, "Sender of the checkpoint must be the carrier");
        assertTrue(cp.timestamp > 0, "Timestamp should have been generated");
    }
}
