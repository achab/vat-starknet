%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_eq, uint256_le, uint256_check, uint256_mul,
    uint256_signed_nn, uint256_neg)
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address

@storage_var
func _can(u : felt, v : felt) -> (res : felt):
end

struct Ilk:
    member Art : Uint256  # Total Normalised Debt     [wad]
    member rate : Uint256  # Accumulated Rates         [ray]
    member spot : Uint256  # Price with Safety Margin  [ray]
    member line : Uint256  # Debt Ceiling              [rad]
    member dust : Uint256  # Urn Debt Floor            [rad]
end

struct Urn:
    member ink : Uint256  # Locked Collateral  [wad]
    member art : Uint256  # Normalised Debt    [wad]
end

@storage_var
func _ilks(i : felt) -> (ilk : Ilk):
end

@storage_var
func _urns(i : felt, u : felt) -> (urn : Urn):
end

@storage_var
func _gem(i : felt, u : felt) -> (gem : Uint256):
end

@storage_var
func _dai(u : felt) -> (dai : Uint256):
end

@storage_var
func _sin(u : felt) -> (sin : Uint256):
end

@storage_var
func _debt() -> (debt : Uint256):
end

@storage_var
func _vice() -> (vice : Uint256):
end

@storage_var
func _Line() -> (Line : Uint256):
end

@storage_var
func _live() -> (live : felt):
end

@storage_var
func _wards(user : felt) -> (res : felt):
end

# util functions
func eq{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(a : felt, b : felt) -> (
        res : felt):
    if a == b:
        return (res=1)
    else:
        return (res=0)
    end
end

func either{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : felt, y : felt) -> (res : felt):
    assert x * x = x
    assert y * y = y
    let (res) = eq((x - 1) * (y - 1), 0)
    return (res=res)
end

func both{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : felt, y : felt) -> (res : felt):
    assert x * x = x
    assert y * y = y
    let (res) = eq((x + y), 2)
    return (res=res)
end

func wish{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        u : felt, v : felt) -> (res : felt):
    let (can) = _can.read(u, v)
    let (e) = eq(u, v)
    let (res) = either(e, can)
    return (res=res)
end

# auth function
func auth{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (ward) = _wards.read(caller)
    assert (ward) = 1
    return ()
end

# init vault function
@external
func init{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(i : felt):
    alloc_locals
    auth()
    let (local ilk : Ilk) = _ilks.read(i)
    let (is_zero) = uint256_is_zero(ilk.rate)
    assert (is_zero) = 1
    _ilks.write(i, Ilk(ilk.Art, Uint256(10 ** 27, 0), ilk.spot, ilk.line, ilk.dust))
    return ()
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(caller : felt):
    # get_caller_address() returns '0' in the constructor
    # therefore, caller parameter is included
    _wards.write(caller, 1)
    _live.write(1)
    return ()
end

func add{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : Uint256, y : Uint256) -> (z : Uint256):
    let (z : Uint256, is_overflow) = uint256_add(x, y)
    assert (is_overflow) = 0
    return (z=z)
end

func sub{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : Uint256, y : Uint256) -> (z : Uint256):
    let (z : Uint256) = uint256_sub(x, y)
    return (z=z)
end

func mul{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : Uint256, y : Uint256) -> (z : Uint256):
    let (z : Uint256, carry : Uint256) = uint256_mul(x, y)
    assert carry = Uint256(0, 0)
    return (z=z)
end

func uint256_is_zero{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : Uint256) -> (res : felt):
    let (res) = uint256_eq(x, Uint256(0, 0))
    return (res=res)
end

func uint256_is_not_zero{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : Uint256) -> (res : felt):
    let (z) = uint256_is_zero(x=x)
    return (res=1 - z)
end

@external
func frob{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        i : felt, u : felt, v : felt, w : felt, dink : Uint256, dart : Uint256) -> ():
    alloc_locals

    # system is live
    let (live) = _live.read()
    assert live = 1

    let (local urn) = _urns.read(i, u)
    let (local ilk) = _ilks.read(i)
    # ilk has been initialised
    let (is_not_zero) = uint256_is_not_zero(ilk.rate)
    assert_not_zero(is_not_zero)

    # update urn.ink
    let (res) = add(urn.ink, dink)
    assert urn.ink = res
    # update urn.art
    let (res) = add(urn.art, dart)
    assert urn.art = res
    # update ilk.Art
    let (res) = add(ilk.Art, dart)
    assert ilk.Art = res

    let (dtab) = mul(ilk.rate, dart)
    let (tab) = mul(ilk.rate, urn.art)
    # update debt and write
    let (debt) = _debt.read()
    let (res) = add(debt, dtab)
    _debt.write(res)

    let (Line) = _Line.read()
    let (caller) = get_caller_address()

    # define useful variables
    let (neg_dart) = uint256_neg(dart)
    let (is_dart_negative) = uint256_signed_nn(neg_dart)
    let (neg_dink) = uint256_neg(dink)
    let (is_dink_positive) = uint256_signed_nn(dink)
    let (is_dink_negative) = uint256_signed_nn(neg_dink)

    # either debt has decreased, or debt ceilings are not exceeded
    let (is_debt_below_Line) = uint256_le(debt, Line)
    let (product) = mul(ilk.Art, ilk.rate)
    let (is_ilk_below_line) = uint256_le(product, ilk.line)
    let (are_ceilings_normal) = both(is_ilk_below_line, is_debt_below_Line)
    let (condition_one) = either(is_dart_negative, are_ceilings_normal)
    assert_not_zero(condition_one)

    # urn is either less risky than before, or it is safe
    let (product) = mul(urn.ink, ilk.spot)
    let (is_urn_safe) = uint256_le(tab, product)
    let (is_urn_less_risky) = both(is_dart_negative, is_dink_positive)
    let (condition_two) = either(is_urn_less_risky, is_urn_safe)
    assert_not_zero(condition_two)

    # urn is either more safe, or the owner consents
    let (is_urn_safer) = both(is_dart_negative, is_dink_positive)
    let (is_u_valid) = wish(u, caller)
    let (condition_three) = either(is_urn_safer, is_u_valid)
    assert_not_zero(condition_three)

    # collateral src consents
    let (is_v_valid) = wish(v, caller)
    let (condition_four) = either(is_dink_negative, is_v_valid)
    assert_not_zero(condition_four)

    # debt dst consents
    let (is_w_valid) = wish(w, caller)
    let (condition_five) = either(is_dink_positive, is_w_valid)
    assert_not_zero(condition_five)

    # urn has no debt, or a non-dusty amount
    let (has_urn_no_debt) = uint256_is_zero(urn.art)
    let (is_amount_non_dusty) = uint256_le(ilk.dust, tab)
    let (condition_six) = either(has_urn_no_debt, is_amount_non_dusty)
    assert_not_zero(condition_six)

    let (local gem) = _gem.read(i, v)
    let (res) = sub(gem, dink)
    _gem.write(i, v, res)
    let (local dai) = _dai.read(w)
    let (res) = add(dai, dtab)
    _dai.write(w, res)

    _urns.write(i, u, urn)
    _ilks.write(i, ilk)

    return ()
end
