%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_block_number, get_caller_address, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_lt, uint256_eq, uint256_check, assert_uint256_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.bool import TRUE, FALSE

from openzeppelin.access.ownable.library import Ownable
from openzeppelin.security.safemath.library import SafeUint256

from src.tokens.interfaces.IERC20 import IERC20

struct UserInfo {
    amount: Uint256,
    reward_debt: Uint256,
}

struct PoolInfo {
    lp_token: felt,
    allocation_point: Uint256,
    last_reward_block: felt,
    accumalated_reward_per_share: Uint256,
}

//  
// Constants
//
const CHEF_TOKEN = 0;

const BONUS_MULTIPLIER = 10;

const SHARE_PRECISION_VALUE = 1000000000000;

//
// Storage Variables
//
@storage_var
func chef_token_per_block() -> (amount: Uint256) {
}

@storage_var
func bonus_end_block() -> (amount: felt) {
}

@storage_var
func start_block() -> (amount: felt) {
}

@storage_var
func pools_info(pid: felt) -> (info: PoolInfo) {
}

@storage_var
func users_info(pid: felt, address: felt) -> (info: UserInfo) {
}

@storage_var
func pool_length() -> (value: felt) {
}

@storage_var
func total_allocation_point() -> (value: Uint256) {
}

//
// Event
//
@event
func Deposit(user: felt, pid: felt, amount: Uint256) {
}

@event
func Withdraw(user: felt, pid: felt, amount: Uint256) {
}

@event
func EmergencyWithdraw(user: felt, pid: felt, amount: Uint256) {
}

namespace MasterChef {
    
    //
    // Initializer
    //

    func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        token_per_block: Uint256
    ) {
        with_attr error_message("MasterChef: token_per_block is not a valid Uint256") {
            uint256_check(token_per_block);
        }
        let (caller) = get_caller_address();
        Ownable.initializer(caller);
        let (block_number) = get_block_number();
        start_block.write(block_number);
        bonus_end_block.write(block_number + 20);
        chef_token_per_block.write(token_per_block);
        return ();
    }

    //
    // Impure Functions
    //

    func add{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        lp_token: felt, allocation_point: Uint256
    ) {
        Ownable.assert_only_owner();
        with_attr error_message("MasterChef: allocation_point is not a valid Uint256") {
            uint256_check(allocation_point);
        }
        let (block_number) = get_block_number();
        let last_reward_block = block_number;
        let (old_pool_length) = pool_length.read();
        let new_pool_length = old_pool_length + 1;
        pool_length.write(new_pool_length);
        let pool_info = PoolInfo(lp_token, allocation_point, last_reward_block, Uint256(0, 0));
        pools_info.write(new_pool_length, pool_info);
        let (old_total_allocation_point) = total_allocation_point.read();
        let (new_total_allocation_point) = SafeUint256.add(old_total_allocation_point, allocation_point);
        total_allocation_point.write(new_total_allocation_point);
        return ();
    }

    func set{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        pid: felt, allocation_point: Uint256
    ) {
        Ownable.assert_only_owner();
        with_attr error_message("MasterChef: allocation_point is not a valid Uint256") {
            uint256_check(allocation_point);
        }
        let (pool_info) = pools_info.read(pid);
        let (old_total_allocation_point) = total_allocation_point.read();
        let (old_total_allocation_point_plus_allocation_point) = SafeUint256.add(old_total_allocation_point, allocation_point);
        let (new_total_allocation_point) = SafeUint256.sub_le(old_total_allocation_point_plus_allocation_point, pool_info.allocation_point);
        total_allocation_point.write(new_total_allocation_point);
        pools_info.write(pid, PoolInfo(pool_info.lp_token, allocation_point, pool_info.last_reward_block, pool_info.accumalated_reward_per_share));
        return ();
    }

    func getMultiplier{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _from: felt, to: felt
    ) -> (multiplier: Uint256) {
        let (block) = bonus_end_block.read();
        return getMultiplierPure(block, _from, to);
    }

    func pendingChefToken{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_from: felt, to: felt, pid: felt, user: felt) -> (value: Uint256) {
        let (multiplier) = getMultiplier(_from, to);
        let (pool_info) = pools_info.read(pid);
        let (user_info) = users_info.read(pid, user);
        let (contract_address) = get_contract_address();
        let (lp_supply) = IERC20.balanceOf(contract_address=pool_info.lp_token, account=contract_address);
        let (block_number) = get_block_number();
        return pendingChefTokenPure(pool_info, user_info, multiplier, lp_supply, block_number);
    }

    func updatePool{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(pid: felt) {
        let pool_info = pools_info.read(pid);
        let (block_number) = get_block_number();
        let last_reward_block = pool_info.last_reward_block;
        let block_number_is_less = FALSE;
        %{
            if ids.block_number <= ids.last_reward_block:
                ids.block_number_is_less = 1
        %}
        if (block_number_is_less == TRUE){
            return ();
        }
        let (contract_address) = get_contract_address();
        let (lp_supply) = IERC20.balanceOf(contract_address=pool_info.lp_token, account=contract_address);
        let (lp_supply_is_zero) = uint256_eq(lp_supply, Uint256(0, 0));
        if (lp_supply_is_zero == TRUE){
            pools_info.write(pid, PoolInfo(pool_info.lp_token, pool_info.allocation_point, block_number, pool_info.accumalated_reward_per_share));
            return ();
        }
        let (multiplier) = getMultiplier(pool_info.last_reward_block, block_number);
        let (multiplier_times_token_per_block) = SafeUint256.mul((SafeUint256.mul(multiplier, chef_token_per_block)), pool_info.allocation_point);
        let (chef_token_reward, _) = SafeUint256.div_rem(multiplier_times_token_per_block, total_allocation_point.read());
        IERC20.mint(contract_address=CHEF_TOKEN, to=contract_address, chef_token_reward);
        let (reward_times_precision) = SafeUint256.mul(chef_token_reward, Uint256(SHARE_PRECISION_VALUE, 0));
        let (share, _) = SafeUint256.div_rem(reward_times_precision, lp_supply);
        let (new_accumulated_reward_per_share) = SafeUint256.add(pool_info.accumalated_reward_per_share, share);
        pools_info.write(pid, PoolInfo(pool_info.lp_token, pool_info.allocation_point, block_number, new_accumulated_reward_per_share));
        return ();
    }

    func deposit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(pid: felt, amount: Uint256){
        with_attr error_message("MasterChef: amount is not a valid Uint256") {
            uint256_check(amount);
        }
        let pool_info = pools_info.read(pid);
        let (user) = get_caller_address();
        let user_info = users_info.read(pid, user);
        updatePool(pid);
        let (amount_is_greater_than_zero) = uint256_lt(Uint256(0, 0), amount);
        if (amount_is_greater_than_zero == TRUE) {
            let (amount_times_a_r_p_s) = SafeUint256.mul(user.amount, pool_info.accumalated_reward_per_share);
            let (scale_down_by_share_precision, _) = SafeUint256.div_rem(amount_times_a_r_p_s, Uint256(SHARE_PRECISION_VALUE, 0));
            let (reward_debt_removed) = SafeUint256.sub_le(scale_down_by_share_precision, user.reward_debt);
            IERC20.transfer(contract_address=CHEF_TOKEN, recipient=user, amount=reward_debt_removed);
        }
        let (contract_address) = get_contract_address();
        IERC20.transferFrom(contract_address=pool_info.lp_token, sender=user, recipient=contract_address, amount=amount);
        let (new_amount) = SafeUint256.add(user_info.amount, amount);
        let (amount_times_a_r_p_s) = SafeUint256.mul(user.amount, pool_info.accumalated_reward_per_share);
        let (scale_down_by_share_precision, _) = SafeUint256.div_rem(amount_times_a_r_p_s, Uint256(SHARE_PRECISION_VALUE, 0));
        users_info.write(pid, user, UserInfo(new_amount, scale_down_by_share_precision));
        Deposit.emit(pid, user, amount);
        return ();
    }

    func withdraw{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(pid: felt, amount: felt){
        with_attr error_message("MasterChef: amount is not a valid Uint256") {
            uint256_check(amount);
        }
        let pool_info = pools_info.read(pid);
        let (user) = get_caller_address();
        let user_info = users_info.read(pid, user);
        with_attr error_message("MasterChef: amount should less than or equal to user amount") {
            assert_uint256_le(amount, user_info.amount);
        }
        updatePool(pid);
        let (amount_times_a_r_p_s) = SafeUint256.mul(user.amount, pool_info.accumalated_reward_per_share);
        let (scale_down_by_share_precision, _) = SafeUint256.div_rem(amount_times_a_r_p_s, Uint256(SHARE_PRECISION_VALUE, 0));
        let (reward_debt_removed) = SafeUint256.sub_le(scale_down_by_share_precision, user.reward_debt);
        IERC20.transfer(contract_address=CHEF_TOKEN, recipient=user, amount=reward_debt_removed);
        let (new_amount) = SafeUint256.sub_le(user_info.amount, amount);
        let (amount_times_a_r_p_s) = SafeUint256.mul(user.amount, pool_info.accumalated_reward_per_share);
        let (scale_down_by_share_precision, _) = SafeUint256.div_rem(amount_times_a_r_p_s, Uint256(SHARE_PRECISION_VALUE, 0));
        users_info.write(pid, user, UserInfo(new_amount, scale_down_by_share_precision));
        IERC20.transfer(contract_address=pool_info.lp_token, recipient=user, amount=reward_debt_removed);
        Withdraw.emit(pid, user, amount);
        return ();
    }

    //
    // Pure Functions
    //

    func getMultiplierPure{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        bonus_end_block: felt, _from: felt, to: felt
    ) -> (multiplier: Uint256) {
        let to_check = is_le(to, bonus_end_block);  // `to` value less than or equal to `bonus_end_block`
        let from_check = is_le(bonus_end_block, _from);  // `_from` value greater than or equal to `bonus_end_block`
        if (to_check == TRUE) {
            let block_diff = to - _from;
            let block_diff_with_multiplier = block_diff * BONUS_MULTIPLIER;
            return (multiplier=Uint256(block_diff_with_multiplier, 0));
        } else {
            if (from_check == 1) {
                let block_diff = to - _from;
                return (multiplier=Uint256(block_diff, 0));
            } else {
                let block_diff = bonus_end_block - _from;
                let block_diff_with_multiplier = block_diff * BONUS_MULTIPLIER;
                let block_diff_in_future = to - bonus_end_block;
                let multiplier = block_diff_with_multiplier * block_diff_in_future;
                return (multiplier=Uint256(multiplier, 0));
            }
        }
    }

    func pendingChefTokenPure{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(pool: PoolInfo, user: UserInfo, multiplier: Uint256, lp_supply: Uint256, block_number: felt) -> (value: Uint256) {
        let accumalated_reward_per_share = pool.accumalated_reward_per_share;
        let last_reward_block = pool.last_reward_block;
        let check = FALSE;
        %{
            if ids.block_number < ids.last_reward_block:
                ids.check = 1
        %}
        let (lp_supply_is_zero) = uint256_eq(lp_supply, Uint256(0, 0));
        if (check == TRUE and lp_supply_is_zero == FALSE){
            let (_chef_token_per_block) = chef_token_per_block.read();
            let (multiplier) = SafeUint256.mul(multiplier, _chef_token_per_block);
            let (multiplier_times_token_per_block) = SafeUint256.mul(multiplier, pool.allocation_point);
            let (_total_allocation_point) = total_allocation_point.read();
            let (chef_token_reward, _) = SafeUint256.div_rem(multiplier_times_token_per_block, _total_allocation_point);
            let (reward_times_precision) = SafeUint256.mul(chef_token_reward, Uint256(SHARE_PRECISION_VALUE, 0));
            let (share, _) = SafeUint256.div_rem(reward_times_precision, lp_supply);
            accumalated_reward_per_share = SafeUint256.add(accumalated_reward_per_share, share);
            let (amount_times_a_r_p_s) = SafeUint256.mul(user.amount, accumalated_reward_per_share);
            let (scale_down_by_share_precision, _) = SafeUint256.div_rem(amount_times_a_r_p_s, Uint256(SHARE_PRECISION_VALUE, 0));
            let (reward_debt_removed) = SafeUint256.sub_le(scale_down_by_share_precision, user.reward_debt);
            return (value=reward_debt_removed);
        }
        let (amount_times_a_r_p_s) = SafeUint256.mul(user.amount, accumalated_reward_per_share);
        let (scale_down_by_share_precision, _) = SafeUint256.div_rem(amount_times_a_r_p_s, Uint256(SHARE_PRECISION_VALUE, 0));
        let (reward_debt_removed) = SafeUint256.sub_le(scale_down_by_share_precision, user.reward_debt);
        return (value=reward_debt_removed);
    } 
}
