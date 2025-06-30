# pragma version 0.4.0
"""
@title FastBridgeL2
@notice A contract responsible for Fast Bridge on L2
@license MIT
@author curve.fi
@custom:version 0.0.1
@custom:security security@curve.fi
"""

version: public(constant(String[8])) = "0.0.1"


from ethereum.ercs import IERC20
from snekmate.auth import ownable

initializes: ownable
exports: (
    ownable.owner,
    ownable.transfer_ownership,
)

interface IBridger:
    def bridge(_token: IERC20, _to: address, _amount: uint256, _min_amount: uint256=0) -> uint256: nonpayable

interface IMessenger:
    def message(_to: address, _message: Bytes[96]): payable

event SetMinAmount:
    min_amount: uint256

event SetLimit:
    limit: uint256

event SetBridger:
    bridger: IBridger

event SetMessenger:
    messenger: IMessenger


CRVUSD: public(immutable(IERC20))
VAULT: public(immutable(address))

INTERVAL: constant(uint256) = 86400  # 1 day
min_amount: public(uint256)  # Minimum amount to initiate bridge. Might be costy to claim on Ethereum
limit: public(uint256)  # Maximum amount to bridge in an INTERVAL, so there's no queue to resolve to claim on Ethereum
bridged: public(HashMap[uint256, uint256])  # Amounts of bridge coins per INTERVAL

bridger: public(IBridger)
messenger: public(IMessenger)


@deploy
def __init__(_crvusd: IERC20, _vault: address, _bridger: IBridger, _messenger: IMessenger):
    CRVUSD = _crvusd
    VAULT = _vault

    self.bridger = _bridger
    self.messenger = _messenger
    log SetBridger(_bridger)
    log SetMessenger(_messenger)

    self.min_amount = 10**18
    self.limit = 10**18
    log SetMinAmount(10**18)
    log SetLimit(10**18)

    ownable.__init__()


@external
@payable
def bridge(_to: address, _amount: uint256, _min_amount: uint256=0) -> uint256:
    """
    @notice Bridge crvUSD
    @param _to The receiver on destination chain
    @param _amount The amount of crvUSD to deposit, 2^256-1 for the whole available balance
    @param _min_amount Minimum amount to bridge
    @return Bridged amount
    """
    amount: uint256 = _amount
    if amount == max_value(uint256):
        amount = min(staticcall CRVUSD.balanceOf(msg.sender), staticcall CRVUSD.allowance(msg.sender, self))

    # Apply daily limit
    available: uint256 = self.limit - self.bridged[block.timestamp // INTERVAL]
    amount = min(amount, available)
    assert amount >= _min_amount

    assert extcall CRVUSD.transferFrom(msg.sender, self, amount)
    self.bridged[block.timestamp // INTERVAL] += amount

    # Initiate bridge transaction
    extcall self.bridger.bridge(CRVUSD, VAULT, max_value(uint256), self.min_amount)
    # Message for VAULT to release amount while waiting
    extcall self.messenger.message(
        VAULT,
        abi_encode(_to, amount, method_id=method_id("mint(address,uint256)")),
        value=msg.value,
    )

    return amount


@external
def allowed_to_bridge(_ts: uint256=block.timestamp) -> (uint256, uint256):
    """
    @notice Get interval of allowed amounts to bridge
    @param _ts Timestamp at which to check (current by default)
    @return (minimum, maximum) amounts allowed to bridge
    """
    available: uint256 = self.limit - self.bridged[block.timestamp // INTERVAL]

    balance: uint256 = staticcall CRVUSD.balanceOf(self)  # Someone threw money by mistake
    min_amount: uint256 = self.min_amount
    min_amount -= min(min_amount, balance)

    if available < min_amount:  # Not enough for bridge initiation
        return (0, 0)
    return (min_amount, available)


@external
def set_min_amount(_min_amount: uint256):
    """
    @notice Set minimum amount allowed to bridge
    @param _min_amount Minimum amount
    """
    ownable._check_owner()

    self.min_amount = _min_amount
    log SetMinAmount(_min_amount)


@external
def set_limit(_limit: uint256):
    """
    @notice Set new limit
    @param _limit Limit on bridging per INTERVAL
    """
    ownable._check_owner()

    self.limit = _limit
    log SetLimit(_limit)


@external
def set_bridger(_bridger: IBridger):
    """
    @notice Set new bridger
    @param _bridger Contract initiating actual bridge transaction
    """
    ownable._check_owner()

    extcall CRVUSD.approve(self.bridger.address, 0)
    extcall CRVUSD.approve(_bridger.address, max_value(uint256))
    self.bridger = _bridger
    log SetBridger(_bridger)


@external
def set_messenger(_messenger: IMessenger):
    """
    @notice Set new messenger
    @param _messenger Contract passing bridge tx fast
    """
    ownable._check_owner()

    self.messenger = _messenger
    log SetMessenger(_messenger)
