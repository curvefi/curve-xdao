# @version 0.3.10
"""
@title Block Hash Oracle
@license MIT
@author Curve Finance
"""

event CommitBlockHash:
    keeper: indexed(address)
    block_number: indexed(uint256)
    block_hash: bytes32

event WriteBlockHash:
    block_number: indexed(uint256)
    block_hash: bytes32

event AddKeeper:
    keeper: indexed(address)

event RemoveKeeper:
    keeper: indexed(address)

event TransferOwnership:
    owner: indexed(address)


MAX_KEEPERS: constant(uint256) = 9


get_keeper: public(DynArray[address, MAX_KEEPERS])
get_block_hash: public(HashMap[uint256, bytes32])

hash_counter: HashMap[uint256, HashMap[bytes32, uint256]]  # block number -> block hash -> count
commitments: HashMap[address, HashMap[uint256, bytes32]]  # keeper -> block number -> block hash
commitments_counter: HashMap[uint256, uint256]  # block number -> number of commitments


owner: public(address)
future_owner: public(address)


@external
def __init__():
    self.owner = msg.sender
    log TransferOwnership(msg.sender)


@external
def commit_block_hash(_block_number: uint256, _block_hash: bytes32):
    """
    @notice Commit the block hash of a block, settling if quorum has been reached
    @param _block_number The block of interest
    @param _block_hash The hash of the block
    """
    assert _block_hash != empty(bytes32)  # dev: invalid block hash

    keepers: DynArray[address, MAX_KEEPERS] = self.get_keeper
    assert msg.sender in keepers  # dev: only keeper

    assert self.get_block_hash[_block_number] == empty(bytes32)  # dev: block hash already known
    assert self.commitments[msg.sender][_block_number] == empty(bytes32)  # dev: keeper already committed

    # number of times _block_hash has been committed
    hash_count: uint256 = self.hash_counter[_block_number][_block_hash] + 1
    self.hash_counter[_block_number][_block_hash] = hash_count

    # number of commitments made for _block_number
    commitments_count: uint256 = self.commitments_counter[_block_number] + 1
    self.commitments_counter[_block_number] = commitments_count

    # store the commitment made by this keeper
    self.commitments[msg.sender][_block_number] = _block_hash
    log CommitBlockHash(msg.sender, _block_number, _block_hash)

    # if not enough commitments have come in, return early since
    # we can't determine the block hash yet anyways
    if 10 * commitments_count < 20 * len(keepers) / 3:
        return

    multimodal: bool = False
    block_hash: bytes32 = _block_hash

    for keeper in keepers:
        # we already know the commitment for the caller, skip over them
        if keeper == msg.sender:
            continue

        # if this block hash is the same as the leader or empty continue
        commitment: bytes32 = self.commitments[keeper][_block_number]
        if commitment == block_hash or commitment == empty(bytes32):
            continue

        # if the number of times commitment has been committed is less
        # than the leading block hash then continue
        count: uint256 = self.hash_counter[_block_number][commitment]
        if count < hash_count:
            continue

        # multimodal in the lead means we can't make a decision
        multimodal = count == hash_count
        if not multimodal:
            # if we aren't multimodal update the leader
            hash_count = count
            block_hash = commitment

    # only write the confirmed block hash to storage if we have a
    # majority decision
    if (
        block_hash != empty(bytes32)
        and not multimodal
        and 10 * hash_count >= 20 * len(keepers) / 3
    ):
        self.get_block_hash[_block_number] = block_hash
        log WriteBlockHash(_block_number, block_hash)


@external
def add_keeper(_keeper: address):
    """
    @notice Add a keeper
    @dev The prospective keeper must not already have the role of keeper
    @param _keeper The account to grant the role of keeper to
    """
    assert msg.sender == self.owner  # dev: only owner
    assert _keeper not in self.get_keeper  # dev: already a keeper

    self.get_keeper.append(_keeper)
    log AddKeeper(_keeper)


@external
def remove_keeper(_keeper: address):
    """
    @notice Remove a keeper
    @dev The account to remove must already be a keeper
    @param _keeper The account to revoke the role of keeper from
    """
    assert msg.sender == self.owner  # dev: only owner

    keepers: DynArray[address, MAX_KEEPERS] = self.get_keeper
    keeper_count: uint256 = len(keepers)

    for idx in range(MAX_KEEPERS):
        if idx == keeper_count:
            break

        if keepers[idx] != _keeper:
            continue

        if idx < keeper_count-1:
            self.get_keeper[idx] = self.get_keeper[keeper_count-1]
        self.get_keeper.pop()

        log RemoveKeeper(_keeper)
        return

    raise  # dev: account is not a keeper


@external
def write_block_hash(_block_number: uint256, _block_hash: bytes32):
    assert msg.sender == self.owner  # dev: only owner

    self.get_block_hash[_block_number] = _block_hash

    log WriteBlockHash(_block_number, _block_hash)


@external
def commit_transfer_ownership(_future_owner: address):
    """
    @notice Transfer ownership to `_future_owner`
    @param _future_owner The account to commit as the future owner
    """
    assert msg.sender == self.owner  # dev: only owner

    self.future_owner = _future_owner


@external
def accept_transfer_ownership():
    """
    @notice Accept the transfer of ownership
    @dev Only the committed future owner can call this function
    """
    assert msg.sender == self.future_owner  # dev: only future owner

    self.owner = msg.sender
    log TransferOwnership(msg.sender)


@view
@external
def get_keeper_count() -> uint256:
    """
    @notice Get the total count of keepers
    """
    return len(self.get_keeper)
