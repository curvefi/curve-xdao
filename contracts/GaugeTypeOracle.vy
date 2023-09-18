# @version 0.3.9
"""
@title Gauge Type Oracle
@license MIT
@author Curve Finance
"""

event SetGaugeType:
    gauge: indexed(address)
    type: uint256

event TransferOwnership:
    owner: indexed(address)


gauge_type: HashMap[address, uint256]  # a value of 0 signifies the account is not a valid gauge

owner: public(address)
future_owner: public(address)


@external
def __init__():
    self.owner = msg.sender
    log TransferOwnership(msg.sender)


@view
@external
def get_gauge_type(_gauge: address) -> uint256:
    """
    @notice Get the gauge type of an account
    @dev This method will revert if the gauge type has not been set yet
    """
    return self.gauge_type[_gauge] - 1


@external
def set_gauge_type(_gauge: address, _type: uint256):
    """
    @notice Set the gauge type of an account
    @dev This method will increment the value of `_type` by 1 prior to storing,
        since a value of 0 signifies an invalid gauge.
    """
    assert msg.sender == self.owner  # dev: only owner

    self.gauge_type[_gauge] = _type + 1
    log SetGaugeType(_gauge, _type)


@external
def commit_transfer_ownership(_future_owner: address):
    """
    @notice Transfer ownership to `_future_owner`
    @param _future_owner The account to commit as the future owner
    """
    assert msg.sender == self.owner  # dev: only owner

    self.future_owner = _future_owner


@external
def accept_transfer_ownership():
    """
    @notice Accept the transfer of ownership
    @dev Only the committed future owner can call this function
    """
    assert msg.sender == self.future_owner  # dev: only future owner

    self.owner = msg.sender
    log TransferOwnership(msg.sender)
