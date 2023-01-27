%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256

from openzeppelin.access.ownable.library import Ownable
from openzeppelin.token.erc20.IERC20 import IERC20

from src.library import MasterChef


@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(token_per_block: Uint256){
    MasterChef.initializer(token_per_block);
    return ();
}

@external
func add{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    lp_token: felt, allocation_point: Uint256
) {
    MasterChef.add(lp_token, allocation_point);
    return ();
}

@external
func set{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    pid: felt, allocation_point: Uint256
) {
    MasterChef.set(pid, allocation_point);
    return ();
}

@view
func getMultiplier{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _from: felt, to: felt
) -> (multiplier: Uint256) {
    return MasterChef.getMultiplier(_from, to);
}

@view
func getMultiplierPure{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    bonus_end_block: felt, _from: felt, to: felt
) -> (multiplier: Uint256) {
    return MasterChef.getMultiplierPure(bonus_end_block, _from, to);
}

@view
func pendingChefToken{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _from: felt, to: felt, pid: felt, user: felt
) -> (multiplier: Uint256) {
    return MasterChef.pendingChefToken(_from, to, pid, user);
}