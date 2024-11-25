from pathlib import Path
from typing import Optional
import subprocess


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
        assert get_script(
            script_name
        ).exists(), f"Script {script_name} not found"


def singleton(cls):
    """Singleton decorator for classes.
    Note: This decorator will call __init__ method
    every time the instance is created.
    """
    instances = {}

    def get_instance(*args, **kwargs):
        if cls not in instances:
            instances[cls] = cls(*args, **kwargs)
        instances[cls].__init__(*args, **kwargs)
        return instances[cls]

    return get_instance


def exec_cmd(
    cmd: str,
    run_with_sudo: Optional[bool] = None,
    bash: bool = True,
    stdout=False,
) -> subprocess.CompletedProcess:
    """Execute a command.

    Args:
        - cmd (str): command to execute
        - _run_with_sudo (bool, optional): run command with sudo.
        Defaults to None.
        - bash (bool, optional): run command with bash.
        Defaults to True.
    """

    if bash and not cmd.strip().startswith("bash"):
        cmd = f"bash {cmd}"
    if run_with_sudo:
        cmd = f"sudo {cmd}"
    if stdout:
        output = subprocess.PIPE
    else:
        output = subprocess.DEVNULL
    return subprocess.run(
        cmd,
        shell=True,
        check=True,
        stdout=output,
    )
