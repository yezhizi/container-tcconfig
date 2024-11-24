# -*- coding: utf-8 -*-

from pathlib import Path


def get_script(script_name: str) -> Path:
    scripts_path = Path(__file__).resolve().parent.parent / "utils" / "scripts"
    assert scripts_path.exists(), f"Scripts path {scripts_path} not found"
    return scripts_path / script_name


def check_scripts():
    script_names = [
        "clear_tc_rules.sh",
        "docker_tcconfig.sh",
        "find_container_ip.sh",
        "find_container_veth_name.sh",
        "set_network_limit.sh",
    ]
    for script_name in script_names:
        assert get_script(script_name).exists(), f"Script {script_name} not found"
