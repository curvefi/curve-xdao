# @version 0.3.10
"""
@title Minter Proxy
@dev Middleware to allow multiple minters for a token.
"""

interface MERC20:
    def mint(_to: address, _value: uint256): nonpayable


event TransferOwnership:
    owner: address


TOKEN: public(immutable(address))


is_minter: public(HashMap[address, bool])

owner: public(address)
future_owner: public(address)


@external
def __init__(token: address):
    TOKEN = token

    self.owner = msg.sender


@external
def mint(_to: address, _value: uint256):
    assert self.is_minter[msg.sender]
    
    MERC20(TOKEN).mint(_to, _value)


@external
def set_minter(_minter: address, _is_approved: bool):
    assert msg.sender == self.owner

    self.is_minter[_minter] = _is_approved


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
