# @version 0.3.10
"""
@title Curve Token Minter Proxy
@license MIT
@author Curve Finance
"""

interface ERC20:
    def mint(_to: address, _value: uint256): nonpayable


event SetMinter:
    minter: indexed(address)
    status: bool

event TransferOwnership:
    owner: address


TOKEN: public(immutable(address))


is_minter: public(HashMap[address, bool])
owner: public(address)


@external
def __init__(_token: address):
    TOKEN = _token

    self.owner = msg.sender
    log TransferOwnership(msg.sender)


@external
def mint(_to: address, _value: uint256):
    assert self.is_minter[msg.sender]

    ERC20(TOKEN).mint(_to, _value)


@external
def set_minter(_minter: address, _status: bool):
    assert msg.sender == self.owner

    self.is_minter[_minter] = _status
    log SetMinter(_minter, _status)


@external
def transferOwnership(_owner: address):
    assert msg.sender == self.owner

    self.owner = _owner
    log TransferOwnership(_owner)
