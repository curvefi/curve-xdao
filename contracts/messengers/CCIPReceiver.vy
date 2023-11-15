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


ETH_CHAIN_SELECTOR: constant(uint64) = 5009297550715157269


ORACLE: public(immutable(address))
CCIP_ROUTER: public(immutable(address))


@external
def __init__(_oracle: address, _ccip_router: address):
    ORACLE = _oracle
    CCIP_ROUTER = _ccip_router


@external
def ccipReceive(_message: Any2EVMMessage):
    assert msg.sender == CCIP_ROUTER
    assert _message.source_chain_selector == ETH_CHAIN_SELECTOR
    assert _abi_decode(_message.sender, address) == self

    _: bool = raw_call(
        ORACLE,
        concat(method_id("commit_block_hash(uint256,bytes32)"), _message.data),
        revert_on_failure=False
    )
