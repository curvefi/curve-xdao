# @version 0.3.10
"""
@title Block Hash Oracle
@license MIT
@author Curve Finance
"""

event CommitBlockHash:
    committer: indexed(address)
    number: indexed(uint256)
    hash: bytes32

event ApplyBlockHash:
    number: indexed(uint256)
    hash: bytes32

event AddCommitter:
    committer: indexed(address)

event RemoveCommitter:
    committer: indexed(address)

event SetThreshold:
    threshold: uint256

event TransferOwnership:
    owner: indexed(address)


MAX_COMMITTERS: constant(uint256) = 32


block_hash: HashMap[uint256, bytes32]
commitments: public(HashMap[address, HashMap[uint256, bytes32]])

committer_idx: HashMap[address, uint256]  # 0 represents not in list
get_committer: public(DynArray[address, MAX_COMMITTERS])

threshold: public(uint256)

owner: public(address)
future_owner: public(address)


@external
def __init__(_threshold: uint256):
    self.threshold = _threshold
    log SetThreshold(_threshold)

    self.owner = msg.sender
    log TransferOwnership(msg.sender)


@view
@external
def get_block_hash(_number: uint256) -> bytes32:
    """
    @notice Query the block hash of a block.
    @dev Reverts for block numbers which have yet to be set.
    """
    block_hash: bytes32 = self.block_hash[_number]
    assert block_hash != empty(bytes32)

    return block_hash


@external
def commit(_number: uint256, _hash: bytes32):
    """
    @notice Commit a block hash.
    """
    assert self.committer_idx[msg.sender] != 0

    self.commitments[msg.sender][_number] = _hash
    log CommitBlockHash(msg.sender, _number, _hash)


@external
def apply(_number: uint256, _hash: bytes32, _committers: DynArray[address, MAX_COMMITTERS]):
    """
    @notice Apply a block hash.
    @dev The list of committers must be sorted in ascending hexadecimal order.
    """
    assert self.block_hash[_number] == empty(bytes32)
    assert _hash != empty(bytes32)
    assert len(_committers) >= self.threshold

    previous: uint256 = 0

    for committer in _committers:
        assert self.commitments[committer][_number] == _hash

        assert previous < convert(committer, uint256)
        previous = convert(committer, uint256)

    self.block_hash[_number] = _hash
    log ApplyBlockHash(_number, _hash)


@external
def add_committer(_committer: address):
    """
    @notice Add a committer to the set of authorized committers.
    """
    assert msg.sender == self.owner
    assert _committer != empty(address)
    assert self.committer_idx[_committer] == 0

    self.get_committer.append(_committer)
    self.committer_idx[_committer] = len(self.get_committer)

    log AddCommitter(_committer)


@external
def remove_committer(_committer: address):
    """
    @notice Remove a committer from the set of authorized committers.
    """
    assert msg.sender == self.owner

    last_idx: uint256 = len(self.get_committer) - 1  # dev: underflow
    if last_idx != 0:
        committer_idx: uint256 = self.committer_idx[_committer] - 1  # dev: underflow
        replacement: address = self.get_committer[last_idx]

        self.get_committer[committer_idx] = replacement
        self.committer_idx[replacement] = committer_idx + 1

    self.get_committer.pop()
    self.committer_idx[_committer] = 0

    log RemoveCommitter(_committer)


@external
def set_threshold(_threshold: uint256):
    """
    @notice Set the threshold.
    """
    assert msg.sender == self.owner

    self.threshold = _threshold
    log SetThreshold(_threshold)


@external
def set_block_hash(_number: uint256, _hash: bytes32):
    assert msg.sender == self.owner

    self.block_hash[_number] = _hash
    log ApplyBlockHash(_number, _hash)


@view
@external
def is_committer(_committer: address) -> bool:
    """
    @notice Query the committer status of an account.
    """
    return self.committer_idx[_committer] != 0


@view
@external
def committer_count() -> uint256:
    """
    @notice Query the total number of committers.
    """
    return len(self.get_committer)


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
