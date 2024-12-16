TC_BANDWIDTH_UNITS = [
    "kbit",
    "mbit",
    "gbit",
    "tbit",
    "kbps",
    "mbps",
    "gbps",
    "tbps",
    # keep the shorter units at the end
    "bit",
    "bps",
]


def split_raw_str_rate(rate: str) -> tuple[int, str]:
    """Split raw string rate into rate and unit.
    Args:
        - rate (str) : raw string rate. e.g. "100mbit"

    Returns:
        - rate (int) : rate
        - unit (str) : rate unit
    """
    rate = rate.lower()
    for unit in TC_BANDWIDTH_UNITS:
        if rate.endswith(unit):
            return int(rate[: -len(unit)]), unit
    raise ValueError(
        f"Invalid rate {rate}. " + f"Valid units are {TC_BANDWIDTH_UNITS}"
    )
