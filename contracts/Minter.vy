# @version 0.3.10
"""
@title Minter
@license MIT
@author Curve Finance
"""

interface ERC20:
    def mint(_to: address, _value: uint256) -> bool: nonpayable

interface Gauge:
    def user_checkpoint(_user: address) -> bool: nonpayable
    def integrate_fraction(_user: address) -> uint256: view

interface GaugeTypeOracle:
    def get_gauge_type(_gauge: address) -> uint256: view


event Minted:
    receiver: indexed(address)
    gauge: indexed(address)
    amount: uint256


N_GAUGES: constant(uint256) = 64


TOKEN: public(immutable(address))
GAUGE_TYPE_ORACLE: public(immutable(address))
NETWORK_TYPE_ID: public(immutable(uint256))


# user -> gauge -> value
minted: public(HashMap[address, HashMap[address, uint256]])


@external
def __init__(_token: address, _gauge_type_oracle: address, _network_type_id: uint256):
    TOKEN = _token
    GAUGE_TYPE_ORACLE = _gauge_type_oracle
    NETWORK_TYPE_ID = _network_type_id


@internal
def _mint(_gauge: address, _for: address):
    assert GaugeTypeOracle(GAUGE_TYPE_ORACLE).get_gauge_type(_gauge) == NETWORK_TYPE_ID  # dev: not permitted

    Gauge(_gauge).user_checkpoint(_for)
    total: uint256 = Gauge(_gauge).integrate_fraction(_for)
    dx: uint256 = total - self.minted[_for][_gauge]

    if dx != 0:
        self.minted[_for][_gauge] = total
        ERC20(TOKEN).mint(_for, dx)

        log Minted(_for, _gauge, total)


@external
@nonreentrant('lock')
def mint(_gauge: address, _for: address = msg.sender):
    """
    @notice Mint all tokens earned by `_for` in the gauge `_gauge`.
    """
    self._mint(_gauge, _for)


@external
@nonreentrant('lock')
def mint_many(_gauges: DynArray[address, N_GAUGES], _for: address = msg.sender):
    """
    @notice Mint all tokens earned by `_for` in the gauges `_gauges`.
    """
    for gauge in _gauges:
        self._mint(gauge, _for)
