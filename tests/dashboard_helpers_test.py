import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class DashboardHelpersTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.env = dict(os.environ, PATH=str(self.directory) + os.pathsep + os.environ["PATH"])

    def stub(self, name, body):
        path = self.directory / name
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.check_output(["bash", SCRIPTS / name, *args], env=self.env, text=True)

    def test_weather_key_uses_stdin_for_both_requests(self):
        self.env["OWM_API_KEY"] = "synthetic-test-key"
        self.stub("curl", '''
[[ "$*" != *"$OWM_API_KEY"* && "$*" == *"appid@-"* ]] || exit 1
[[ $(cat) == "$OWM_API_KEY" ]] || exit 1
printf '{"endpoint":"%s"}' "${!#}"
''')
        weather = json.loads(self.run_script("fetch-weather.sh", "60", "22"))
        self.assertTrue(weather["cur"]["endpoint"].endswith("/weather"))
        self.assertTrue(weather["fc"]["endpoint"].endswith("/forecast"))

    def test_unavailable_gpu_fields_do_not_drop_other_readings(self):
        self.stub("nvidia-smi", '''
[[ $1 == --id=0 ]] || exit 1
printf '%s\n' '[N/A], 49, 25, 1024, NVIDIA GeForce Test "A"' '90, 60, 1000, 2048, Second GPU'
''')
        sample = json.loads(self.run_script("perf.sh"))
        self.assertEqual([sample[k] for k in ("gpu", "gtemp", "vramU", "vramT", "gname")],
                         [0, 49, 25, 1024, 'Test "A"'])
        self.assertGreater(sample["ramT"], 0)
        self.stub("nvidia-smi", "exit 1")
        sample = json.loads(self.run_script("perf.sh"))
        self.assertEqual((sample["gtemp"], sample["vramU"], sample["vramT"]), (0, -1, 0))

    def test_probe_uses_selected_interface(self):
        self.stub("ip", '''
case "$*" in
    *"dev eth1 "*) echo "3: eth1 inet 192.0.2.8/24" ;;
    *"dev wlan0 "*) echo "5: wlan0 inet 192.0.2.9/24" ;;
    *) echo "1: vpn inet 192.0.2.1/32" ;;
esac
''')
        self.stub("nmcli", '[[ "$*" == *"ifname wlan0 "* ]] && echo "yes:5200 MHz"')
        self.assertEqual(self.run_script("network-details.sh", "eth1", "wired").splitlines(),
                         ["192.0.2.8/24"])
        self.assertEqual(self.run_script("network-details.sh", "wlan0", "wifi").splitlines(),
                         ["192.0.2.9/24", "5200 MHz"])
