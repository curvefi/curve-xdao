import json
import os

from brownie import (
    BlockHashOracle,
    GaugeTypeOracle,
    GaugeTypeProver,
    LayerZeroBridgeCRV,
    LayerZeroReceiver,
    LayerZeroSender,
    Minter,
    Token,
    accounts,
    network,
    web3,
)

dev = accounts.load("dev")
temp = accounts.add()

DEPLOYMENTS = {}
REQUIRED_CONFS = 2


def mainnet(token_mirror, lz_chain_id):
    deployments = {}

    required = LayerZeroBridgeCRV.deploy.estimate_gas(
        86400,
        0,
        500_000,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        "0xd061D61a4d941c39E5453435B6345Dc261C2fcE0",
        "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675",
        token_mirror,
        lz_chain_id,
        {"from": dev, "required_confs": REQUIRED_CONFS},
    )

    required += LayerZeroSender.deploy.estimate_gas(
        300_000, lz_chain_id, {"from": dev, "required_confs": REQUIRED_CONFS}
    )
    gas_price = web3.eth.gas_price
    dev.transfer(temp, required * gas_price * 1.25, gas_price=gas_price)

    deployments["bridge"] = bridge = LayerZeroBridgeCRV.deploy(
        86400,
        0,
        500_000,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        "0xd061D61a4d941c39E5453435B6345Dc261C2fcE0",
        "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675",
        token_mirror,
        lz_chain_id,
        {"from": temp, "gas_price": gas_price, "required_confs": REQUIRED_CONFS},
    )

    deployments["sender"] = sender = LayerZeroSender.deploy(
        300_000,
        lz_chain_id,
        {"from": temp, "gas_price": gas_price, "required_confs": REQUIRED_CONFS},
    )

    DEPLOYMENTS[f"mainnet->{lz_chain_id}"] = {k: v.address for k, v in deployments.items()}

    if temp.balance() != 0:
        try:
            temp.transfer(
                dev, temp.balance() - 21000 * web3.eth.gas_price, gas_price=web3.eth.gas_price
            )
        except:
            pass


def sidechain(network_type_id, lz_endpoint):
    deployments = {}

    deployments["token"] = token = Token.deploy(
        "Curve DAO Token", "CRV", 18, {"from": dev, "required_confs": REQUIRED_CONFS}
    )

    deployments["block_hash_oracle"] = block_hash_oracle = BlockHashOracle.deploy(
        1, {"from": dev, "required_confs": REQUIRED_CONFS}
    )
    deployments["gauge_type_oracle"] = gauge_type_oracle = GaugeTypeOracle.deploy(
        {"from": dev, "required_confs": REQUIRED_CONFS}
    )

    deployments["gauge_type_prover"] = gauge_type_prover = GaugeTypeProver.deploy(
        block_hash_oracle,
        gauge_type_oracle,
        {"from": dev, "required_confs": REQUIRED_CONFS},
        publish_source=False,
    )
    try:
        gauge_type_oracle.set_prover(
            gauge_type_prover, {"from": dev, "required_confs": REQUIRED_CONFS}
        )
    except:
        pass

    deployments["minter"] = minter = Minter.deploy(
        token, gauge_type_oracle, network_type_id, {"from": dev, "required_confs": REQUIRED_CONFS}
    )
    try:
        token.set_minter(minter, {"from": dev, "required_confs": REQUIRED_CONFS})
    except:
        pass

    required = LayerZeroBridgeCRV.deploy.estimate_gas(
        86400,
        0,
        500_000,
        token,
        minter,
        lz_endpoint,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        101,  # ethereum
        {"from": dev, "required_confs": REQUIRED_CONFS},
    )

    required += LayerZeroReceiver.deploy.estimate_gas(
        block_hash_oracle, lz_endpoint, {"from": dev, "required_confs": REQUIRED_CONFS}
    )
    gas_price = web3.eth.gas_price
    dev.transfer(temp, required * gas_price * 1.25, gas_price=gas_price)

    deployments["bridge"] = bridge = LayerZeroBridgeCRV.deploy(
        86400,
        0,
        500_000,
        token,
        minter,
        lz_endpoint,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        101,  # ethereum
        {"from": temp, "gas_price": gas_price, "required_confs": REQUIRED_CONFS},
    )

    deployments["receiver"] = receiver = LayerZeroReceiver.deploy(
        block_hash_oracle,
        lz_endpoint,
        {"from": temp, "gas_price": gas_price, "required_confs": REQUIRED_CONFS},
    )

    try:
        block_hash_oracle.add_committer(receiver, {"from": dev, "required_confs": REQUIRED_CONFS})
    except:
        pass

    DEPLOYMENTS[f"sidechain={network_type_id}"] = {k: v.address for k, v in deployments.items()}

    if temp.balance() != 0:
        try:
            temp.transfer(
                dev, temp.balance() - 21000 * web3.eth.gas_price, gas_price=web3.eth.gas_price
            )
        except:
            pass

    return token


def main():
    token = sidechain(8, "0x3c2269811836af69497E5F486A85D7316753cf62").address

    network.disconnect()
    network.connect("mainnet")

    mainnet(token, 106)

    with open("deployments/avalanche.json", "w") as f:
        json.dump(DEPLOYMENTS, f)
