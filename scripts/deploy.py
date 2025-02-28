import json

from brownie import (
    chain,
    BlockHashOracle,
    GaugeTypeOracle,
    GaugeTypeProver,
    LayerZeroBridgeCRV,
    LayerZeroReceiver,
    LayerZeroSender,
    CRVUSDLayerZeroBridge,
    CRVUSDLayerZeroBridgeETH,
    MinterProxy,
    MessageDigestVerifier,
    XYZRelayer,
    Agent,
    history,
    Minter,
    Token,
    accounts,
    network,
    web3,
)


def make_blueprint(initcode):
    if isinstance(initcode, str):
        initcode = bytes.fromhex(initcode[2:])
    initcode = b"\xfe\x71\x00" + initcode  # eip-5202 preamble version 0
    initcode = (
        b"\x61" + len(initcode).to_bytes(2, "big") + b"\x3d\x81\x60\x0a\x3d\x39\xf3" + initcode
    )
    return initcode


def main(gauge_type, lz_endpoint, lz_chain_id):
    deployer = accounts.load("dev")
    temp = accounts.add()

    # deploy DAO agents
    agent_blueprint = deployer.transfer(data=make_blueprint(Agent.bytecode)).contract_address

    relayer = XYZRelayer.deploy(
        agent_blueprint, deployer.get_deployment_address(deployer.nonce + 1), {"from": deployer}
    )
    MessageDigestVerifier.deploy(
        deployer.get_deployment_address(deployer.nonce + 1), relayer, {"from": deployer}, publish_source=False
    )

    # deploy CRV token + Minter
    block_hash_oracle = BlockHashOracle.deploy(1, {"from": deployer})  # transfer ownership
    gauge_type_oracle = GaugeTypeOracle.deploy({"from": deployer})  # transfer ownership
    gauge_type_oracle.set_prover(
        deployer.get_deployment_address(deployer.nonce + 1), {"from": deployer}
    )

    GaugeTypeProver.deploy(
        block_hash_oracle, gauge_type_oracle, {"from": deployer}, publish_source=False
    )

    crv_token = Token.deploy("Curve DAO Token", "CRV", 18, {"from": deployer})
    minter = Minter.deploy(crv_token, gauge_type_oracle, gauge_type, {"from": deployer})
    crv_token.set_minter(minter, {"from": deployer})

    # deploy crvUSD token + minter proxy
    crvusd_token = Token.deploy("Curve.fi USD Stablecoin", "crvUSD", 18, {"from": deployer})
    minter_proxy = MinterProxy.deploy(crvusd_token, {"from": deployer})  # transfer ownership
    crvusd_token.set_minter(minter_proxy, {"from": deployer})

    # calculate total native required for temp account
    required = LayerZeroBridgeCRV.deploy.estimate_gas(
        86400,
        0,
        500_000,
        crv_token,
        minter,
        lz_endpoint,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        101,
        {"from": deployer},
    )
    required += LayerZeroReceiver.deploy.estimate_gas(
        block_hash_oracle, lz_endpoint, {"from": deployer}
    )
    required += CRVUSDLayerZeroBridge.deploy.estimate_gas(
        86400, 0, 101, lz_endpoint, crvusd_token, minter_proxy, {"from": deployer}
    )

    gas_price = int(web3.eth.gas_price * 1.1)
    deployer.transfer(temp, int(required * 1.3 * gas_price), gas_price=gas_price)

    # deploy bridges + receiver
    crv_bridge = LayerZeroBridgeCRV.deploy(
        86400,
        0,
        500_000,
        crv_token,
        minter,
        lz_endpoint,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        101,
        {"from": temp, "gas_price": gas_price},
    )  # transfer ownership

    crvusd_bridge = CRVUSDLayerZeroBridge.deploy(
        86400, 0, 101, lz_endpoint, crvusd_token, minter_proxy, {"from": temp}
    )  # transfer ownership
    minter_proxy.set_minter(crvusd_bridge, True, {"from": deployer})

    block_hash_oracle.add_committer(temp.get_deployment_address(temp.nonce + 1), {"from": deployer})
    LayerZeroReceiver.deploy(block_hash_oracle, lz_endpoint, {"from": temp, "gas_price": gas_price})

    # transfer ownerships
    for contract in [block_hash_oracle, gauge_type_oracle, minter_proxy, crv_bridge, crvusd_bridge]:
        contract.commit_transfer_ownership(
            relayer.OWNERSHIP_AGENT(), {"from": contract.owner(), "required_confs": 0}
        )

    try:
        temp.transfer(deployer, temp.balance() - 21000 * web3.eth.gas_price, gas_price=web3.eth.gas_price)
    except:
        pass

    crv_token = crv_token.address

    deployments = {chain.id: [tx.contract_address for tx in history if tx.contract_address is not None]}

    network.disconnect()
    network.connect("mainnet")

    # calculate required native for temp account
    required = LayerZeroBridgeCRV.deploy.estimate_gas(
        86400,
        0,
        500_000,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        "0xd061D61a4d941c39E5453435B6345Dc261C2fcE0",
        "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675",
        crv_token,
        lz_chain_id,
        {"from": deployer},
    )
    required += LayerZeroSender.deploy.estimate_gas(300_000, lz_chain_id, {"from": deployer})
    required += CRVUSDLayerZeroBridgeETH.deploy.estimate_gas(
        86400, 0, lz_chain_id, {"from": deployer}
    )

    gas_price = int(web3.eth.gas_price * 1.1)
    deployer.transfer(temp, int(required * 1.25 * gas_price), gas_price=gas_price)

    # deploy bridges + sender
    crv_bridge_eth = LayerZeroBridgeCRV.deploy(
        86400,
        0,
        500_000,
        "0xD533a949740bb3306d119CC777fa900bA034cd52",
        "0xd061D61a4d941c39E5453435B6345Dc261C2fcE0",
        "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675",
        crv_token,
        lz_chain_id,
        {"from": temp},
    )
    crvusd_bridge_eth = CRVUSDLayerZeroBridgeETH.deploy(86400, 0, lz_chain_id, {"from": temp})
    sender = LayerZeroSender.deploy(300_000, lz_chain_id, {"from": temp})

    for contract in [crv_bridge_eth, crvusd_bridge_eth]:
        contract.commit_transfer_ownership("0x5a02d537fE0044E3eF506ccfA08f370425d1408C", {"from": temp})
    
    sender.commit_transfer_ownership("0x40907540d8a6C65c637785e8f8B742ae6b0b9968", {"from": temp})

    try:
        temp.transfer(deployer, temp.balance() - 21000 * web3.eth.gas_price, gas_price=web3.eth.gas_price)
    except:
        pass

    deployments[chain.id] = [tx.contract_address for tx in history if tx.contract_address is not None]
    deployments["seed"] = temp.private_key

    with open("deployments.json", "w") as f:
        json.dump(deployments, f, indent=2)
