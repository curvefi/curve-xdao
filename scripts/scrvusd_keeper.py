import time
from time import sleep

from web3 import Web3
from web3.eth import AsyncEth
import json
import os

from getpass import getpass
from eth_account import account

from submit_scrvusd_price import generate_proof

ETH_NETWORK = f"https://eth-mainnet.alchemyapi.io/v2/{os.environ['WEB3_ETHEREUM_MAINNET_ALCHEMY_API_KEY']}"
L2_NETWORK = f"https://opt-mainnet.g.alchemy.com/v2/{os.environ['WEB3_OPTIMISM_MAINNET_ALCHEMY_API_KEY']}"

SCRVUSD = "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367"

B_ORACLE = ""
S_ORACLE = ""
PROVER = ""

last_update = 0

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
wallet_pk = account_load_pkey("keeper")


def prove(boracle, prover):
    # Apply latest available blockhash
    tx = boracle.functions.apply().build_transaction()
    signed_tx = l2_web3.eth.account.sign_transaction(tx, private_key=wallet_pk)
    tx_hash = l2_web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    l2_web3.eth.wait_for_transaction_receipt(tx_hash)
    tx_receipt = l2_web3.eth.get_transaction_receipt(tx_hash)
    number = -1
    for log in tx_receipt["logs"]:
        if log["address"] == boracle.address:
            if log["topics"][0].hex() == APPLY_BLOCK_HASH:
                number = int(log["topics"][1].hex(), 16)
                break
            if log["topics"][0].hex() == COMMIT_BLOCK_HASH:
                number = int(log["topics"][2].hex(), 16)
                break
    assert number > 0, "Applied block number not retrieved"
    print(f"Applied block: {number}")

    # Generate and submit proof for applied blockhash
    proofs = generate_proof(eth_web3, number)
    tx = prover.functions.prove(proofs[0], proofs[1]).build_transaction()
    signed_tx = l2_web3.eth.account.sign_transaction(tx, private_key=wallet_pk)
    l2_web3.eth.send_raw_transaction(signed_tx.rawTransaction)
    l2_web3.eth.wait_for_transaction_receipt(tx_hash)
    print(f"Submitted proof")


def time_to_update():
    # can be any relative change or time
    return time.time() - last_update >= 4 * 3600  # Every 4 hours


def loop():
    boracle = l2_web3.eth.contract(B_ORACLE, abi=[{'name': 'CommitBlockHash', 'inputs': [{'name': 'committer', 'type': 'address', 'indexed': True}, {'name': 'number', 'type': 'uint256', 'indexed': True}, {'name': 'hash', 'type': 'bytes32', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'name': 'ApplyBlockHash', 'inputs': [{'name': 'number', 'type': 'uint256', 'indexed': True}, {'name': 'hash', 'type': 'bytes32', 'indexed': False}], 'anonymous': False, 'type': 'event'}, {'stateMutability': 'view', 'type': 'function', 'name': 'get_block_hash', 'inputs': [{'name': '_number', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'commit', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'nonpayable', 'type': 'function', 'name': 'apply', 'inputs': [], 'outputs': [{'name': '', 'type': 'uint256'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'block_hash', 'inputs': [{'name': 'arg0', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}, {'stateMutability': 'view', 'type': 'function', 'name': 'commitments', 'inputs': [{'name': 'arg0', 'type': 'address'}, {'name': 'arg1', 'type': 'uint256'}], 'outputs': [{'name': '', 'type': 'bytes32'}]}])
    prover = l2_web3.eth.contract(PROVER, abi=[{"inputs": [{"internalType": "bytes", "name": "_block_header_rlp", "type": "bytes"}, {"internalType": "bytes", "name": "_proof_rlp", "type": "bytes"}], "name": "prove", "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}], "stateMutability": "nonpayable", "type": "function"}])

    while True:
        if time_to_update():
            try:
                prove(boracle, prover)
                global last_update
                last_update = time.time()
            except Exception as e:
                print(e)
        sleep(12)


if __name__ == '__main__':
    loop()
