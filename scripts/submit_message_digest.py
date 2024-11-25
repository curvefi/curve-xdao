import time
import os
import json
import eth_abi
import rlp

from eth.hash import keccak256
from eth_account import Account, account
from hexbytes import HexBytes
from getpass import getpass
from web3 import Web3, HTTPProvider
from web3.middleware import ExtraDataToPOAMiddleware


ETH_NETWORK = f"https://eth-mainnet.alchemyapi.io/v2/{os.environ['WEB3_ETHEREUM_MAINNET_ALCHEMY_API_KEY']}"  # ALTER
L1_NETWORK = f"https://bscrpc.com"  # ALTER

AGENT = 1  # ALTER
CHAIN_ID = 56  # ALTER
NONCE = 2  # ALTER
MESSAGES = []  # ALTER

BLOCK_NUMBER = 21242400  # ALTER: last applied block number

POA = (CHAIN_ID in (56,))
PROVER = {
    43114: "0xd5cF10C83aC5F30Ab27B6156DA9c238Aa63a63d0",  # avax
    250: "0xAb0ab357a10c0161002A91426912933750082A9d",  # ftm
    56: "0xbfF1f56c8e48e2F2F52941e16FEecc76C49f1825",  # bsc
    2222: "0x5373E1B9f2781099f6796DFe5D68DE59ac2F18E3",  # kava
}[CHAIN_ID]

BROADCASTER = "0x5786696bB5bE7fCDb9997E7f89355d9e97FF8d89"
MESSAGE_DIGEST_PROVER_ABI = [{'inputs': [{'internalType': 'address', 'name': '_block_hash_oracle', 'type': 'address'}, {'internalType': 'address', 'name': '_relayer', 'type': 'address'}], 'stateMutability': 'nonpayable', 'type': 'constructor'}, {'inputs': [], 'name': 'BLOCK_HASH_ORACLE', 'outputs': [{'internalType': 'address', 'name': '', 'type': 'address'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'RELAYER', 'outputs': [{'internalType': 'address', 'name': '', 'type': 'address'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [], 'name': 'nonce', 'outputs': [{'internalType': 'uint256', 'name': '', 'type': 'uint256'}], 'stateMutability': 'view', 'type': 'function'}, {'inputs': [{'internalType': 'uint256', 'name': '_agent', 'type': 'uint256'}, {'components': [{'internalType': 'address', 'name': 'target', 'type': 'address'}, {'internalType': 'bytes', 'name': 'data', 'type': 'bytes'}], 'internalType': 'struct IRelayer.Message[]', 'name': '_messages', 'type': 'tuple[]'}, {'internalType': 'bytes', 'name': '_block_header_rlp', 'type': 'bytes'}, {'internalType': 'bytes', 'name': '_proof_rlp', 'type': 'bytes'}], 'name': 'prove', 'outputs': [], 'stateMutability': 'nonpayable', 'type': 'function'}]

# https://github.com/ethereum/go-ethereum/blob/master/core/types/block.go#L69
BLOCK_HEADER = (
    "parentHash",
    "sha3Uncles",
    "miner",
    "stateRoot",
    "transactionsRoot",
    "receiptsRoot",
    "logsBloom",
    "difficulty",
    "number",
    "gasLimit",
    "gasUsed",
    "timestamp",
    "extraData",
    "mixHash",
    "nonce",
    "baseFeePerGas",  # added by EIP-1559 and is ignored in legacy headers
    "withdrawalsRoot",  # added by EIP-4895 and is ignored in legacy headers
    "blobGasUsed",  # added by EIP-4844 and is ignored in legacy headers
    "excessBlobGas",  # added by EIP-4844 and is ignored in legacy headers
    "parentBeaconBlockRoot",  # added by EIP-4788 and is ignored in legacy headers
)


def serialize_block(block):
    block_header = [
        HexBytes("0x") if (isinstance((v := block.get(k, 0)), int) and v == 0) or v == "0x0" else HexBytes(block[k])
        for k in BLOCK_HEADER
    ]
    encoded = rlp.encode(block_header)

    # Helper: https://blockhash.ardis.lu
    assert keccak256(encoded) == block["hash"], "Badly encoded block"
    return encoded


def serialize_proofs(proofs):
    account_proof = list(map(rlp.decode, map(HexBytes, proofs["accountProof"])))
    storage_proofs = [
        list(map(rlp.decode, map(HexBytes, proof["proof"]))) for proof in proofs["storageProof"]
    ]
    return rlp.encode([account_proof, *storage_proofs])


def hashmap(eth_web3, slot, value, type):
    if isinstance(slot, HexBytes):
        slot = int(slot.hex(), 16)
    return eth_web3.keccak(eth_abi.encode([f"(uint256,{type})"], [[slot, value]]))


def generate_proof(eth_web3, agent=AGENT, chain_id=CHAIN_ID, nonce=NONCE, block_number=BLOCK_NUMBER, log=False):
    block = eth_web3.eth.get_block(block_number)
    if log:
        print(f"Generating proof for block {block.number}, {block.hash.hex()}")
    block_header_rlp = serialize_block(block)
    message_digest_slot = hashmap(eth_web3, hashmap(eth_web3, hashmap(eth_web3, 8, agent, "uint256"), chain_id, "uint256"), nonce, "uint256")
    proof_rlp = serialize_proofs(eth_web3.eth.get_proof(BROADCASTER, [message_digest_slot], block_number))

    with open("header.txt", "w") as f:
        f.write(block_header_rlp.hex())
    with open("proof.txt", "w") as f:
        f.write(proof_rlp.hex())

    return block_header_rlp.hex(), proof_rlp.hex()


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


def submit_proof(agent=AGENT, messages=MESSAGES, proofs=None, prover=PROVER, web3=None, signer=None):
    if proofs:
        block_header_rlp, proof_rlp = proofs
    else:
        with open("header.txt") as f:
            block_header_rlp = f.read()
        with open("proof.txt") as f:
            proof_rlp = f.read()

    encoded_messages = []
    for addr, calldata in messages:
        if isinstance(calldata, str):
            encoded_messages.append((addr, bytes.fromhex(calldata)))
        else:
            encoded_messages.append((addr, calldata))

    if isinstance(prover, str):
        prover = web3.eth.contract(address=prover, abi=MESSAGE_DIGEST_PROVER_ABI)
        send_transaction(
            web3,
            signer,
            prover.functions.prove(agent, encoded_messages, bytes.fromhex(block_header_rlp), bytes.fromhex(proof_rlp))
        )
    else:
        prover.prove(agent, encoded_messages, bytes.fromhex(block_header_rlp), bytes.fromhex(proof_rlp))


def account_load_pkey(fname):
    path = os.path.expanduser(os.path.join('~', '.brownie', 'accounts', fname + '.json'))
    with open(path, 'r') as f:
        pkey = account.decode_keyfile_json(json.load(f), getpass())
        return Account.from_key(pkey)


if __name__ == "__main__":
    eth_web3 = Web3(HTTPProvider(ETH_NETWORK))
    web3 = Web3(HTTPProvider(L1_NETWORK))
    if POA:
        web3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)
    signer = account_load_pkey("keeper")  # ALTER
    proofs = generate_proof(eth_web3, log=True)
    submit_proof(web3=web3, signer=signer, proofs=proofs)
