
from contcfg import TCCmdWrapper
from contcfg.cmd_wrapper import DockerCmdWrapper

if __name__ == "__main__":
    tc = TCCmdWrapper(run_with_sudo=True)
    # tc.set_bandwidth("constellation-test-worker-2", "constellation-test-worker-3", 1000, "mbit")
    cmder = DockerCmdWrapper(run_with_sudo=True)
    cmder.check_container("constellation-test-worker-2")
    print(cmder.get_container("constellation-test-worker"))
    