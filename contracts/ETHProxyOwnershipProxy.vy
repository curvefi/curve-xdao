# @version 0.3.10
"""
@title Curve ETH Proxy Ownerhip Proxy
@license MIT
@author Curve Finance
"""

interface Proxy:
    def set_executor(_executor: address): nonpayable
    def commit_transfer_ownership(_owner: address): nonpayable
    def accept_transfer_ownership(): nonpayable


event TransferOwnership:
    admin: indexed(address)


admin: public(address)
future_admin: public(address)


@external
def __init__(_admin: address):
    self.admin = _admin
    log TransferOwnership(_admin)


@external
@nonreentrant('lock')
def set_executor(_proxy: address, _executor: address):
    assert msg.sender == self.admin, "Access denied"

    Proxy(_proxy).set_executor(_executor)


@external
@nonreentrant('lock')
def commit_transfer_ownership(_proxy: address, new_owner: address):
    assert msg.sender == self.admin, "Access denied"

    Proxy(_proxy).commit_transfer_ownership(new_owner)


@external
@nonreentrant('lock')
def accept_transfer_ownership(_proxy: address):
    Proxy(_proxy).accept_transfer_ownership()


@external
def commit_admin(_future_admin: address):
    assert msg.sender == self.admin

    self.future_admin = _future_admin


@external
def accept_admin():
    assert msg.sender == self.future_admin

    self.admin = msg.sender
    log TransferOwnership(msg.sender)
