# @version 0.3.10
"""
@title Layer Zero Block Hash Receiver
@license MIT
@author Curve Finance
"""


KECCAK_LZ_ADDRESS: immutable(bytes32)

LZ_ENDPOINT: public(immutable(address))
ORACLE: public(immutable(address))


@external
def __init__(_oracle: address, _lz_endpoint: address):
    lz_address: Bytes[40] = concat(
        slice(convert(self, bytes32), 12, 20), slice(convert(self, bytes32), 12, 20)
    )
    KECCAK_LZ_ADDRESS = keccak256(lz_address)

    LZ_ENDPOINT = _lz_endpoint
    ORACLE = _oracle


@external
def lzReceive(_lz_chain_id: uint16, _lz_address: Bytes[40], _nonce: uint64, _payload: Bytes[64]):
    """
    @dev LayerZero method which should not revert at all
    """
    assert msg.sender == LZ_ENDPOINT  # dev: invalid caller

    assert _lz_chain_id == 101  # dev: invalid source chain
    assert keccak256(_lz_address) == KECCAK_LZ_ADDRESS  # dev: invalid source address

    _: bool = raw_call(
        ORACLE,
        concat(method_id("commit_block_hash(uint256,bytes32)"), _payload),
        revert_on_failure=False
    )
