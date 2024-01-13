# @version 0.3.10
"""
@title Layer Zero Bridge - Curve DAO Token
@license MIT
@author Curve Finance
"""

interface ERC20:
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
    def transfer(_to: address, _value: uint256): nonpayable
    def burn(_value: uint256) -> bool: nonpayable

interface LZEndpoint:
    def send(
        _dst_chain_id: uint16,
        _destination: Bytes[40],
        _payload: Bytes[64],
        _refund_address: address,
        _zro_payment_address: address,
        _adapter_params: Bytes[34]
    ): payable
    def estimateFees(
        _dst_chain_id: uint16,
        _user_application: address,
        _payload: Bytes[64],
        _pay_in_zro: bool,
        _adapter_params: Bytes[34]
    ) -> uint256: view

interface Minter:
    def mint(_gauge: address): nonpayable


event BridgeSent:
    receiver: indexed(address)
    amount: uint256

event BridgeReceived:
    receiver: indexed(address)
    amount: uint256

event Delayed:
    nonce: indexed(uint64)
    receiver: indexed(address)
    amount: uint256

event SetPeriod:
    period: uint256

event SetLimit:
    limit: uint256

event SetGasLimit:
    gas_limit: uint256

event SetKilled:
    killed: bool

event TransferOwnership:
    owner: address


TOKEN: public(immutable(address))
MINTER: public(immutable(address))
LZ_ENDPOINT: public(immutable(address))

TOKEN_MIRROR: immutable(address)  # token address on the other side of the bridge
LZ_CHAIN_ID: immutable(uint16)
LZ_ADDRESS: immutable(Bytes[40])
KECCAK_LZ_ADDRESS: immutable(bytes32)


integrate_fraction: public(HashMap[address, uint256])

cache: uint256  # [last timestamp uint64][last available uint192]
limit: public(uint256)
period: public(uint256)

delayed: public(HashMap[uint64, bytes32])

gas_limit: public(uint256)
is_killed: public(bool)

owner: public(address)
future_owner: public(address)


@external
def __init__(
    _period: uint256,
    _limit: uint256,
    _gas_limit: uint256,
    _token: address,
    _minter: address,
    _lz_endpoint: address,
    _token_mirror: address,
    _lz_chain_id: uint16
):
    assert _period != 0

    self.period = _period
    log SetPeriod(_period)

    self.limit = _limit
    log SetLimit(_limit)

    self.gas_limit = _gas_limit
    log SetGasLimit(_gas_limit)

    self.owner = msg.sender
    log TransferOwnership(msg.sender)

    TOKEN = _token
    MINTER = _minter
    LZ_ENDPOINT = _lz_endpoint

    TOKEN_MIRROR = _token_mirror
    LZ_CHAIN_ID = _lz_chain_id
    LZ_ADDRESS = concat(
        slice(convert(self, bytes32), 12, 20), slice(convert(self, bytes32), 12, 20)
    )
    KECCAK_LZ_ADDRESS = keccak256(LZ_ADDRESS)


@payable
@external
def bridge(_receiver: address, _amount: uint256, _refund: address = msg.sender):
    """
    @notice Bridge tokens.
    """
    assert not self.is_killed
    assert _receiver not in [empty(address), TOKEN_MIRROR] and _amount != 0

    assert ERC20(TOKEN).transferFrom(msg.sender, self, _amount)
    assert ERC20(TOKEN).burn(_amount)

    LZEndpoint(LZ_ENDPOINT).send(
        LZ_CHAIN_ID,
        LZ_ADDRESS,
        _abi_encode(_receiver, _amount),
        _refund,
        empty(address),
        concat(b"\x00\x01", convert(self.gas_limit, bytes32)),
        value=msg.value
    )

    log BridgeSent(_receiver, _amount)


@external
def lzReceive(_lz_chain_id: uint16, _lz_address: Bytes[40], _nonce: uint64, _payload: Bytes[64]):
    assert msg.sender == LZ_ENDPOINT

    assert _lz_chain_id == LZ_CHAIN_ID
    assert keccak256(_lz_address) == KECCAK_LZ_ADDRESS

    receiver: address = empty(address)
    amount: uint256 = empty(uint256)
    receiver, amount = _abi_decode(_payload, (address, uint256))

    if receiver in [empty(address), TOKEN] or amount == 0:
        # safeguard
        return

    limit: uint256 = self.limit

    if self.is_killed or amount > limit:
        self.delayed[_nonce] = keccak256(_abi_encode(block.timestamp, receiver, amount))
        log Delayed(_nonce, receiver, amount)
        return

    cache: uint256 = self.cache
    ts: uint256 = cache >> 192
    available: uint256 = cache & convert(max_value(uint192), uint256)

    period: uint256 = self.period

    if period <= (block.timestamp - ts):
        available = limit
    else:
        # regenerate amount which is available to mint at a rate of (limit / period)
        available = min(available + (limit * (block.timestamp - ts) / period), limit)

    if amount > available:
        remainder: uint256 = amount - available
        amount = available
        available = 0

        # delay the remainder
        self.delayed[_nonce] = keccak256(_abi_encode(block.timestamp, receiver, remainder))
        log Delayed(_nonce, receiver, remainder)
    else:
        available -= amount

    self.cache = (block.timestamp << 192) + available

    if amount != 0:
        self.integrate_fraction[self] += amount

        Minter(MINTER).mint(self)
        ERC20(TOKEN).transfer(receiver, amount)
        log BridgeReceived(receiver, amount)


@external
def retry(_nonce: uint64, _timestamp: uint256, _receiver: address, _amount: uint256):
    """
    @notice Retry a delayed bridge attempt.
    """
    assert msg.sender == self.owner or not self.is_killed
    assert self.delayed[_nonce] == keccak256(_abi_encode(_timestamp, _receiver, _amount))

    self.delayed[_nonce] = empty(bytes32)

    period: uint256 = self.period
    assert block.timestamp >= _timestamp + period

    cache: uint256 = self.cache
    ts: uint256 = cache >> 192
    available: uint256 = cache & convert(max_value(uint192), uint256)

    limit: uint256 = self.limit

    if period <= (block.timestamp - ts):
        available = limit
    else:
        available = min(available + (limit * (block.timestamp - ts) / period), limit)

    amount: uint256 = _amount
    if amount > available:
        remainder: uint256 = amount - available
        amount = available
        available = 0

        # delay the remainder with the waiting period removed
        self.delayed[_nonce] = keccak256(_abi_encode(_timestamp, _receiver, remainder))
        log Delayed(_nonce, _receiver, remainder)
    else:
        available -= amount

    self.cache = (block.timestamp << 192) + available

    if amount != 0:
        self.integrate_fraction[self] += amount

        Minter(MINTER).mint(self)
        ERC20(TOKEN).transfer(_receiver, amount)
        log BridgeReceived(_receiver, amount)


@view
@external
def quote() -> uint256:
    """
    @notice Quote the cost to bridge tokens.
    """
    return LZEndpoint(LZ_ENDPOINT).estimateFees(
        LZ_CHAIN_ID,
        self,
        _abi_encode(self, block.timestamp),
        False,
        concat(b"\x00\x01", convert(self.gas_limit, bytes32)),
    )


@external
def user_checkpoint(_user: address) -> bool:
    return True


@external
def set_period(_period: uint256):
    """
    @notice Set the bridge limit period.
    """
    assert msg.sender == self.owner
    assert _period != 0

    self.period = _period
    log SetPeriod(_period)


@external
def set_limit(_limit: uint256):
    """
    @notice Set the bridge limit.
    """
    assert msg.sender == self.owner

    self.limit = _limit
    log SetLimit(_limit)


@external
def set_gas_limit(_gas_limit: uint256):
    """
    @notice Set the gas limit for bridge execution.
    """
    assert msg.sender == self.owner

    self.gas_limit = _gas_limit
    log SetGasLimit(_gas_limit)


@external
def set_killed(_killed: bool):
    assert msg.sender == self.owner

    self.is_killed = _killed
    log SetKilled(_killed)


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
