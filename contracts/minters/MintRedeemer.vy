# pragma version 0.4.3
# pragma nonreentrancy on
"""
@title MintRedeemer
@notice Mint and Redeem functionality for scrvUSD/crvUSD
@dev Actually this contract works as inverse of scrvUSD Vault.
    Though, to comply with Ethereum treated as ERC4626 Vault with crvUSD as an asset
@author Curve.Fi
@license Copyright (c) Curve.Fi, 2020-2024 - all rights reserved
"""

version: public(constant(String[8])) = "1.0.0"  # Initial

interface IToken:
    def balanceOf(_user: address) -> uint256: view
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
    def burnFrom(_from: address, _value: uint256) -> bool: nonpayable
    def minter() -> IMinter: view

interface IMinter:
    def mint(_to: address, _value: uint256): nonpayable

interface IOracle:
    def price_v0() -> uint256: view
    def price_v1() -> uint256: view
    def price_v2() -> uint256: view
    def price() -> uint256: view
    def pricePerShare() -> uint256: view
    def price_oracle() -> uint256: view

event Deposit:
    sender: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

event Withdraw:
    sender: indexed(address)
    receiver: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

event ClaimFees:
    fees: uint256

event SetLimit:
    limit: uint256

event SetOracle:
    oracle: indexed(IOracle)
    oracle_method: OracleMethod

event SetFee:
    fee: uint256

event SetFeeReceiver:
    fee_receiver: indexed(address)

event SetKilled:
    status: Killed

flag Direction:
    NO_FEE
    DEPOSIT
    REDEEM

flag Killed:
    DEPOSIT
    REDEEM
    CLAIM_FEES

flag OracleMethod:
    V0
    V1
    V2
    PRICE_PER_SHARE
    PRICE
    PRICE_ORACLE

CRVUSD: public(immutable(IToken))
SCRVUSD: public(immutable(IToken))
CRVUSD_MINTER: immutable(IMinter)

ONE: constant(uint256) = 10 ** 18
# This contact mints crvUSD for scrvUSD as collateral.
# In order to mitigate any loops with scrvUSD rate washing away need to set a limit on this minting.
limit: public(uint256)  # limit of crvUSD to mint for scrvUSD
minted: public(uint256)  # minted <= limit

oracle: public(IOracle)
oracle_method: public(OracleMethod)

FEE_BASE: constant(uint256) = 100_00_0  # 0.1 bps
# Fee is needed to cover lags of oracle.
fee: public(uint256)  # 10 == 0.01 %

fee_receiver: public(address)

is_killed: public(Killed)


@deploy
def __init__(_crvUSD: IToken, _scrvUSD: IToken, _oracle: IOracle, _oracle_method: OracleMethod, _fee_receiver: address):
    """
    @param _crvUSD crvUSD address on used chain (needs minter role)
    @param _scrvUSD scrvUSD address on used chain
    @param _oracle Oracle for scrvUSD/crvUSD rate
    @param _fee_receiver Receiver of generated fees
    """
    CRVUSD = _crvUSD
    SCRVUSD = _scrvUSD
    CRVUSD_MINTER = staticcall _crvUSD.minter()

    self.limit = 100_000 * 10 ** 18
    log SetLimit(limit=self.limit)

    self.oracle = _oracle
    self.oracle_method = _oracle_method
    self._check_oracle()
    log SetOracle(oracle=_oracle, oracle_method=_oracle_method)

    self.fee = FEE_BASE // 100_00  # 1bps
    log SetFee(fee=self.fee)

    assert _fee_receiver != empty(address)
    self.fee_receiver = _fee_receiver
    log SetFeeReceiver(fee_receiver=_fee_receiver)

    log SetKilled(status=empty(Killed))


@view
def _rate() -> uint256:
    if self.oracle_method == OracleMethod.V0:
        return staticcall self.oracle.price_v0()
    elif self.oracle_method == OracleMethod.V1:
        return staticcall self.oracle.price_v1()
    elif self.oracle_method == OracleMethod.V2:
        return staticcall self.oracle.price_v2()
    elif self.oracle_method == OracleMethod.PRICE_PER_SHARE:
        return staticcall self.oracle.pricePerShare()
    elif self.oracle_method == OracleMethod.PRICE:
        return staticcall self.oracle.price()
    elif self.oracle_method == OracleMethod.PRICE_ORACLE:
        return staticcall self.oracle.price_oracle()

    raise "Bad oracle method"

@view
def _calc_fee(amount: uint256) -> uint256:
    return amount * self.fee // FEE_BASE

@view
def _rate_high() -> uint256:
    rate: uint256 = self._rate()
    return rate + self._calc_fee(rate)

@view
def _rate_low() -> uint256:
    rate: uint256 = self._rate()
    return rate - self._calc_fee(rate)


@view
def _convert_to_assets(shares: uint256, direction: Direction) -> uint256:
    if shares == 0:
        return 0

    if direction == Direction.NO_FEE:
        return shares * ONE // self._rate()
    elif direction == Direction.DEPOSIT:
        return ((shares + 1) * ONE - 1) // self._rate_low()
    elif direction == Direction.REDEEM:
        return shares * ONE // self._rate_high()

    raise "Unreachable"

@view
def _convert_to_shares(assets: uint256, direction: Direction) -> uint256:
    if assets == 0:
        return 0

    if direction == Direction.NO_FEE:
        return assets * self._rate() // ONE
    elif direction == Direction.DEPOSIT:
        return assets * self._rate_low() // ONE
    elif direction == Direction.REDEEM:
        return ((assets + 1) * self._rate_high() - 1) // ONE

    raise "Unreachable"


def _redeem(
    sender: address,
    receiver: address,
    owner: address,  # Should be same as sender
    assets: uint256,
    shares: uint256,
):
    assert self.is_killed not in Killed.REDEEM, "Killed"
    assert sender == owner, "Different owner not supported"

    minted: uint256 = self.minted
    assert minted + assets <= self.limit, "exceed withdraw limit"
    extcall SCRVUSD.transferFrom(owner, self, shares)
    extcall CRVUSD_MINTER.mint(receiver, assets)
    self.minted = minted + assets

    log Withdraw(
        sender=sender,
        receiver=receiver,
        owner=owner,
        assets=assets,
        shares=shares,
    )


def _deposit(
    sender: address,
    receiver: address,
    assets: uint256,
    shares: uint256,
):
    assert self.is_killed not in Killed.DEPOSIT, "Killed"

    minted: uint256 = self.minted
    assert minted <= assets and shares <= staticcall SCRVUSD.balanceOf(self), "exceed deposit limit"
    extcall CRVUSD.burnFrom(sender, assets)
    extcall SCRVUSD.transfer(receiver, shares)
    self.minted = minted - assets

    log Deposit(
        sender=sender,
        owner=receiver,
        assets=assets,
        shares=shares,
    )


@view
@external
def pricePerShare() -> uint256:
    """
    @notice Get the price per share (pps) of the vault.
    @dev This value offers limited precision. Integrations that require
        exact precision should use convertToAssets or convertToShares instead.
    @return The price per share.
    """
    return self._rate()


@external
def deposit(_assets: uint256, _receiver: address) -> uint256:
    """
    @notice Deposit assets into the vault.
    @dev Pass max uint256 to deposit full asset balance.
    @param _assets The amount of assets to deposit.
    @param _receiver The address to receive the shares.
    @return The amount of shares minted.
    """
    amount: uint256 = _assets
    # Deposit all if sent with max uint
    if amount == max_value(uint256):
        amount = staticcall CRVUSD.balanceOf(msg.sender)

    shares: uint256 = self._convert_to_shares(amount, Direction.DEPOSIT)
    self._deposit(msg.sender, _receiver, amount, shares)
    return shares


@external
def mint(_shares: uint256, _receiver: address) -> uint256:
    """
    @notice Mint shares for the receiver.
    @param _shares The amount of shares to mint.
    @param _receiver The address to receive the shares.
    @return The amount of assets deposited.
    """
    assets: uint256 = self._convert_to_assets(_shares, Direction.DEPOSIT)
    self._deposit(msg.sender, _receiver, assets, _shares)
    return assets


@external
def withdraw(_assets: uint256, _receiver: address, _owner: address) -> uint256:
    """
    @notice Withdraw an amount of asset to `_receiver` burning `_owner`s shares.
    @param _assets The amount of asset to withdraw.
    @param _receiver The address to receive the assets.
    @param _owner The address who's shares are being burnt. Only sender is supported.
    @return The amount of shares actually burnt.
    """
    shares: uint256 = self._convert_to_shares(_assets, Direction.REDEEM)
    self._redeem(msg.sender, _receiver, _owner, _assets, shares)
    return shares

@external
def redeem(_shares: uint256, _receiver: address, _owner: address) -> uint256:
    """
    @notice Redeems an amount of shares of `_owner`s shares sending funds to `_receiver`.
    @dev Pass max uint256 to redeem full scrvUSD balance.
    @param _shares The amount of shares to burn.
    @param _receiver The address to receive the assets.
    @param _owner The address who's shares are being burnt. Only sender is supported.
    @return The amount of assets actually withdrawn.
    """
    amount: uint256 = _shares
    if _shares == max_value(uint256):
        amount = staticcall SCRVUSD.balanceOf(_owner)

    assets: uint256 = self._convert_to_assets(amount, Direction.REDEEM)
    self._redeem(msg.sender, _receiver, _owner, assets, amount)
    return assets


@view
@external
def convertToShares(assets: uint256) -> uint256:
    """
    @notice Convert an amount of assets to shares.
    @param assets The amount of assets to convert.
    @return The amount of shares.
    """
    return self._convert_to_shares(assets, Direction.NO_FEE)


@view
def _max_deposit(_receiver: address) -> uint256:
    """
    @dev Returns amount of assets available for the mint to `_receiver`
    """
    if _receiver in [empty(address), self]:
        return 0
    return min(
        ((staticcall SCRVUSD.balanceOf(self) + 1) * self._rate_high() - 1) // ONE,  # extra check, should be always greater
        self.minted,
    )


@view
@external
def previewDeposit(_assets: uint256) -> uint256:
    """
    @notice Preview the amount of shares that would be minted for a deposit.
    @param _assets The amount of assets to deposit.
    @return The amount of shares that would be minted.
    """
    return self._convert_to_shares(_assets, Direction.DEPOSIT)

@view
@external
def previewMint(_shares: uint256) -> uint256:
    """
    @notice Preview the amount of assets that would be deposited for a mint.
    @param _shares The amount of shares to mint.
    @return The amount of assets that would be deposited.
    """
    return self._convert_to_assets(_shares, Direction.DEPOSIT)

@view
@external
def maxDeposit(_receiver: address) -> uint256:
    """
    @notice Get the maximum amount of assets that can be deposited.
    @param _receiver The address that will receive the shares.
    @return The maximum amount of assets that can be deposited.
    """
    return self._max_deposit(_receiver)

@view
@external
def maxMint(_receiver: address) -> uint256:
    """
    @notice Get the maximum amount of shares that can be minted.
    @param _receiver The address that will receive the shares.
    @return The maximum amount of shares that can be minted.
    """
    max_deposit: uint256 = self._max_deposit(_receiver)
    return self._convert_to_shares(max_deposit, Direction.DEPOSIT)


@view
@external
def convertToAssets(_shares: uint256) -> uint256:
    """
    @notice Convert an amount of shares to assets.
    @param _shares The amount of shares to convert.
    @return The amount of assets.
    """
    return self._convert_to_assets(_shares, Direction.NO_FEE)

@view
def _max_redeem(_owner: address) -> uint256:
    """
    @dev Returns the max amount of `shares` an `owner` can redeem.
    """
    if _owner in [empty(address), self]:
        return 0
    available_to_mint: uint256 = self.limit
    minted: uint256 = self.minted
    if available_to_mint >= minted:
        return 0
    return min(
        ((available_to_mint - minted + 1) * ONE - 1) // self._rate_low(),  # opposite of convert_to_assets
        staticcall SCRVUSD.balanceOf(_owner),  # extra check, should be always greater
    )

@view
@external
def maxWithdraw(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of assets that can be withdrawn.
    @param _owner The address that owns the shares.
    @return The maximum amount of assets that can be withdrawn.
    """
    max_redeem: uint256 = self._max_redeem(_owner)
    return self._convert_to_assets(max_redeem, Direction.REDEEM)

@view
@external
def maxRedeem(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of shares that can be redeemed.
    @param _owner The address that owns the shares.
    @return The maximum amount of shares that can be redeemed.
    """
    return self._max_redeem(_owner)

@view
@external
def previewWithdraw(_assets: uint256) -> uint256:
    """
    @notice Preview the amount of shares that would be redeemed for a withdraw.
    @param _assets The amount of assets to withdraw.
    @return The amount of shares that would be redeemed.
    """
    return self._convert_to_shares(_assets, Direction.REDEEM)

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    """
    @notice Preview the amount of assets that would be withdrawn for a redeem.
    @param _shares The amount of shares to redeem.
    @return The amount of assets that would be withdrawn.
    """
    return self._convert_to_assets(_shares, Direction.REDEEM)


@external
def claim_fees() -> uint256:
    assert self.is_killed not in Killed.CLAIM_FEES, "Killed"

    accumulated_fees: uint256 = staticcall SCRVUSD.balanceOf(self) - self._convert_to_shares(self.minted, Direction.REDEEM)
    extcall SCRVUSD.transfer(self.fee_receiver, accumulated_fees)
    log ClaimFees(fees=accumulated_fees)
    return accumulated_fees


@view
def _check_oracle():
    price: uint256 = self._rate()
    assert ONE <= price and price <= ONE ** 2, "Bad oracle response"

#@external
#def set_oracle(_new_oracle: IOracle, _oracle_method: OracleMethod):
#    admin._check_owner()
#
#    self.oracle = _new_oracle
#    self._check_oracle()
#    log SetOracle(oracle=_new_oracle, oracle_method=_oracle_method)
#
#
#@external
#def set_limit(_new_limit: uint256):
#    admin._check_owner()
#
#    assert _new_limit <= FEE_BASE, "Bad limit value"
#    self.limit = _new_limit
#    log SetLimit(limit=_new_limit)
#
#
#@external
#def set_fee(_new_fee: uint256):
#    admin._check_owner()
#
#    assert _new_fee <= FEE_BASE, "Bad fee value"
#    self.fee = _new_fee
#    log SetFee(fee=_new_fee)
#
#
#@external
#def set_fee_receiver(_new_fee_receiver: address):
#    admin._check_owner()
#
#    assert _new_fee_receiver != empty(address), "Bad fee_receiver value"
#    self.fee_receiver = _new_fee_receiver
#    log SetFeeReceiver(fee_receiver=_new_fee_receiver)
#
#
#@external
#def set_killed(_status: Killed):
#    admin._check_emergency()
#
#    self.is_killed = _status
#    log SetKilled(status=_status)
