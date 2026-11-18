import importlib.util
import sys
import unittest

spec = importlib.util.spec_from_file_location("librepods_watch", sys.argv[1])
watcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watcher)


class AirPodsConnectionTests(unittest.TestCase):
    def device(self, **changes):
        result = {"Paired": True, "Connected": True, "UUIDs": [watcher.AIRPODS_UUID]}
        result.update(changes)
        return result

    def test_pairing_does_not_start_discovery(self):
        self.assertFalse(watcher.connected_airpods([self.device(Connected=False)]))

    def test_unpaired_advertisement_does_not_start_app(self):
        self.assertFalse(watcher.connected_airpods([self.device(Paired=False)]))

    def test_other_connected_headset_does_not_start_app(self):
        self.assertFalse(watcher.connected_airpods([self.device(UUIDs=["audio-sink"])]))

    def test_device_name_does_not_control_matching(self):
        self.assertTrue(watcher.connected_airpods([self.device(Name="Renamed earbuds")]))
        self.assertFalse(watcher.connected_airpods([
            self.device(Name="AirPods", UUIDs=[]),
        ]))

    def test_services_can_arrive_after_connection(self):
        self.assertFalse(watcher.connected_airpods([self.device(UUIDs=[])]))
        self.assertTrue(watcher.connected_airpods([self.device()]))

    def test_keep_app_until_last_airpods_disconnects(self):
        first = self.device()
        second = self.device()
        self.assertTrue(watcher.connected_airpods([first, second]))
        first["Connected"] = False
        self.assertTrue(watcher.connected_airpods([first, second]))
        second["Connected"] = False
        self.assertFalse(watcher.connected_airpods([first, second]))

    def test_missing_devices_or_properties_stop_app(self):
        for devices in ([], [{}], [{"Paired": True, "Connected": True}]):
            with self.subTest(devices=devices):
                self.assertFalse(watcher.connected_airpods(devices))


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
