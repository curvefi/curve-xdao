import eth_abi
import rlp
import web3
from hexbytes import HexBytes

BLOCK_NUMBER = 18578883
SCRVUSD = "0x0655977FEb2f289A4aB78af67BAB0d17aAb84367"

PROVER = ""

ASSET_PARAM_SLOTS = [
    21,  # total_debt
    22,  # total_idle, slot doesn't exist
]
SUPPLY_PARAM_SLOTS = [
    20,  # totalSupply
    38,  # full_profit_unlock_date
    39,  # profit_unlocking_rate
    40,  # last_profit_update
    web3.Web3.keccak(eth_abi.encode(["(uint256,address)"], [[18, SCRVUSD]])),  # balance_of_self
    # ts from block header
]

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
        HexBytes("0x") if (isinstance((v := block[k]), int) and v == 0) or v == "0x0" else HexBytes(block[k])
        for k in BLOCK_HEADER
        if k in block
    ]
    block_header[14] = HexBytes("0x0000000000000000")  # nonce
    return rlp.encode(block_header)


def serialize_proofs(proofs):
    account_proof = list(map(rlp.decode, map(HexBytes, proofs["accountProof"])))
    storage_proofs = [
        list(map(rlp.decode, map(HexBytes, proof["proof"]))) for proof in proofs["storageProof"]
    ]
    return rlp.encode([account_proof, *storage_proofs])


def generate_proof(eth_web3, block_number=BLOCK_NUMBER, log=False):
    block = eth_web3.eth.get_block(block_number)
    if log:
        print(f"Generating proof for block {block.number}, {block.hash.hex()}")
    block_header_rlp = serialize_block(block)
    proof_rlp = serialize_proofs(eth_web3.eth.get_proof(SCRVUSD, ASSET_PARAM_SLOTS + SUPPLY_PARAM_SLOTS, block_number))

    with open("header.txt", "w") as f:
        f.write(block_header_rlp.hex())
    with open("proof.txt", "w") as f:
        f.write(proof_rlp.hex())

    return block_header_rlp.hex(), proof_rlp.hex()


def submit_proof(proofs, prover=PROVER):
    if proofs:
        block_header_rlp, proof_rlp = proofs
    else:
        with open("header.txt") as f:
            block_header_rlp = f.read()
        with open("proof.txt") as f:
            proof_rlp = f.read()

    if isinstance(prover, str):
        from brownie import accounts, ScrvusdProver
        dev = accounts.load("dev")
        prover = ScrvusdProver.at(prover)
        prover.prove(bytes.fromhex(block_header_rlp), bytes.fromhex(proof_rlp), {"from": dev})
    else:
        prover.prove(bytes.fromhex(block_header_rlp), bytes.fromhex(proof_rlp))
