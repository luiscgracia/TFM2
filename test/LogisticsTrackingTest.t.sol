// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {LogisticsTracking} from "../src/LogisticsTracking.sol";

contract LogisticsTrackingTest is Test {
    LogisticsTracking public logistics;

    address admin = address(0xAD);
    address sender = address(0x1);
    address carrier = address(0x2);
    address hub = address(0x3);
    address recipient = address(0x4);
    address stranger = address(0x5);
    address sender2 = address(0x6);

    // -------------------------------------------------------------------------
    // Eventos — firmas exactas del contrato v4
    // -------------------------------------------------------------------------
    event ShipmentCreated(
        uint256 indexed shipmentId, address indexed sender, address indexed recipient, string product
    );
    event CheckpointRecorded(
        uint256 indexed checkpointId,
        uint256 indexed shipmentId,
        LogisticsTracking.CheckpointType checkpointType,
        address actor
    );
    event ShipmentStatusChanged(uint256 indexed shipmentId, LogisticsTracking.ShipmentStatus newStatus);
    event IncidentReported(
        uint256 indexed incidentId, uint256 indexed shipmentId, LogisticsTracking.IncidentType incidentType
    );
    event IncidentResolved(uint256 indexed incidentId, string resolutionNote);
    event DeliveryConfirmed(uint256 indexed shipmentId, address indexed recipient, uint256 timestamp);
    event ActorRegistered(address indexed actorAddress, string name, LogisticsTracking.ActorRole role);

    function setUp() public {
        vm.prank(admin);
        logistics = new LogisticsTracking();
    }

    // =========================================================================
    // Tests de Gestión de Actores
    // =========================================================================

    function testRegisterSender() public {
        vm.prank(admin);
        logistics.registerActor("Sender Corp", LogisticsTracking.ActorRole.Sender, "Madrid", sender);
        LogisticsTracking.Actor memory a = logistics.getActor(sender);
        assertEq(uint256(a.role), uint256(LogisticsTracking.ActorRole.Sender));
        assertTrue(a.isActive);
    }

    function testRegisterCarrier() public {
        vm.prank(admin);
        logistics.registerActor("Fast Truck", LogisticsTracking.ActorRole.Carrier, "Valencia", carrier);
        assertEq(uint256(logistics.getActor(carrier).role), uint256(LogisticsTracking.ActorRole.Carrier));
    }

    function testRegisterHub() public {
        vm.prank(admin);
        logistics.registerActor("Main Hub", LogisticsTracking.ActorRole.Hub, "Zaragoza", hub);
        assertEq(uint256(logistics.getActor(hub).role), uint256(LogisticsTracking.ActorRole.Hub));
    }

    function testRegisterRecipient() public {
        vm.prank(admin);
        logistics.registerActor("End User", LogisticsTracking.ActorRole.Recipient, "Barcelona", recipient);
        assertEq(uint256(logistics.getActor(recipient).role), uint256(LogisticsTracking.ActorRole.Recipient));
    }

    function testDeactivateActor() public {
        vm.prank(admin);
        logistics.registerActor("Temp", LogisticsTracking.ActorRole.Sender, "Loc", sender);
        vm.prank(admin);
        logistics.deactivateActor(sender);
        assertFalse(logistics.getActor(sender).isActive);
    }

    function testOnlyAdminCanRegisterActor() public {
        vm.prank(sender);
        vm.expectRevert(LogisticsTracking.OnlyAdmin.selector);
        logistics.registerActor("Hacker", LogisticsTracking.ActorRole.Sender, "X", sender);
    }

    function testCannotRegisterActorTwice() public {
        vm.startPrank(admin);
        logistics.registerActor("Sender Corp", LogisticsTracking.ActorRole.Sender, "Madrid", sender);
        vm.expectRevert(LogisticsTracking.AlreadyRegisteredAndActive.selector);
        logistics.registerActor("Sender Corp Again", LogisticsTracking.ActorRole.Sender, "Madrid", sender);
        vm.stopPrank();
    }

    function testGetUnregisteredActorReturnsEmpty() public view {
        LogisticsTracking.Actor memory a = logistics.getActor(address(0x999));
        assertFalse(a.isActive, "Un actor no registrado debe tener isActive = false");
    }

    function testReactivateActor() public {
        vm.startPrank(admin);
        logistics.registerActor("Temp", LogisticsTracking.ActorRole.Carrier, "Loc", carrier);
        logistics.deactivateActor(carrier);
        assertFalse(logistics.getActor(carrier).isActive);
        logistics.reactivateActor(carrier);
        assertTrue(logistics.getActor(carrier).isActive);
        vm.stopPrank();
    }

    function testRegisterActorEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ActorRegistered(sender, "Sender Corp", LogisticsTracking.ActorRole.Sender);
        vm.prank(admin);
        logistics.registerActor("Sender Corp", LogisticsTracking.ActorRole.Sender, "Madrid", sender);
    }

    // =========================================================================
    // Tests de Gestión de Admin (transferencia en dos pasos)
    // =========================================================================

    function testProposeAndAcceptAdmin() public {
        address newAdmin = address(0xBB);
        vm.prank(admin);
        logistics.proposeAdmin(newAdmin);
        assertEq(logistics.pendingAdmin(), newAdmin);
        vm.prank(newAdmin);
        logistics.acceptAdmin();
        assertEq(logistics.admin(), newAdmin);
        assertEq(logistics.pendingAdmin(), address(0));
    }

    function testOnlyAdminCanProposeAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(LogisticsTracking.OnlyAdmin.selector);
        logistics.proposeAdmin(address(0xBB));
    }

    function testOnlyPendingAdminCanAccept() public {
        vm.prank(admin);
        logistics.proposeAdmin(address(0xBB));
        vm.prank(stranger);
        vm.expectRevert(LogisticsTracking.NotPendingAdmin.selector);
        logistics.acceptAdmin();
    }

    // =========================================================================
    // Tests de Creación de Envíos
    // =========================================================================

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
        uint256 sid =
            logistics.createShipment(recipient, "Vacunas Termosensibles", "Laboratorio Bio", "Hospital Central", true);
        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertTrue(s.requiresColdChain);
        assertEq(s.product, "Vacunas Termosensibles");
    }

    function testShipmentIdIncrementation() public {
        _setupActors();
        vm.startPrank(sender);
        uint256 id1 = logistics.createShipment(recipient, "Prod 1", "O", "D", false);
        uint256 id2 = logistics.createShipment(recipient, "Prod 2", "O", "D", false);
        uint256 id3 = logistics.createShipment(recipient, "Prod 3", "O", "D", false);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(logistics.nextShipmentId(), 4);
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
        assertEq(s.checkpointIds.length, 0);
    }

    function testOnlySenderCanCreateShipment() public {
        _setupActors();
        vm.prank(carrier);
        vm.expectRevert(LogisticsTracking.OnlySendersCanCreate.selector);
        logistics.createShipment(recipient, "Bad", "A", "B", false);
    }

    function testCreateShipmentEmitsEvent() public {
        _setupActors();
        vm.expectEmit(true, true, true, true);
        emit ShipmentCreated(1, sender, recipient, "Tablet");
        vm.prank(sender);
        logistics.createShipment(recipient, "Tablet", "Origin", "Dest", false);
    }

    function testMultipleSendersCreateIndependentShipments() public {
        _setupActors();
        vm.prank(admin);
        logistics.registerActor("Sender 2", LogisticsTracking.ActorRole.Sender, "Sevilla", sender2);

        vm.prank(sender);
        uint256 sid1 = logistics.createShipment(recipient, "Prod A", "O1", "D1", false);
        vm.prank(sender2);
        uint256 sid2 = logistics.createShipment(recipient, "Prod B", "O2", "D2", false);

        assertEq(logistics.getShipment(sid1).sender, sender);
        assertEq(logistics.getShipment(sid2).sender, sender2);
        assertTrue(sid1 != sid2);
    }

    // =========================================================================
    // Tests de Checkpoints
    // [C-2] carrier y hub deben estar asignados al envío antes de registrar checkpoints.
    //       Se asignan llamando a updateShipmentStatus, que invoca _addActorShipment.
    // =========================================================================

    function testRecordPickupCheckpoint() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(
            sid, "Warehouse A", LogisticsTracking.CheckpointType.Pickup, "Picked up by truck 1", 250
        );
        LogisticsTracking.Checkpoint[] memory cps = logistics.getAllShipmentCheckpoints(sid);
        assertEq(cps.length, 1);
        assertEq(uint256(cps[0].checkpointType), uint256(LogisticsTracking.CheckpointType.Pickup));
    }

    function testRecordHubCheckpoint() public {
        uint256 sid = _createStandardShipment();
        // Asignar hub al envío [C-2]
        vm.prank(hub);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);

        vm.prank(hub);
        uint256 cid = logistics.recordCheckpoint(
            sid, "Hub Logistico Norte", LogisticsTracking.CheckpointType.Hub, "Paquete clasificado", 220
        );
        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(uint256(cp.checkpointType), uint256(LogisticsTracking.CheckpointType.Hub));
        assertEq(cp.actor, hub);
        assertEq(logistics.getAllShipmentCheckpoints(sid).length, 1);
    }

    function testRecordTransitCheckpoint() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 cid = logistics.recordCheckpoint(
            sid, "Autopista AP-7", LogisticsTracking.CheckpointType.Transit, "Camion en movimiento", 215
        );
        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(uint256(cp.checkpointType), uint256(LogisticsTracking.CheckpointType.Transit));
        assertEq(cp.location, "Autopista AP-7");
    }

    function testRecordDeliveryCheckpoint() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 cid = logistics.recordCheckpoint(
            sid, "Puerta del Destinatario", LogisticsTracking.CheckpointType.Delivery, "En camino", 230
        );
        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(uint256(cp.checkpointType), uint256(LogisticsTracking.CheckpointType.Delivery));

        LogisticsTracking.Checkpoint[] memory history = logistics.getAllShipmentCheckpoints(sid);
        assertEq(
            uint256(history[history.length - 1].checkpointType), uint256(LogisticsTracking.CheckpointType.Delivery)
        );
    }

    function testRecordCheckpointWithTemperature() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Fridge Truck", LogisticsTracking.CheckpointType.Transit, "Stable", 42);
        assertEq(logistics.getAllShipmentCheckpoints(sid)[0].temperature, 42);
    }

    function testGetShipmentCheckpoints() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        logistics.recordCheckpoint(sid, "Origen", LogisticsTracking.CheckpointType.Pickup, "Carga", 200);
        logistics.recordCheckpoint(sid, "Ruta 1", LogisticsTracking.CheckpointType.Transit, "En viaje", 210);
        logistics.recordCheckpoint(sid, "Hub A", LogisticsTracking.CheckpointType.Hub, "Descarga", 205);
        vm.stopPrank();

        LogisticsTracking.Checkpoint[] memory all = logistics.getAllShipmentCheckpoints(sid);
        assertEq(all.length, 3);
        assertEq(all[0].location, "Origen");
        assertEq(all[1].location, "Ruta 1");
        assertEq(all[2].location, "Hub A");
    }

    function testGetShipmentCheckpointsPaginated() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        for (uint256 i = 0; i < 5; i++) {
            logistics.recordCheckpoint(
                sid,
                string(abi.encodePacked("Punto ", vm.toString(i + 1))),
                LogisticsTracking.CheckpointType.Transit,
                "",
                200
            );
        }
        vm.stopPrank();

        LogisticsTracking.Checkpoint[] memory page0 = logistics.getShipmentCheckpoints(sid, 0, 3);
        assertEq(page0.length, 3);
        assertEq(page0[0].location, "Punto 1");
        assertEq(page0[2].location, "Punto 3");

        LogisticsTracking.Checkpoint[] memory page1 = logistics.getShipmentCheckpoints(sid, 3, 3);
        assertEq(page1.length, 2);
        assertEq(page1[0].location, "Punto 4");
        assertEq(page1[1].location, "Punto 5");

        LogisticsTracking.Checkpoint[] memory empty = logistics.getShipmentCheckpoints(sid, 99, 3);
        assertEq(empty.length, 0);
    }

    function testCheckpointTimeline() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.warp(1000);
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Punto A", LogisticsTracking.CheckpointType.Pickup, "Inicio", 200);

        vm.warp(2000);
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Punto B", LogisticsTracking.CheckpointType.Transit, "Sigue", 210);

        LogisticsTracking.Checkpoint[] memory timeline = logistics.getAllShipmentCheckpoints(sid);
        assertEq(timeline[0].timestamp, 1000);
        assertEq(timeline[1].timestamp, 2000);
        assertTrue(timeline[1].timestamp > timeline[0].timestamp);
    }

    function testRecordCheckpointEmitsEvent() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 cid = logistics.recordCheckpoint(sid, "Hub", LogisticsTracking.CheckpointType.Transit, "En ruta", 200);
        assertEq(cid, 1);

        vm.expectEmit(true, true, false, true);
        emit CheckpointRecorded(2, sid, LogisticsTracking.CheckpointType.Hub, carrier);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Hub 2", LogisticsTracking.CheckpointType.Hub, "En ruta 2", 200);
    }

    // =========================================================================
    // Tests de Temperatura
    // =========================================================================

    function testVerifyTemperatureComplianceValid() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        logistics.recordCheckpoint(sid, "Origen", LogisticsTracking.CheckpointType.Pickup, "Carga fria", 40);
        logistics.recordCheckpoint(sid, "Ruta A", LogisticsTracking.CheckpointType.Transit, "En trayecto", 55);
        logistics.recordCheckpoint(sid, "Hub", LogisticsTracking.CheckpointType.Hub, "Almacenaje", 30);
        vm.stopPrank();

        assertTrue(logistics.verifyTemperatureCompliance(sid));
        assertEq(logistics.getShipment(sid).incidentIds.length, 0);
    }

    function testVerifyTemperatureComplianceViolation() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Sun Exposure", LogisticsTracking.CheckpointType.Transit, "Hot", 150);
        assertFalse(logistics.verifyTemperatureCompliance(sid));
    }

    function testColdChainMonitoring() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        logistics.recordCheckpoint(sid, "Laboratorio", LogisticsTracking.CheckpointType.Pickup, "Carga inicial", 50);
        assertTrue(logistics.verifyTemperatureCompliance(sid));
        logistics.recordCheckpoint(sid, "Aduana", LogisticsTracking.CheckpointType.Transit, "Sin aire", 120);
        logistics.recordCheckpoint(sid, "Hub Destino", LogisticsTracking.CheckpointType.Hub, "Vuelta camara", 40);
        vm.stopPrank();

        assertFalse(logistics.verifyTemperatureCompliance(sid));
        assertTrue(logistics.getShipment(sid).incidentIds.length > 0);

        LogisticsTracking.Incident memory inc = logistics.getIncident(logistics.getShipment(sid).incidentIds[0]);
        assertEq(uint256(inc.incidentType), uint256(LogisticsTracking.IncidentType.TempViolation));
    }

    function testNegativeTemperatureTriggersViolation() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Camara Fria", LogisticsTracking.CheckpointType.Transit, "Sensor negativo", -50);

        assertFalse(logistics.verifyTemperatureCompliance(sid));
        assertEq(logistics.getShipment(sid).incidentIds.length, 1);
        assertEq(
            uint256(logistics.getIncident(logistics.getShipment(sid).incidentIds[0]).incidentType),
            uint256(LogisticsTracking.IncidentType.TempViolation)
        );
    }

    function testTemperatureAtLowerBoundIsValid() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Camara", LogisticsTracking.CheckpointType.Transit, "Limite inferior", 20);

        assertTrue(logistics.verifyTemperatureCompliance(sid));
        assertEq(logistics.getShipment(sid).incidentIds.length, 0);
    }

    function testTemperatureAtUpperBoundIsValid() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Camara", LogisticsTracking.CheckpointType.Transit, "Limite superior", 80);

        assertTrue(logistics.verifyTemperatureCompliance(sid));
        assertEq(logistics.getShipment(sid).incidentIds.length, 0);
    }

    function testTemperatureOneAboveUpperBoundViolates() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Camara", LogisticsTracking.CheckpointType.Transit, "Un grado de mas", 81);

        assertFalse(logistics.verifyTemperatureCompliance(sid));
        assertEq(logistics.getShipment(sid).incidentIds.length, 1);
    }

    function testNonColdChainShipmentIgnoresTemperature() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Almacen", LogisticsTracking.CheckpointType.Transit, "Ambiente", 300);

        assertTrue(logistics.verifyTemperatureCompliance(sid));
        assertEq(logistics.getShipment(sid).incidentIds.length, 0);
    }

    // =========================================================================
    // Tests de Confirmación de Entrega
    // =========================================================================

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
        vm.expectRevert(LogisticsTracking.OnlyRecipientCanConfirm.selector);
        logistics.confirmDelivery(sid);
    }

    function testDeliveryUpdatesTimestamp() public {
        uint256 sid = _createStandardShipment();
        vm.warp(5000);
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.dateDelivered, 5000);
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
    }

    function testCannotConfirmDeliveryTwice() public {
        uint256 sid = _createStandardShipment();
        vm.prank(recipient);
        logistics.confirmDelivery(sid);
        vm.prank(recipient);
        vm.expectRevert(LogisticsTracking.AlreadyDelivered.selector);
        logistics.confirmDelivery(sid);
    }

    function testConfirmDeliveryEmitsEvent() public {
        uint256 sid = _createStandardShipment();
        vm.warp(9999);
        vm.expectEmit(true, true, false, true);
        emit DeliveryConfirmed(sid, recipient, 9999);
        vm.prank(recipient);
        logistics.confirmDelivery(sid);
    }

    // =========================================================================
    // Tests de Incidencias
    // =========================================================================

    function testReportDelayIncident() public {
        uint256 sid = _createStandardShipment();
        string memory reason = "Delay due to customs congestion";
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, reason);

        LogisticsTracking.Incident memory inc = logistics.getIncident(incId);
        assertEq(uint256(inc.incidentType), uint256(LogisticsTracking.IncidentType.Delay));
        assertEq(inc.description, reason);
        assertEq(inc.reporter, carrier);
        assertFalse(inc.resolved);

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.incidentIds.length, 1);
        assertEq(s.incidentIds[0], incId);
    }

    function testReportDamageIncident() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Damaged box");
        assertEq(logistics.getIncident(incId).description, "Damaged box");
        assertFalse(logistics.getIncident(incId).resolved);
    }

    function testReportLostIncident() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 incId =
            logistics.reportIncident(sid, LogisticsTracking.IncidentType.Lost, "Package not found after unloading");
        assertEq(uint256(logistics.getIncident(incId).incidentType), uint256(LogisticsTracking.IncidentType.Lost));
        assertEq(logistics.getShipment(sid).incidentIds.length, 1);
    }

    function testReportTempViolation() public {
        uint256 sid = _createColdChainShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        logistics.recordCheckpoint(
            sid, "Almacen Transito", LogisticsTracking.CheckpointType.Hub, "Fallo refrigeracion", 150
        );

        assertFalse(logistics.verifyTemperatureCompliance(sid));

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.incidentIds.length, 1);

        LogisticsTracking.Incident memory inc = logistics.getIncident(s.incidentIds[0]);
        assertEq(uint256(inc.incidentType), uint256(LogisticsTracking.IncidentType.TempViolation));
        assertEq(inc.description, "Temperature out of range");
    }

    function testResolveIncident() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Broken");
        vm.prank(admin);
        logistics.resolveIncident(incId, "Paquete revisado y reemplazado por el carrier");
        assertTrue(logistics.isIncidentResolved(incId));
    }

    function testGetShipmentIncidents() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, "Heavy traffic");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Damaged box");
        vm.stopPrank();

        LogisticsTracking.Incident[] memory incs = logistics.getAllShipmentIncidents(sid);
        assertEq(incs.length, 2);
        assertEq(uint256(incs[0].incidentType), uint256(LogisticsTracking.IncidentType.Delay));
        assertEq(uint256(incs[1].incidentType), uint256(LogisticsTracking.IncidentType.Damage));
    }

    function testGetShipmentIncidentsPaginated() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, "Retraso");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Dano");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Unauthorized, "Sello roto");
        vm.stopPrank();

        LogisticsTracking.Incident[] memory page = logistics.getShipmentIncidents(sid, 1, 2);
        assertEq(page.length, 2);
        assertEq(uint256(page[0].incidentType), uint256(LogisticsTracking.IncidentType.Damage));
    }

    function testUnresolvedThenResolvedIncident() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Lost, "No aparece");
        assertFalse(logistics.getIncident(incId).resolved);
        vm.prank(admin);
        logistics.resolveIncident(incId, "Paquete localizado y reenviado al destinatario");
        assertTrue(logistics.getIncident(incId).resolved);
        assertEq(logistics.getIncident(incId).resolutionNote, "Paquete localizado y reenviado al destinatario");
    }

    function testReportIncidentEmitsEvent() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.expectEmit(true, true, false, true);
        emit IncidentReported(1, sid, LogisticsTracking.IncidentType.Delay);
        vm.prank(carrier);
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, unicode"Tráfico");
    }

    function testResolveIncidentEmitsEvent() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Roto");
        vm.expectEmit(true, false, false, true);
        emit IncidentResolved(incId, "Caja inspeccionada y reempacada correctamente");
        vm.prank(admin);
        logistics.resolveIncident(incId, "Caja inspeccionada y reempacada correctamente");
    }

    // =========================================================================
    // Tests de Cancelación
    // =========================================================================

    function testCancelShipment() public {
        uint256 sid = _createStandardShipment();
        vm.prank(sender);
        logistics.cancelShipment(sid);
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Cancelled));
    }

    function testOnlySenderCanCancelShipment() public {
        uint256 sid = _createStandardShipment();

        vm.prank(carrier);
        vm.expectRevert(LogisticsTracking.OnlySenderCanCancel.selector);
        logistics.cancelShipment(sid);

        vm.prank(address(0x999));
        vm.expectRevert(LogisticsTracking.OnlySenderCanCancel.selector);
        logistics.cancelShipment(sid);

        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Created));
    }

    // [W-1] v4 lanza AlreadyClosedShipment para estados terminales (Delivered, Returned, Cancelled)
    function testCannotCancelDeliveredShipment() public {
        uint256 sid = _createStandardShipment();
        vm.prank(recipient);
        logistics.confirmDelivery(sid);
        vm.prank(sender);
        vm.expectRevert(LogisticsTracking.AlreadyClosedShipment.selector);
        logistics.cancelShipment(sid);
    }

    // [C-2] El actor debe estar asignado al envío para registrar checkpoints.
    // [W-1] Solo se puede cancelar desde Created o AtHub.
    // Estrategia: asignar hub via AtHub (estado cancelable), cancelar, luego hub registra checkpoint.
    function testCancelledShipmentStillAcceptsCheckpoints() public {
        uint256 sid = _createStandardShipment();
        // Asignar hub al envío moviéndolo a AtHub (estado aún cancelable) [C-2] [W-1]
        vm.prank(hub);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);

        // Cancelar desde AtHub (permitido por [W-1])
        vm.prank(sender);
        logistics.cancelShipment(sid);
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Cancelled));

        // El hub ya está asignado y puede registrar checkpoints post-cancelación
        vm.prank(hub);
        logistics.recordCheckpoint(sid, "Ruta", LogisticsTracking.CheckpointType.Transit, "Post-cancelacion", 200);
        assertEq(logistics.getAllShipmentCheckpoints(sid).length, 1);
    }

    function testCancelShipmentEmitsEvent() public {
        uint256 sid = _createStandardShipment();
        vm.expectEmit(true, false, false, true);
        emit ShipmentStatusChanged(sid, LogisticsTracking.ShipmentStatus.Cancelled);
        vm.prank(sender);
        logistics.cancelShipment(sid);
    }

    // =========================================================================
    // Tests de Control de Acceso — updateShipmentStatus
    // =========================================================================

    function testOnlyCarrierOrHubCanUpdateStatus() public {
        uint256 sid = _createStandardShipment();

        vm.prank(sender);
        vm.expectRevert(LogisticsTracking.OnlyCarrierOrHub.selector);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(recipient);
        vm.expectRevert(LogisticsTracking.OnlyCarrierOrHub.selector);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(stranger);
        vm.expectRevert(LogisticsTracking.ActorInactive.selector);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
    }

    function testCarrierCanUpdateStatusToInTransit() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.InTransit));
    }

    function testHubCanUpdateStatusToAtHub() public {
        uint256 sid = _createStandardShipment();
        vm.prank(hub);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.AtHub));
    }

    function testCannotUpdateStatusToDeliveredDirectly() public {
        uint256 sid = _createStandardShipment();
        vm.prank(carrier);
        vm.expectRevert(LogisticsTracking.CannotSetDeliveredDirectly.selector);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.Delivered);
    }

    // =========================================================================
    // Tests de Validaciones
    // =========================================================================

    function testCannotRecordCheckpointForNonExistentShipment() public {
        _setupActors();
        vm.prank(carrier);
        vm.expectRevert(abi.encodeWithSelector(LogisticsTracking.ShipmentNotFound.selector, uint256(999)));
        logistics.recordCheckpoint(999, "Madrid", LogisticsTracking.CheckpointType.Transit, "Error test", 200);
    }

    function testCannotReportIncidentForNonExistentShipment() public {
        _setupActors();
        vm.prank(carrier);
        vm.expectRevert(abi.encodeWithSelector(LogisticsTracking.ShipmentNotFound.selector, uint256(888)));
        logistics.reportIncident(888, LogisticsTracking.IncidentType.Damage, "Derrame");
    }

    function testInactiveActorCannotRecordCheckpoint() public {
        uint256 sid = _createStandardShipment();
        vm.prank(admin);
        logistics.deactivateActor(carrier);
        vm.prank(carrier);
        vm.expectRevert(LogisticsTracking.ActorInactive.selector);
        logistics.recordCheckpoint(sid, "Ruta", LogisticsTracking.CheckpointType.Transit, "Intento ilegal", 200);
    }

    // =========================================================================
    // Tests de Casos EDGE
    // =========================================================================

    function testMultipleCheckpointsForSameShipment() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        for (uint256 i = 1; i <= 5; i++) {
            logistics.recordCheckpoint(
                sid,
                string(abi.encodePacked("Punto ", vm.toString(i))),
                LogisticsTracking.CheckpointType.Transit,
                "Movimiento rutinario",
                200
            );
        }
        vm.stopPrank();

        assertEq(logistics.getShipment(sid).checkpointIds.length, 5);
        assertEq(logistics.getAllShipmentCheckpoints(sid)[4].location, "Punto 5");
    }

    function testShipmentWithMultipleIncidents() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.startPrank(carrier);
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Delay, "Traffic jam");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Wet box");
        logistics.reportIncident(sid, LogisticsTracking.IncidentType.Unauthorized, "Broken seal");
        vm.stopPrank();

        assertEq(logistics.getShipment(sid).incidentIds.length, 3);
        assertEq(
            uint256(logistics.getAllShipmentIncidents(sid)[2].incidentType),
            uint256(LogisticsTracking.IncidentType.Unauthorized)
        );
    }

    function testEmptyCheckpointNotes() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        vm.prank(carrier);
        uint256 cid = logistics.recordCheckpoint(sid, "Hub", LogisticsTracking.CheckpointType.Transit, "", 200);
        assertEq(bytes(logistics.getCheckpoint(cid).notes).length, 0);
    }

    // =========================================================================
    // Tests de Flujos Completos
    // =========================================================================

    function testCompleteShippingFlow() public {
        _setupActors();

        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Smartphone X1", "Shenzhen", "Madrid", false);
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Created));

        vm.startPrank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        logistics.recordCheckpoint(sid, "Factory Outlet", LogisticsTracking.CheckpointType.Pickup, "Cargando", 250);
        vm.stopPrank();

        vm.startPrank(hub);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        logistics.recordCheckpoint(sid, "Puerto Hong Kong", LogisticsTracking.CheckpointType.Hub, "Aduana", 240);
        vm.stopPrank();

        vm.startPrank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.OutForDelivery);
        logistics.recordCheckpoint(sid, "Almacen Madrid", LogisticsTracking.CheckpointType.Transit, "Reparto", 220);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        LogisticsTracking.Shipment memory final_ = logistics.getShipment(sid);
        assertEq(uint256(final_.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
        assertEq(final_.checkpointIds.length, 3);
        assertTrue(final_.dateDelivered > final_.dateCreated);

        LogisticsTracking.Checkpoint[] memory history = logistics.getAllShipmentCheckpoints(sid);
        assertEq(uint256(history[0].checkpointType), uint256(LogisticsTracking.CheckpointType.Pickup));
        assertEq(uint256(history[2].checkpointType), uint256(LogisticsTracking.CheckpointType.Transit));
    }

    function testPharmaceuticalColdChainFlow() public {
        _setupActors();

        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Insulin", "Lab", "Clinic", true);

        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        vm.prank(carrier);
        logistics.recordCheckpoint(sid, "Lab Loading Dock", LogisticsTracking.CheckpointType.Pickup, "Temp OK", 50);

        vm.prank(hub);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        vm.prank(hub);
        logistics.recordCheckpoint(sid, "Main Cold Hub", LogisticsTracking.CheckpointType.Hub, "In fridge", 48);

        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        assertTrue(logistics.verifyTemperatureCompliance(sid));
        assertEq(uint256(logistics.getShipment(sid).status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
    }

    function testMultiHubLogisticsFlow() public {
        _setupActors();

        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Electronic Components", "Shanghai", "CDMX", false);

        vm.startPrank(hub);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        logistics.recordCheckpoint(sid, "Hub Shanghai Port", LogisticsTracking.CheckpointType.Hub, "Consolidacion", 200);
        vm.stopPrank();

        vm.startPrank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        logistics.recordCheckpoint(sid, "Pacific Ocean", LogisticsTracking.CheckpointType.Transit, "Cargo ship", 180);
        vm.stopPrank();

        vm.startPrank(hub);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.AtHub);
        logistics.recordCheckpoint(sid, "Hub Puerto Manzanillo", LogisticsTracking.CheckpointType.Hub, "Aduana OK", 280);
        vm.stopPrank();

        vm.startPrank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.OutForDelivery);
        logistics.recordCheckpoint(sid, "Local Distribution", LogisticsTracking.CheckpointType.Transit, "Reparto", 250);
        vm.stopPrank();

        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(s.checkpointIds.length, 4);
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));

        LogisticsTracking.Checkpoint[] memory history = logistics.getAllShipmentCheckpoints(sid);
        assertEq(history[0].location, "Hub Shanghai Port");
        assertEq(history[2].location, "Hub Puerto Manzanillo");
    }

    function testFlowWithIncidentResolution() public {
        _setupActors();

        vm.prank(sender);
        uint256 sid = logistics.createShipment(recipient, "Maquinaria", "Fabrica", "Obra", false);

        vm.startPrank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);
        logistics.recordCheckpoint(sid, "Fabrica", LogisticsTracking.CheckpointType.Pickup, "Cargado", 200);
        vm.stopPrank();

        vm.prank(carrier);
        uint256 incId = logistics.reportIncident(sid, LogisticsTracking.IncidentType.Damage, "Caja golpeada");
        assertFalse(logistics.isIncidentResolved(incId));

        vm.prank(admin);
        logistics.resolveIncident(incId, unicode"Caja golpeada revisada, contenido sin daño mayor");
        assertTrue(logistics.isIncidentResolved(incId));

        vm.prank(recipient);
        logistics.confirmDelivery(sid);

        LogisticsTracking.Shipment memory s = logistics.getShipment(sid);
        assertEq(uint256(s.status), uint256(LogisticsTracking.ShipmentStatus.Delivered));
        assertEq(s.incidentIds.length, 1);
    }

    // =========================================================================
    // Test de datos de checkpoint
    // =========================================================================

    function testGetCheckpointData() public {
        uint256 sid = _createStandardShipment();
        // Asignar carrier al envío [C-2]
        vm.prank(carrier);
        logistics.updateShipmentStatus(sid, LogisticsTracking.ShipmentStatus.InTransit);

        int256 expectedTemp = 215;
        vm.prank(carrier);
        uint256 cid = logistics.recordCheckpoint(
            sid, "Cargo Terminal T4", LogisticsTracking.CheckpointType.Hub, "Package inspected by X-ray", expectedTemp
        );

        LogisticsTracking.Checkpoint memory cp = logistics.getCheckpoint(cid);
        assertEq(cp.id, cid);
        assertEq(cp.shipmentId, sid);
        assertEq(cp.actor, carrier);
        assertEq(cp.location, "Cargo Terminal T4");
        assertEq(uint256(cp.checkpointType), uint256(LogisticsTracking.CheckpointType.Hub));
        assertEq(cp.notes, "Package inspected by X-ray");
        assertEq(cp.temperature, expectedTemp);
        assertTrue(cp.timestamp > 0);
    }

    // =========================================================================
    // Helpers internos
    // =========================================================================

    function _setupActors() internal {
        vm.startPrank(admin);
        logistics.registerActor("S", LogisticsTracking.ActorRole.Sender, "O", sender);
        logistics.registerActor("C", LogisticsTracking.ActorRole.Carrier, "T", carrier);
        logistics.registerActor("H", LogisticsTracking.ActorRole.Hub, "Z", hub);
        logistics.registerActor("R", LogisticsTracking.ActorRole.Recipient, "D", recipient);
        vm.stopPrank();
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
}
