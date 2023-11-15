# @version 0.3.10
"""
@title CCIP Block Hash Sender
@license MIT
@author Curve Finance
"""

# https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol
interface Router:
    def getFee(_destinationChainSelector: uint64, _message: EVM2AnyMessage) -> uint256: view
    def ccipSend(_destinationChainSelector: uint64, _message: EVM2AnyMessage) -> bytes32: payable


event Transmission:
    message_id: bytes32


# https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts/src/v0.8/ccip/libraries/Client.sol#L7-L10
struct EVMTokenAmount:
    token: address
    amount: uint256

# https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts/src/v0.8/ccip/libraries/Client.sol#L20-L27
struct EVM2AnyMessage:
    receiver: Bytes[32]
    data: Bytes[64]
    token_amounts: DynArray[EVMTokenAmount, 1]
    fee_token: address
    extra_args: Bytes[64]


CCIP_ROUTER: public(constant(address)) = 0xE561d5E02207fb5eB32cca20a699E0d8919a1476


DESTINATION_CHAIN_SELECTOR: public(immutable(uint64))


@external
def __init__(_destination_chain_selector: uint64):
    DESTINATION_CHAIN_SELECTOR = _destination_chain_selector


@payable
@external
def transmit(_block_number: uint256):
    assert block.number - 256 <= _block_number and _block_number < block.number - 64  # dev: invalid block

    destination_chain_selector = DESTINATION_CHAIN_SELECTOR
    message: EVM2AnyMessage = EVM2AnyMessage({
        receiver: _abi_encode(self),
        data: _abi_encode(_block_number, blockhash(_block_number)),
        token_amounts: empty(DynArray[EVMTokenAmount, 1]),
        fee_token: empty(address),
        extra_args: _abi_encode(convert(500_000, uint256), method_id=b"\x97\xa6\x57\xc9")
    })

    fee: uint256 = Router(CCIP_ROUTER).getFee(destination_chain_selector, message)
    Router(CCIP_ROUTER).ccipSend(destination_chain_selector, message, value=fee)

    if msg.value > fee:
        raw_call(msg.sender, b"", value=msg.value - fee)


@view
@external
def quote() -> uint256:
    return Router(CCIP_ROUTER).getFee(
        DESTINATION_CHAIN_SELECTOR,
        EVM2AnyMessage({
            receiver: _abi_encode(self),
            data: _abi_encode(block.number, max_value(uint256)),
            token_amounts: empty(DynArray[EVMTokenAmount, 1]),
            fee_token: empty(address),
            extra_args: _abi_encode(convert(500_000, uint256), method_id=b"\x97\xa6\x57\xc9")
        })
    )
