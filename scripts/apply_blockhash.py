import time
import os
import json

from eth_account import Account, account
from getpass import getpass
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

NETWORK = "https://bsc.rpc.blxrbdn.com"
POA = False  # bsc, gnosis, etc
BLOCKHASH_ORACLE = "0x7cDe6Ef7e2e2FD3B6355637F1303586D7262ba37"

COMMIT_BLOCK_HASH = "0x8039f84f0eb77eb0be5293b76b4581ab181b17950e0da213eaf8847d6cf8fc02"
BLOCKHASH_ORACLE_ABI = [{'name': 'CommitBlockHash', 'inputs': [{'name': 'committer', 'type': 'address', 'indexed': True}, {'name': 'number', 'type': 'uint256', 'indexed': True}, {'name': 'hash', 'type': 'bytes32', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'ApplyBlockHash', 'inputs': [{'name': 'number', 'type': 'uint256', 'indexed': True}, {'name': 'hash', 'type': 'bytes32', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'AddCommitter', 'inputs': [{'name': 'committer', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'RemoveCommitter', 'inputs': [{'name': 'committer', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'name': 'SetThreshold', 'inputs': [{'name': 'threshold', 'type': 'uint256', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'TransferOwnership', 'inputs': [{'name': 'owner', 'type': 'address', 'indexed': True}], 'anonymous': False, 'type': 'event'}, {'stateMutability': 'nonpayable', 'type': 'constructor', 'inputs': [{'name': '_threshold', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'view', 'type': 'function', 'name': 'get_block_hash', 'inputs': [{'name': '_number', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'commit', 'inputs': [{'name': '_number', 'type': 'uint256'}, {'name': '_hash', 'type': 'bytes32'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'apply', 'inputs': [{'name': '_number', 'type': 'uint256'}, {'name': '_hash', 'type': 'bytes32'}, {'name': '_committers', 'type': 'address[]'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'add_committer', 'inputs': [{'name': '_committer', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'remove_committer', 'inputs': [{'name': '_committer', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_threshold', 'inputs': [{'name': '_threshold', 'type': 'uint256'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'set_block_hash', 'inputs': [{'name': '_number', 'type': 'uint256'}, {'name': '_hash', 'type': 'bytes32'}], 'outputs': []}, {'stateMutability': 'view', 'type': 'function', 'name': 'is_committer', 'inputs': [{'name': '_committer', 'type': 'address'}], 'outputs': [{'name': '', 'type': 'bool'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'committer_count', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'commit_transfer_ownership', 'inputs': [{'name': '_future_owner', 'type': 'address'}], 'outputs': []}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'accept_transfer_ownership', 'inputs': [], 'outputs': []}, {'stateMutability': 'view', 'type': 'function', 'name': 'commitments', 'inputs': [{'name': 'arg0', 'type': 'address'}, {'name': 'arg1', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'get_committer', 'inputs': [{'name': 'arg0', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'threshold', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'owner', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'future_owner', 'inputs': [], 'outputs': [{'name': '', 'type': 'address'}]}]


def _retrieve_commits(logs, oracle) -> dict:
    commits = dict()
    for log in logs:
        if log["address"] != oracle.address:
            continue

        if log.get("topics") and log["topics"][0].hex() == COMMIT_BLOCK_HASH:
            committer = log["topics"][1].hex()
            block_number = int(log["topics"][2].hex(), 16)
            blockhash = log["topics"][3].hex()
        elif log.get("event") and log["event"] == "CommitBlockHash":
            committer = log["args"]["committer"]
            block_number = log["args"]["number"]
            blockhash = log["args"]["hash"]
        else:
            continue
        if committer:
            key = (block_number, blockhash)
            if key not in commits:
                commits[key] = set()
            commits[key].add(committer)
    return commits


def _get_commits(web3, oracle):
    lookup_start = web3.eth.block_number  # going backwards
    lookup_end = lookup_start - 86400 // 12  # assume 12sec block is max, look over last day
    lookup_size = 1024
    commits = dict()
    for to in range(lookup_start, lookup_end, -lookup_size):
        logs = oracle.events.CommitBlockHash().get_logs(
            from_block=max(to - lookup_size, lookup_end),
            to_block=to,
        )
        some_commits = _retrieve_commits(logs, oracle)
        for key, committers in some_commits.items():
            if key not in commits:
                commits[key] = set()
            commits[key].update(committers)
    return commits


def send_transaction(web3, signer, func):
    tx = func.build_transaction(
        {
            "from": signer.address,
            "nonce": web3.eth.get_transaction_count(signer.address),
        }
    )
    tx["gas"] = int(1.5 * web3.eth.estimate_gas(tx))

    signed_tx = web3.eth.account.sign_transaction(tx, private_key=signer.key)
    tx_hash = web3.eth.send_raw_transaction(signed_tx.raw_transaction)
    web3.eth.wait_for_transaction_receipt(tx_hash)
    time.sleep(20)  # wait for tx to propagate to nodes
    return web3.eth.get_transaction_receipt(tx_hash)


def apply_blockhash(web3, signer, oracle=BLOCKHASH_ORACLE, log=False):
    if isinstance(oracle, str):
        oracle = web3.eth.contract(address=oracle, abi=BLOCKHASH_ORACLE_ABI)

    commits = _get_commits(web3, oracle)
    threshold = oracle.functions.threshold().call()
    to_apply = []
    for commit, committers in commits.items():
        block_number, block_hash = commit
        if len(committers) >= threshold:
            try:
                oracle.functions.get_block_hash(block_number).call()
                continue
            except Exception as e:  # doesn't have
                to_apply.append(
                    (block_number, block_hash, list(sorted(list(committers), key=lambda s: int(s, 16))))
                )
    if log:
        print(f"To apply: {len(to_apply)}")
        for block_number, block_hash, committers in to_apply:
            print(f"  {block_number}: {block_hash.hex()} by {committers}")

    for block_number, block_hash, committers in to_apply:
        send_transaction(web3, signer, oracle.functions.apply(block_number, block_hash, committers))


def account_load_pkey(fname):
    path = os.path.expanduser(os.path.join('~', '.brownie', 'accounts', fname + '.json'))
    with open(path, 'r') as f:
        pkey = account.decode_keyfile_json(json.load(f), getpass())
        return Account.from_key(pkey)


if __name__ == "__main__":
    web3 = Web3(Web3.HTTPProvider(NETWORK))
    if POA:
        web3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)
    signer = account_load_pkey("keeper")
    apply_blockhash(web3, signer, log=True)
