# @version 0.3.10
"""
@title Ethereum Proxy
@license MIT
@author Curve Finance
"""

event Execute:
    fingerprint: indexed(bytes32)

event SetExecutor:
    executor: indexed(address)

event TransferOwnership:
    owner: indexed(address)


executor: public(address)

owner: public(address)
future_owner: public(address)


@external
def __init__(_executor: address, _owner: address):
    self.executor = _executor
    log SetExecutor(_executor)

    self.owner = _owner
    log TransferOwnership(_owner)


@external
def execute(_target: address, _data: Bytes[4096], _value: uint256 = 0):
    """
    @notice Execute a call on another chain via an emitted log
    @param _target The target address to interact with
    @param _data The calldata to provide for the interaction
    @param _value The value to provide in the interaction (must be available on the chain)
    """
    assert msg.sender == self.executor  # dev: not executor

    log Execute(keccak256(_abi_encode(_target, keccak256(_data), _value)))


@external
def set_executor(_executor: address):
    """
    @notice Set the executor account which can call `execute`
    @param _executor The account to set as the executor
    """
    assert msg.sender == self.owner

    self.executor = _executor
    log SetExecutor(_executor)


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
