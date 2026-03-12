// sc/test/LogisticsTracking.t.sol
import "ds-test/Test.sol";
import "../src/LogisticsTracking.sol";

contract LogisticsTrackingTest is Test {
    LogisticsTracking public logistics;
    address admin = address(1);
    address sender = address(2);
    address carrier = address(3);
    address recipient = address(4);

    function setUp() public {
        vm.prank(admin);
        logistics = new LogisticsTracking();
        
        vm.prank(sender);
        logistics.registerActor("FarmaCorp", LogisticsTracking.ActorRole.Sender, "Madrid");
        
        vm.prank(carrier);
        logistics.registerActor("FastLogistics", LogisticsTracking.ActorRole.Carrier, unicode"Logroño");
    }

    function testCreateShipment() public {
        vm.prank(sender);
        uint256 id = logistics.createShipment(recipient, "Vacunas", "Lab A", "Hospital B", true);
        
        LogisticsTracking.Shipment memory s = logistics.getShipment(id);
        assertEq(s.product, "Vacunas");
        assertEq(uint(s.status), uint(LogisticsTracking.ShipmentStatus.Created));
    }

    function testRecordCheckpointWithTemperature() public {
        vm.prank(sender);
        uint256 sId = logistics.createShipment(recipient, "Insulina", "A", "B", true);
        
        vm.prank(carrier);
        logistics.recordCheckpoint(sId, "Hub Central", "Hub", "Enfriamiento OK", 45); // 4.5°C

        LogisticsTracking.Checkpoint[] memory cps = logistics.getShipmentCheckpoints(sId);
        assertEq(cps.length, 1);
        assertEq(cps[0].temperature, 45);
    }

    function testFailOnlySenderCanCreate() public {
        vm.prank(carrier); // Un transportista intenta crear un envío
        logistics.createShipment(recipient, "Error", "A", "B", false);
    }
}