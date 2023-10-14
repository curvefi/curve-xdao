# @version 0.3.10
"""
@title Minter
@license MIT
@author Curve Finance
"""

interface Gauge:
    def user_checkpoint(_user: address) -> bool: nonpayable
    def integrate_fraction(_user: address) -> uint256: view

interface MERC20:
    def mint(_to: address, _value: uint256) -> bool: nonpayable

interface GaugeTypeOracle:
    def get_gauge_type(_gauge: address) -> uint256: view


event Minted:
    recipient: indexed(address)
    gauge: indexed(address)
    amount: uint256


ORACLE: public(immutable(address))
TOKEN: public(immutable(address))
TYPE: public(immutable(uint256))


# user -> gauge -> value
minted: public(HashMap[address, HashMap[address, uint256]])


@external
def __init__(_oracle: address, _token: address, _type: uint256):
    ORACLE = _oracle
    TOKEN = _token
    TYPE = _type


@internal
def _mint_for(_gauge: address, _for: address):
    assert GaugeTypeOracle(ORACLE).get_gauge_type(_gauge) == TYPE  # dev: gauge is not permitted

    Gauge(_gauge).user_checkpoint(_for)
    total_mint: uint256 = Gauge(_gauge).integrate_fraction(_for)
    to_mint: uint256 = total_mint - self.minted[_for][_gauge]

    if to_mint != 0:
        MERC20(TOKEN).mint(_for, to_mint)
        self.minted[_for][_gauge] = total_mint

        log Minted(_for, _gauge, total_mint)


@external
@nonreentrant('lock')
def mint(_gauge: address, _for: address = msg.sender):
    """
    @notice Mint everything which belongs to `_for` and send to them
    @param _gauge `Gauge` address to get mintable amount from
    """
    self._mint_for(_gauge, _for)


@external
@nonreentrant('lock')
def mint_many(_gauges: DynArray[address, 32], _for: address = msg.sender):
    """
    @notice Mint everything which belongs to `_for` across multiple gauges
    @param _gauges List of `Gauge` addresses
    """
    for gauge in _gauges:
        self._mint_for(gauge, _for)
