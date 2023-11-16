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

event TransferOwnership:
    owner: indexed(address)

event SetGasLimit:
    gas_limit: uint256


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
    extra_args: Bytes[68]

struct EVMExtraArgsV1:
    gas_limit: uint256
    strict: bool


CCIP_ROUTER: public(constant(address)) = 0xE561d5E02207fb5eB32cca20a699E0d8919a1476
EVM_EXTRA_ARGS_V1_TAG: constant(bytes4) = 0x97a657c9


DESTINATION_CHAIN_SELECTOR: public(immutable(uint64))


gas_limit: public(uint256)

owner: public(address)
future_owner: public(address)


@external
def __init__(_destination_chain_selector: uint64):
    self.gas_limit = 500_000
    log SetGasLimit(500_000)

    self.owner = msg.sender
    log TransferOwnership(msg.sender)

    DESTINATION_CHAIN_SELECTOR = _destination_chain_selector


@payable
@external
def transmit(_block_number: uint256):
    assert block.number - 256 <= _block_number and _block_number < block.number - 64  # dev: invalid block

    destination_chain_selector: uint64 = DESTINATION_CHAIN_SELECTOR
    message: EVM2AnyMessage = EVM2AnyMessage({
        receiver: _abi_encode(self),
        data: _abi_encode(_block_number, blockhash(_block_number)),
        token_amounts: empty(DynArray[EVMTokenAmount, 1]),
        fee_token: empty(address),
        extra_args: _abi_encode(EVMExtraArgsV1({gas_limit: self.gas_limit, strict: False}), method_id=EVM_EXTRA_ARGS_V1_TAG)
    })

    Router(CCIP_ROUTER).ccipSend(destination_chain_selector, message, value=msg.value)


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
            extra_args: _abi_encode(EVMExtraArgsV1({gas_limit: self.gas_limit, strict: False}), method_id=EVM_EXTRA_ARGS_V1_TAG)
        })
    )


@external
def set_gas_limit(_gas_limit: uint256):
    """
    @notice Set the gas limit to use for cross-chain transactions
    @param _gas_limit The gas limit for cross-chain transactions
    """
    assert msg.sender == self.owner  # dev: only owner

    self.gas_limit = _gas_limit
    log SetGasLimit(_gas_limit)


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
