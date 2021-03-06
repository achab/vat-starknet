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
    with_attr error_message("Vat/ilk-already-init"):
        assert (is_zero) = 1
    end
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
    let (is_nonneg) = uint256_le(Uint256(0, 0), y)
    if is_nonneg == 1:
        let (z : Uint256, is_overflow) = uint256_add(x, y)
        assert (is_overflow) = 0
        return (z=z)
    else:
        let (neg_y) = uint256_neg(y)
        let (z : Uint256) = uint256_sub(x, neg_y)
        return (z=z)
    end
end

func sub{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : Uint256, y : Uint256) -> (z : Uint256):
    let (z : Uint256) = uint256_sub(x, y)
    return (z=z)
end

func mul{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        x : Uint256, y : Uint256) -> (z : Uint256):
    let (is_nonneg) = uint256_le(Uint256(0, 0), y)
    if is_nonneg == 1:
        let (z : Uint256, _) = uint256_mul(x, y)
        return (z=z)
    else:
        let (neg_y) = uint256_neg(y)
        let (z : Uint256, _) = uint256_mul(x, neg_y)
        let (neg_z) = uint256_neg(z)
        return (z=neg_z)
    end
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
func file_Line{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(data : Uint256):
    alloc_locals
    auth()

    # system is live
    let (live) = _live.read()
    with_attr error_message("Vat/not-live"):
        assert live = 1
    end

    _Line.write(data)
    return ()
end

@external
func file_ilk{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        i : felt, what : felt, data : Uint256):
    alloc_locals
    auth()

    # system is live
    let (live) = _live.read()
    with_attr error_message("Vat/not-live"):
        assert live = 1
    end

    let (local ilk) = _ilks.read(i)

    # value "spot" corresponds to what == 1
    if what == 1:
        _ilks.write(i, Ilk(ilk.Art, ilk.rate, data, ilk.line, ilk.dust))
        return ()
    end
    # value "line" corresponds to what == 2
    if what == 2:
        _ilks.write(i, Ilk(ilk.Art, ilk.rate, ilk.spot, data, ilk.dust))
        return ()
    end
    # value "dust" corresponds to what == 3
    if what == 3:
        _ilks.write(i, Ilk(ilk.Art, ilk.rate, ilk.spot, ilk.line, data))
        return ()
    end

    with_attr error_message("Argument 'what' should be either 1, 2 or 3."):
        assert 1 = 0
    end

    return ()
end

@external
func frob{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        i : felt, u : felt, v : felt, w : felt, dink : Uint256, dart : Uint256):
    alloc_locals

    # system is live
    let (live) = _live.read()
    with_attr error_message("Vat/not-live"):
        assert live = 1
    end

    let (local urn) = _urns.read(i, u)
    let (local ilk) = _ilks.read(i)
    # ilk has been initialised
    let (is_not_zero) = uint256_is_not_zero(ilk.rate)
    with_attr error_message("Vat/ilk-not-init"):
        assert_not_zero(is_not_zero)
    end

    # update urn.ink and urn.art
    let (urn_ink) = add(urn.ink, dink)
    let (urn_art) = add(urn.art, dart)
    _urns.write(i, u, Urn(urn_ink, urn_art))
    let (local urn) = _urns.read(i, u)
    # update ilk.Art
    let (ilk_art) = add(ilk.Art, dart)
    _ilks.write(i, Ilk(ilk_art, ilk.rate, ilk.spot, ilk.line, ilk.dust))
    let (local ilk) = _ilks.read(i)

    let (dtab) = mul(ilk.rate, dart)
    let (tab) = mul(ilk.rate, urn.art)
    # update debt and write
    let (debt) = _debt.read()
    let (new_debt) = add(debt, dtab)
    _debt.write(new_debt)

    let (Line) = _Line.read()
    let (caller) = get_caller_address()

    # define useful variables
    let (neg_dart) = uint256_neg(dart)
    let (is_dart_negative) = uint256_le(dart, Uint256(0, 0))
    let (is_dart_positive) = uint256_le(Uint256(0, 0), dart)
    let (neg_dink) = uint256_neg(dink)
    let (is_dink_positive) = uint256_le(Uint256(0, 0), dink)
    let (is_dink_negative) = uint256_le(dink, Uint256(0, 0))

    # either debt has decreased, or debt ceilings are not exceeded
    let (is_debt_below_Line) = uint256_le(new_debt, Line)
    let (product) = mul(ilk.Art, ilk.rate)
    let (is_ilk_below_line) = uint256_le(product, ilk.line)
    let (are_ceilings_normal) = both(is_ilk_below_line, is_debt_below_Line)
    let (condition_one) = either(is_dart_negative, are_ceilings_normal)
    with_attr error_message("Vat/ceiling-exceeded"):
        assert_not_zero(condition_one)
    end

    # urn is either less risky than before, or it is safe
    let (product) = mul(urn.ink, ilk.spot)
    let (is_urn_safe) = uint256_le(tab, product)
    let (is_urn_less_risky) = both(is_dart_negative, is_dink_positive)
    let (condition_two) = either(is_urn_less_risky, is_urn_safe)
    with_attr error_message("Vat/not-safe"):
        assert_not_zero(condition_two)
    end

    # urn is either more safe, or the owner consents
    let (is_u_valid) = wish(u, caller)
    let (condition_three) = either(is_urn_less_risky, is_u_valid)
    with_attr error_message("Vat/not-allowed-u"):
        assert_not_zero(condition_three)
    end

    # collateral src consents
    let (is_v_valid) = wish(v, caller)
    let (condition_four) = either(is_dink_negative, is_v_valid)
    with_attr error_message("Vat/not-allowed-v"):
        assert_not_zero(condition_four)
    end

    # debt dst consents
    let (is_w_valid) = wish(w, caller)
    let (condition_five) = either(is_dart_positive, is_w_valid)
    with_attr error_message("Vat/not-allowed-w"):
        assert_not_zero(condition_five)
    end

    # urn has no debt, or a non-dusty amount
    let (has_urn_no_debt) = uint256_is_zero(urn.art)
    let (is_amount_non_dusty) = uint256_le(ilk.dust, tab)

    let (condition_six) = either(has_urn_no_debt, is_amount_non_dusty)
    with_attr error_message("Vat/dust"):
        assert_not_zero(condition_six)
    end

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
