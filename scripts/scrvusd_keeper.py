import time
from time import sleep

from web3 import Web3
from web3.eth import AsyncEth
import json
import os

from getpass import getpass
from eth_account import account, Account

from submit_scrvusd_price import generate_proof

ETH_NETWORK = f"https://eth-mainnet.alchemyapi.io/v2/{os.environ['WEB3_ETHEREUM_MAINNET_ALCHEMY_API_KEY']}"
L2_NETWORK = f"https://opt-mainnet.g.alchemy.com/v2/{os.environ['WEB3_OPTIMISM_MAINNET_ALCHEMY_API_KEY']}"

SCRVUSD = "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367"

DEPLOYMENTS = {
    "optimism": ("0x988d1037e9608B21050A8EFba0c6C45e01A3Bce7", "0xC772063cE3e622B458B706Dd2e36309418A1aE42", "0x47ca04Ee05f167583122833abfb0f14aC5677Ee4"),
    "base": ("0x3c0a405E914337139992625D5100Ea141a9C4d11", "0x3d8EADb739D1Ef95dd53D718e4810721837c69c1", "0x6a2691068C7CbdA03292Ba0f9c77A25F658bAeF5"),
    "fraxtal": ("0xbD2775B8eADaE81501898eB208715f0040E51882", "0x09F8D940EAD55853c51045bcbfE67341B686C071", "0x0094Ad026643994c8fB2136ec912D508B15fe0E5"),
    "mantle": ("0x004A476B5B76738E34c86C7144554B9d34402F13", "0xbD2775B8eADaE81501898eB208715f0040E51882", "0x09F8D940EAD55853c51045bcbfE67341B686C071"),
}

B_ORACLE, S_ORACLE, PROVER = DEPLOYMENTS["optimism"]

last_update = 0
REL_CHANGE_THRESHOLD = 1.00005  # 0.5 bps, should be >1

APPLY_BLOCK_HASH = Web3.keccak(text="ApplyBlockHash(uint256,bytes32)").hex()
COMMIT_BLOCK_HASH = Web3.keccak(text="CommitBlockHash(address,uint256,bytes32)").hex()


eth_web3 = Web3(
    provider=Web3.HTTPProvider(
        ETH_NETWORK,
        # {"verify_ssl": False},
    ),
    # modules={"eth": (AsyncEth,)},
)

l2_web3 = Web3(
    provider=Web3.HTTPProvider(
        L2_NETWORK,
        # {"verify_ssl": False},
    ),
    # modules={"eth": (AsyncEth,)},
)


def account_load_pkey(fname):
    path = os.path.expanduser(os.path.join('~', '.brownie', 'accounts', fname + '.json'))
    with open(path, 'r') as f:
        pkey = account.decode_keyfile_json(json.load(f), getpass())
        return pkey
wallet = Account.from_key(account_load_pkey("keeper"))


def prove(boracle, prover, block_number=None):
    if not block_number:
        # Apply latest available blockhash
        tx = boracle.functions.apply().build_transaction(
            {
                "from": wallet.address,
                "nonce": l2_web3.eth.get_transaction_count(wallet.address),
            }
        )
        signed_tx = l2_web3.eth.account.sign_transaction(tx, private_key=wallet.key)
        tx_hash = l2_web3.eth.send_raw_transaction(signed_tx.raw_transaction)
        l2_web3.eth.wait_for_transaction_receipt(tx_hash)
        tx_receipt = l2_web3.eth.get_transaction_receipt(tx_hash)
        block_number = -1
        for log in tx_receipt["logs"]:
            if log["address"] == boracle.address:
                if log["topics"][0].hex() == APPLY_BLOCK_HASH:
                    block_number = int(log["topics"][1].hex(), 16)
                    break
                if log["topics"][0].hex() == COMMIT_BLOCK_HASH:
                    block_number = int(log["topics"][2].hex(), 16)
                    break
        assert block_number > 0, "Applied block number not retrieved"
        print(f"Applied block: {block_number}")
        time.sleep(1)

    # Generate and submit proof for applied blockhash
    proofs = generate_proof(eth_web3, block_number)
    tx = prover.functions.prove(bytes.fromhex(proofs[0]), bytes.fromhex(proofs[1])).build_transaction(
        {
            "from": wallet.address,
            "nonce": l2_web3.eth.get_transaction_count(wallet.address),
        }
    )
    signed_tx = l2_web3.eth.account.sign_transaction(tx, private_key=wallet.key)
    l2_web3.eth.send_raw_transaction(signed_tx.raw_transaction)
    l2_web3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Submitted proof")


def time_to_update(scrvusd, soracle):
    # can be any relative change or time
    if time.time() - last_update >= 4 * 3600:  # Every 4 hours
        return True
    price = scrvusd.functions.pricePerShare().call()
    oracle_price = soracle.functions.price().call()[1]  # take price.future = latest set
    return price / oracle_price > REL_CHANGE_THRESHOLD


def loop():
    scrvusd = eth_web3.eth.contract(SCRVUSD, abi=[{'name': 'Deposit', 'inputs': [{'name': 'sender', 'type': 'address', 'indexed': True}, {'name': 'owner', 'type': 'address', 'indexed': True}, {'name': 'assets', 'type': 'uint256', 'indexed': False}, {'name': 'shares', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'Withdraw', 'inputs': [{'name': 'sender', 'type': 'address', 'indexed': True}, {'name': 'receiver', 'type': 'address', 'indexed': True}, {'name': 'owner', 'type': 'address', 'indexed': True}, {'name': 'assets', 'type': 'uint256', 'indexed': False}, {'name': 'shares', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'Transfer', 'inputs': [{'name': 'sender', 'type': 'address', 'indexed': True}, {'name': 'receiver', 'type': 'address', 'indexed': True}, {'name': 'value', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'Approval', 'inputs': [{'name': 'owner', 'type': 'address', 'indexed': True}, {'name': 'spender', 'type': 'address', 'indexed': True}, {'name': 'value', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'StrategyChanged', 'inputs': [{'name': 'strategy', 'type': 'address', 'indexed': True}, {'name': 'change_type', 'type': 'uint256', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'StrategyReported', 'inputs': [{'name': 'strategy', 'type': 'address', 'indexed': True}, {'name': 'gain', 'type': 'uint256', 'indexed': False}, {'name': 'loss', 'type': 'uint256', 'indexed': False}, {'name': 'current_debt', 'type': 'uint256', 'indexed': False}, {'name': 'protocol_fees', 'type': 'uint256', 'indexed': False}, {'name': 'total_fees', 'type': 'uint256', 'indexed': False}, {'name': 'total_refunds', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'DebtUpdated', 'inputs': [{'name': 'strategy', 'type': 'address', 'indexed': True}, {'name': 'current_debt', 'type': 'uint256', 'indexed': False}, {'name': 'new_debt', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'RoleSet', 'inputs': [{'name': 'account', 'type': 'address', 'indexed': True}, {'name': 'role', 'type': 'uint256', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateFutureRoleManager', 'inputs': [{'name': 'future_role_manager', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateRoleManager', 'inputs': [{'name': 'role_manager', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateAccountant', 'inputs': [{'name': 'accountant', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateDepositLimitModule', 'inputs': [{'name': 'deposit_limit_module', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateWithdrawLimitModule', 'inputs': [{'name': 'withdraw_limit_module', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateDefaultQueue', 'inputs': [{'name': 'new_default_queue', 'type': 'address[]', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateUseDefaultQueue', 'inputs': [{'name': 'use_default_queue', 'type': 'bool', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateAutoAllocate', 'inputs': [{'name': 'auto_allocate', 'type': 'bool', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdatedMaxDebtForStrategy', 'inputs': [{'name': 'sender', 'type': 'address', 'indexed': True}, {'name': 'strategy', 'type': 'address', 'indexed': True}, {'name': 'new_debt', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateDepositLimit', 'inputs': [{'name': 'deposit_limit', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateMinimumTotalIdle', 'inputs': [{'name': 'minimum_total_idle', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'UpdateProfitMaxUnlockTime', 'inputs': [{'name': 'profit_max_unlock_time', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'DebtPurchased', 'inputs': [{'name': 'strategy', 'type': 'address', 'indexed': True}, {'name': 'amount', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'Shutdown', 'inputs': [], 'anonymous': False, 'type': 'event'}, {'stateMutability': 'nonpayable', 'type': 'constructor', 'inputs': [], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'initialize', 'inputs': [{'name': 'asset', 'type': 'address'}, {'name': 'name', 'type': 'string'}, {'name': 'symbol', 'type': 'string'}, {'name': 'role_manager', 'type': 'address'}, {'name': 'profit_max_unlock_time', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'setName', 'inputs': [{'name': 'name', 'type': 'string'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'setSymbol', 'inputs': [{'name': 'symbol', 'type': 'string'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_accountant', 'inputs': [{'name': 'new_accountant', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_default_queue', 'inputs': [{'name': 'new_default_queue', 'type': 'address[]'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_use_default_queue', 'inputs': [{'name': 'use_default_queue', 'type': 'bool'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_auto_allocate', 'inputs': [{'name': 'auto_allocate', 'type': 'bool'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_deposit_limit', 'inputs': [{'name': 'deposit_limit', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_deposit_limit', 'inputs': [{'name': 'deposit_limit', 'type': 'uint256'}, {'name': 'override', 'type': 'bool'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_deposit_limit_module', 'inputs': [{'name': 'deposit_limit_module', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_deposit_limit_module', 'inputs': [{'name': 'deposit_limit_module', 'type': 'address'}, {'name': 'override', 'type': 'bool'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_withdraw_limit_module', 'inputs': [{'name': 'withdraw_limit_module', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_minimum_total_idle', 'inputs': [{'name': 'minimum_total_idle', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'setProfitMaxUnlockTime', 'inputs': [{'name': 'new_profit_max_unlock_time', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_role', 'inputs': [{'name': 'account', 'type': 'address'}, {'name': 'role', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'add_role', 'inputs': [{'name': 'account', 'type': 'address'}, {'name': 'role', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'remove_role', 'inputs': [{'name': 'account', 'type': 'address'}, {'name': 'role', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'transfer_role_manager', 'inputs': [{'name': 'role_manager', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'accept_role_manager', 'inputs': [], 'outputs': []}, {'stateMutability': 'view', 'type': 'function', 'name': 'isShutdown', 'inputs': [], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'unlockedShares', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'pricePerShare', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'get_default_queue', 'inputs': [], 'outputs': [{'name': '', 'type': 'address[]'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'process_report', 'inputs': [{'name': 'strategy', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}, {'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'buy_debt', 'inputs': [{'name': 'strategy', 'type': 'address'}, {'name': 'amount', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'add_strategy', 'inputs': [{'name': 'new_strategy', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'add_strategy', 'inputs': [{'name': 'new_strategy', 'type': 'address'}, {'name': 'add_to_queue', 'type': 'bool'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'revoke_strategy', 'inputs': [{'name': 'strategy', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'force_revoke_strategy', 'inputs': [{'name': 'strategy', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'update_max_debt_for_strategy', 'inputs': [{'name': 'strategy', 'type': 'address'}, {'name': 'new_max_debt', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'update_debt', 'inputs': [{'name': 'strategy', 'type': 'address'}, {'name': 'target_debt', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'update_debt', 'inputs': [{'name': 'strategy', 'type': 'address'}, {'name': 'target_debt', 'type': 'uint256'}, {'name': 'max_loss', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'shutdown_vault', 'inputs': [], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'deposit', 'inputs': [{'name': 'assets', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'mint', 'inputs': [{'name': 'shares', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'withdraw', 'inputs': [{'name': 'assets', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}, {'name': 'owner', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'withdraw', 'inputs': [{'name': 'assets', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}, {'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'withdraw', 'inputs': [{'name': 'assets', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}, {'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}, {'name': 'strategies', 'type': 'address[]'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'redeem', 'inputs': [{'name': 'shares', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}, {'name': 'owner', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'redeem', 'inputs': [{'name': 'shares', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}, {'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'redeem', 'inputs': [{'name': 'shares', 'type': 'uint256'}, {'name': 'receiver', 'type': 'address'}, {'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}, {'name': 'strategies', 'type': 'address[]'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'approve', 'inputs': [{'name': 'spender', 'type': 'address'}, {'name': 'amount', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'transfer', 'inputs': [{'name': 'receiver', 'type': 'address'}, {'name': 'amount', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'transferFrom', 'inputs': [{'name': 'sender', 'type': 'address'}, {'name': 'receiver', 'type': 'address'}, {'name': 'amount', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'permit', 'inputs': [{'name': 'owner', 'type': 'address'}, {'name': 'spender', 'type': 'address'}, {'name': 'amount', 'type': 'uint256'}, {'name': 'deadline', 'type': 'uint256'}, {'name': 'v', 'type': 'uint8'}, {'name': 'r', 'type': 'bytes32'}, {'name': 's', 'type': 'bytes32'}], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'balanceOf', 'inputs': [{'name': 'addr', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'totalSupply', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'totalAssets', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'totalIdle', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'totalDebt', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'convertToShares', 'inputs': [{'name': 'assets', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'previewDeposit', 'inputs': [{'name': 'assets', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'previewMint', 'inputs': [{'name': 'shares', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'convertToAssets', 'inputs': [{'name': 'shares', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxDeposit', 'inputs': [{'name': 'receiver', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxMint', 'inputs': [{'name': 'receiver', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxWithdraw', 'inputs': [{'name': 'owner', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxWithdraw', 'inputs': [{'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxWithdraw', 'inputs': [{'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}, {'name': 'strategies', 'type': 'address[]'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxRedeem', 'inputs': [{'name': 'owner', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxRedeem', 'inputs': [{'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'maxRedeem', 'inputs': [{'name': 'owner', 'type': 'address'}, {'name': 'max_loss', 'type': 'uint256'}, {'name': 'strategies', 'type': 'address[]'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'previewWithdraw', 'inputs': [{'name': 'assets', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'previewRedeem', 'inputs': [{'name': 'shares', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'FACTORY', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'pure', 'type': 'function', 'name': 'apiVersion', 'inputs': [], 'outputs': [{'name': '', 'type': 'string'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'assess_share_of_unrealised_losses', 'inputs': [{'name': 'strategy', 'type': 'address'}, {'name': 'assets_needed', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'profitMaxUnlockTime', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'fullProfitUnlockDate', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'profitUnlockingRate', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'lastProfitUpdate', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'DOMAIN_SEPARATOR', 'inputs': [], 'outputs': [{'name': '', 'type': 'bytes32'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'asset', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'decimals', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint8'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'strategies', 'inputs': [{'name': 'arg0', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'tuple', 'components': [{'name': 'activation', 'type': 'uint256'}, {'name': 'last_report', 'type': 'uint256'}, {'name': 'current_debt', 'type': 'uint256'}, {'name': 'max_debt', 'type': 'uint256'}]}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'default_queue', 'inputs': [{'name': 'arg0', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'use_default_queue', 'inputs': [], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'auto_allocate', 'inputs': [], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'allowance', 'inputs': [{'name': 'arg0', 'type': 'address'}, {'name': 'arg1', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'minimum_total_idle', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'deposit_limit', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'accountant', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'deposit_limit_module', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'withdraw_limit_module', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'roles', 'inputs': [{'name': 'arg0', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'role_manager', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'future_role_manager', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'name', 'inputs': [], 'outputs': [{'name': '', 'type': 'string'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'symbol', 'inputs': [], 'outputs': [{'name': '', 'type': 'string'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'nonces', 'inputs': [{'name': 'arg0', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'uint256'}]}])
    boracle = l2_web3.eth.contract(B_ORACLE, abi=[{'name': 'CommitBlockHash', 'inputs': [{'name': 'committer', 'type': 'address', 'indexed': True}, {'name': 'number', 'type': 'uint256', 'indexed': True}, {'name': 'hash', 'type': 'bytes32', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'ApplyBlockHash', 'inputs': [{'name': 'number', 'type': 'uint256', 'indexed': True}, {'name': 'hash', 'type': 'bytes32', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'stateMutability': 'view', 'type': 'function', 'name': 'get_block_hash', 'inputs': [{'name': '_number', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'commit', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'apply', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'block_hash', 'inputs': [{'name': 'arg0', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'commitments', 'inputs': [{'name': 'arg0', 'type': 'address'}, {'name': 'arg1', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}])
    soracle = l2_web3.eth.contract(S_ORACLE, abi=[{'anonymous': False, 'inputs': [{'indexed': False, 'name': 'new_price', 'type': 'uint256'}, {'indexed': False, 'name': 'at', 'type': 'uint256'}], 'name': 'PriceUpdate', 'type': 'event'}, {'anonymous': False, 'inputs': [{'indexed': False, 'name': 'prover', 'type': 'address'}], 'name': 'SetProver', 'type': 'event'}, {'anonymous': False, 'inputs': [{'indexed': True, 'name': 'previous_owner', 'type': 'address'}, {'indexed': True, 'name': 'new_owner', 'type': 'address'}], 'name': 'OwnershipTransferred', 'type': 'event'}, {'inputs': [{'name': 'new_owner', 'type': 'address'}], 'name': 'transfer_ownership', 'outputs': [], 'stateMutability': 'nonpayable', 'type': 'function'}, {'inputs': [], 'name': 'renounce_ownership', 'outputs': [], 'stateMutability': 'nonpayable', 'type': 'function'}, {'inputs': [], 'name': 'owner', 'outputs': [{'name': '', 'type': 'address'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'pricePerShare', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [{'name': 'ts', 'type': 'uint256'}], 'name': 'pricePerShare', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'pricePerAsset', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [{'name': 'ts', 'type': 'uint256'}], 'name': 'pricePerAsset', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'price_oracle', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [{'name': 'i', 'type': 'uint256'}], 'name': 'price_oracle', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [{'name': '_parameters', 'type': 'uint256[8]'}], 'name': 'update_price', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'nonpayable', 'type': 'function'}, {'inputs': [{'name': '_max_acceleration', 'type': 'uint256'}], 'name': 'set_max_acceleration', 'outputs': [], 'stateMutability': 'nonpayable', 'type': 'function'}, {'inputs': [{'name': '_prover', 'type': 'address'}], 'name': 'set_prover', 'outputs': [], 'stateMutability': 'nonpayable', 'type': 'function'}, {'inputs': [], 'name': 'version', 'outputs': [{'name': '', 'type': 'string'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'prover', 'outputs': [{'name': '', 'type': 'address'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'price', 'outputs': [{'components': [{'name': 'previous', 'type': 'uint256'}, {'name': 'future', 'type': 'uint256'}], 'name': '', 'type': 'tuple'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'time', 'outputs': [{'components': [{'name': 'previous', 'type': 'uint256'}, {'name': 'future', 'type': 'uint256'}], 'name': '', 'type': 'tuple'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'max_acceleration', 'outputs': [{'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [{'name': '_initial_price', 'type': 'uint256'}, {'name': '_max_acceleration', 'type': 'uint256'}], 'outputs': [], 'stateMutability': 'nonpayable', 'type': 'constructor'}])
    prover = l2_web3.eth.contract(PROVER, abi=[{"inputs": [{"internalType": "bytes", "name": "_block_header_rlp", "type": "bytes"}, {"internalType": "bytes", "name": "_proof_rlp", "type": "bytes"}], "name": "prove", "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}], "stateMutability": "nonpayable", "type": "function"}])

    while True:
        if time_to_update(scrvusd, soracle):
            try:
                prove(boracle, prover)
                global last_update
                last_update = time.time()
            except Exception as e:
                print(e)
        sleep(12)


if __name__ == '__main__':
    loop()
