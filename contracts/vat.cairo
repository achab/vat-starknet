%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.uint256 import (
  Uint256,
  uint256_add,
  uint256_sub,
  uint256_eq,
  uint256_le,
  uint256_check,
  uint256_mul,
  uint256_signed_nn
)
from starkware.starknet.common.syscalls import (get_caller_address, get_contract_address)


@storage_var
func _can(u: felt, v : felt) -> (res : felt):
end

struct Ilk:
    member Art: Uint256   # Total Normalised Debt     [wad]
    member rate: Uint256  # Accumulated Rates         [ray]
    member spot: Uint256  # Price with Safety Margin  [ray]
    member line: Uint256  # Debt Ceiling              [rad]
    member dust: Uint256  # Urn Debt Floor            [rad]
end

struct Urn:
    member ink: Uint256 # Locked Collateral  [wad]
    member art: Uint256 # Normalised Debt    [wad]
end

@storage_var
func _ilks(i: felt) -> (ilk : Ilk):
end

@storage_var
func _urns(i: felt, u: felt) -> (urn : Urn):
end

@storage_var
func _gem(i: felt, u: felt) -> (gem : Uint256):
end

@storage_var
func _dai(u: felt) -> (dai : Uint256):
end

@storage_var
func _sin(u: felt) -> (sin : Uint256):
end

@storage_var
func _debt() -> (debt : Uint256):
end

@storage_var
func _vice() -> (vice: Uint256):
end

@storage_var
func _Line() -> (Line: Uint256):
end

@storage_var
func _live() -> (live: felt):
end

@storage_var
func _wards(user : felt) -> (res : felt):
end

# util functions
func either{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }(x : felt, y : felt):
    assert (x - 1) * (y - 1)) = 0
    return ()
end

func both{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }(x : felt, y : felt):
    assert (x + y) = 2
    return ()
end

func eq{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}(a : felt, b : felt) -> (res : felt):
    if a == b:
        return (res=1)
    else:
        return (res=0)
    end
end

func wish{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}(u : felt, v : felt) -> (res : felt):
    let (can) = _can.read(u, v)
    return (res=either(eq(u, v), can))
end

# auth function
func auth{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }():
    let (caller) = get_caller_address()
    let (ward) = _wards.read(caller)
    assert ward = 1
    return ()
end

# init vault function
@external
func init{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }(user : felt):
    auth()
    _wards.write(user, 1)
    return ()
end

@constructor
func constructor{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }(
    caller : felt
  ):
    # get_caller_address() returns '0' in the constructor
    # therefore, caller parameter is included
    _wards.write(caller, 1)
    _live.write(1)
    return ()
end

func add{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }(x : Uint256, y : Uint256) -> (z : Uint256):
  let (z : Uint256, is_overflow) = uint256_add(x, y)
  assert (is_overflow) = 0
  return (z=z)
end

func sub{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }(x : Uint256, y : Uint256) -> (z : Uint256):
  let (z : Uint256, is_overflow) = uint256_sub(x, y)
  assert (is_overflow) = 0
  return (z=z)
end

func mul{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
  }(x : Uint256, y : Uint256) -> (z : Uint256):
  let (z : Uint256, is_overflow) = uint256_mul(x, y)
  assert (is_overflow) = 0
  return (z=z)
end

func equals_zero{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
    }(x : felt) -> (res : felt):
    return (res=both(uint256_signed_nn(x), uint256_signed_nn(uint256_neg(x))))
end


@external
func frob{}(i: felt, u: felt, v: felt, w: felt, dink: Uint256, dart: Uint256) -> ():
    alloc_locals

    # system is live
    let (live) = _live.read()
    assert live = 1

    let (local urn) = _urns.read(i, u)
    let (local ilk) = _ilks.read(i)
    # ilk has been initialised
    assert_not_zero(ilk.rate)

    urn.ink = add(urn.ink, dink)
    urn.art = add(urn.art, dart)
    ilk.Art = add(ilk.Art, dart)

    let (dtab) = mul(ilk.rate, dart)
    let (tab) = mul(ilk.rate, urn.art)
    let (debt) = _debt.read()
    debt = add(debt, dtab)
    _debt.write(debt)

    let (Line) = _Line.read()
    let (caller) = get_caller_address()

    # either debt has decreased, or debt ceilings are not exceeded
    either(uint256_signed_nn(uint256_neg(dart)), both(uint256_le(mul(ilk.Art, ilk.rate), ilk.line), uint256_le(debt, Line)))

    # urn is either less risky than before, or it is safe
    either(both(uint256_signed_nn(uint256_neg(dart)), uint256_signed_nn(dink)), uint256_le(tab, mul(urn.ink, ilk.spot)))

    # urn is either more safe, or the owner consents
    either(both(uint256_signed_nn(uint256_neg(dart)), uint256_signed_nn(dink)), wish(u, caller))

    # collateral src consents
    either(uint256_signed_nn(uint256_neg(dink)), wish(v, caller))

    # debt dst consents
    either(uint256_signed_nn(dart), wish(w, caller))

    # urn has no debt, or a non-dusty amount
    either(equals_zero(urn.art), uint256_le(ilk.dust, tab))
    
    let (local gem) = _gem.read(i, v)
    _gem.write(i, v, sub(gem, dink))
    let (local dai) = _dai.read(w)
    _dai.write(w, add(dai, dtab))

    _urns.write(i, u, urn)
    _ilks.write(i, ilk)

    return ()
end
