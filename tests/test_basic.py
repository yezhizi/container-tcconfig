
from contcfg import TCCmdWrapper

if __name__ == "__main__":
    tc = TCCmdWrapper(run_with_sudo=True)
    tc.set_bandwidth("constellation-test-worker-2", "constellation-test-worker-3", 1000, "mbit")