# pragma version 0.4.3
"""
@title crvUSD FlashLender
@notice ERC3156 contract for crvUSD flash loans
@author Curve.Fi
@license Copyright (c) Curve.Fi, 2020-2024 - all rights reserved
"""

version: public(constant(String[8])) = "1.0.0"  # Initial

interface ERC3156FlashBorrower:
    def onFlashLoan(initiator: address, token: address, amount: uint256, fee: uint256, data: Bytes[10**5]): nonpayable

interface IToken:
    def balanceOf(_user: address) -> uint256: view
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def burn(_value: uint256) -> bool: nonpayable
    def minter() -> IMinter: view

interface IMinter:
    def mint(_to: address, _value: uint256): nonpayable

event FlashLoan:
    caller: indexed(address)
    receiver: indexed(address)
    amount: uint256

event SetFee:
    token: indexed(IToken)
    fee: uint256

event SetMaxFlashLoan:
    token: indexed(IToken)
    max_flash_loan: uint256

event SetFeeReceiver:
    fee_receiver: address

event SetKilled:
    status: bool


CRVUSD: immutable(IToken)
MINTER: immutable(IMinter)
FEE_BASE: constant(uint256) = 100_00_0  # 0.1bps
fee: public(uint256)  # 10 == 0.01 %
fee_receiver: public(address)
max_flash_loan: uint256

is_killed: public(bool)


@deploy
def __init__(_crvUSD: IToken, _fee_receiver: address):
    CRVUSD = _crvUSD
    MINTER = staticcall _crvUSD.minter()

    self.fee = 0
    log SetFee(token=_crvUSD, fee=0)

    self.max_flash_loan = 100_000 * 10 ** 18
    log SetMaxFlashLoan(token=_crvUSD, max_flash_loan=self.max_flash_loan)

    self.fee_receiver = _fee_receiver
    log SetFeeReceiver(fee_receiver=_fee_receiver)

    log SetKilled(status=empty(bool))


@external
@view
def supportedTokens(_token: IToken) -> bool:
    return _token == CRVUSD


@view
def _calc_fee(amount: uint256) -> uint256:
    return amount * self.fee // FEE_BASE


# nonreentrant by default
@external
def flashLoan(_receiver: ERC3156FlashBorrower, _token: IToken, _amount: uint256, _data: Bytes[10**5]) -> bool:
    """
    @notice Loan `_amount` tokens to `_receiver`, and takes it back plus a `flashFee` after the callback
    @param _receiver The contract receiving the tokens, needs to implement the
    `onFlashLoan(initiator: address, token: address, amount: uint256, fee: uint256, data: Bytes[10**5])` interface.
    @param _token The loan currency.
    @param _amount The amount of tokens lent.
    @param _data A data parameter to be passed on to the `receiver` for any custom use.
    """
    assert _token == CRVUSD, "FlashLender: Unsupported currency"
    assert not self.is_killed, "Killed"

    extcall MINTER.mint(_receiver.address, _amount)
    extcall _receiver.onFlashLoan(msg.sender, CRVUSD.address, _amount, 0, _data)
    extcall CRVUSD.burn(_amount)

    fee: uint256 = self._calc_fee(_amount)
    if fee > 0:
        extcall CRVUSD.transfer(self.fee_receiver, fee)

    log FlashLoan(
        caller=msg.sender,
        receiver=_receiver.address,
        amount=_amount,
    )

    return True


@external
@view
def flashFee(_token: IToken, _amount: uint256) -> uint256:
    """
    @notice The fee to be charged for a given loan.
    @param _token The loan currency.
    @param _amount The amount of tokens lent.
    @return The amount of `_token` to be charged for the loan, on top of the returned principal.
    """
    assert _token == CRVUSD, "FlashLender: Unsupported currency"
    return self._calc_fee(_amount)


@external
@view
def maxFlashLoan(_token: IToken) -> uint256:
    """
    @notice The amount of currency available to be lent.
    @param _token The loan currency.
    @return The amount of `_token` that can be borrowed.
    """
    return self.max_flash_loan if _token == CRVUSD else 0


#@external
#def set_fee(_new_fee: uint256):
#    admin._check_owner()
#
#    assert _new_fee <= FEE_BASE, "Bad fee value"
#    self.fee = _new_fee
#    log SetFee(token=CRVUSD, fee=_new_fee)
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
#def set_max_flash_loan(_new_max_flash_loan: uint256):
#    admin._check_owner()
#
#    self.max_flash_loan = _new_max_flash_loan
#    log SetMaxFlashLoan(token=CRVUSD, max_flash_loan=_new_max_flash_loan)
#

#@external
#def set_killed(_status: bool):
#    admin._check_emergency()
#
#    self.is_killed = _status
#    log SetKilled(status=_status)
