# @version 0.3.10
"""
@title CCIP Block Hash Receiver
@license MIT
@author Curve Finance
"""

struct EVMTokenAmount:
    token: address
    amount: uint256

struct Any2EVMMessage:
    message_id: bytes32
    source_chain_selector: uint64
    sender: Bytes[32]
    data: Bytes[64]
    token_amounts: EVMTokenAmount


ROOT_SENDER: public(immutable(address))
ROOT_CHAIN_SELECTOR: public(immutable(uint64))
ORACLE: public(immutable(address))
CCIP_ROUTER: public(immutable(address))


@external
def __init__(_root_sender: address, _root_chain_selector: uint64, _oracle: address, _ccip_router: address):
    ROOT_SENDER = _root_sender
    ROOT_CHAIN_SELECTOR = _root_chain_selector
    ORACLE = _oracle
    CCIP_ROUTER = _ccip_router


@external
def ccipReceive(_message: Any2EVMMessage):
    assert msg.sender == CCIP_ROUTER
    assert _message.source_chain_selector == ROOT_CHAIN_SELECTOR
    assert _abi_decode(_message.sender, address) == ROOT_SENDER

    _: bool = raw_call(
        ORACLE,
        concat(method_id("commit_block_hash(uint256,bytes32)"), _message.data),
        revert_on_failure=False
    )


@view
@external
def supportsInterface(_interface_id: bytes4) -> bool:
    if _interface_id == 0xffffffff:
        return False
    return True
