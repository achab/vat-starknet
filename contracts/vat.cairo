%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (
  Uint256,
  uint256_add,
  uint256_sub,
  uint256_eq,
  uint256_le,
  uint256_check,
  uint256_mul
)
from starkware.starknet.common.syscalls import (get_caller_address, get_contract_address)

# contract Vat {

#     mapping(address => mapping (address => uint)) public can;
@storage_var
func _can(u: felt) -> (res : felt):
end

#     struct Ilk {
#         uint256 Art;   // Total Normalised Debt     [wad]
#         uint256 rate;  // Accumulated Rates         [ray]
#         uint256 spot;  // Price with Safety Margin  [ray]
#         uint256 line;  // Debt Ceiling              [rad]
#         uint256 dust;  // Urn Debt Floor            [rad]
#     }
struct Ilk:
    member Art: Uint256   # Total Normalised Debt     [wad]
    member rate: Uint256  # Accumulated Rates         [ray]
    member spot: Uint256  # Price with Safety Margin  [ray]
    member line: Uint256  # Debt Ceiling              [rad]
    member dust: Uint256  # Urn Debt Floor            [rad]
end

#     struct Urn {
#         uint256 ink;   // Locked Collateral  [wad]
#         uint256 art;   // Normalised Debt    [wad]
#     }
struct Urn:
    member ink: Uint256 # Locked Collateral  [wad]
    member art: Uint256 # Normalised Debt    [wad]
end

#     mapping (bytes32 => Ilk)                       public ilks;
@storage_var
func _ilks(i: felt) -> (ilk : Ilk):
end

#     mapping (bytes32 => mapping (address => Urn )) public urns;
@storage_var
func _urns(i: felt, u: felt) -> (urn : Urn):
end

#     mapping (bytes32 => mapping (address => uint)) public gem;  // [wad]
@storage_var
func _gem(i: felt, u: felt) -> (gem : Uint256):
end

#     mapping (address => uint256)                   public dai;  // [rad]
@storage_var
func _dai(u: felt) -> (dai : Uint256):
end

#     mapping (address => uint256)                   public sin;  // [rad]
@storage_var
func _sin(u: felt) -> (sin : Uint256):
end

#     uint256 public debt;  // Total Dai Issued    [rad]
@storage_var
func _debt() -> (debt : Uint256):
end

#     uint256 public vice;  // Total Unbacked Dai  [rad]
@storage_var
func _vice() -> (vice: Uint256):
end

#     uint256 public Line;  // Total Debt Ceiling  [rad]
@storage_var
func _Line() -> (Line: Uint256):
end

#     uint256 public live;  // Active Flag
@storage_var
func _live() -> (live: Uint256):
end

@storage_var
func _wards(user : felt) -> (res : felt):
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


#     // --- Math ---
#     function add(uint x, int y) internal pure returns (uint z) {
#         z = x + uint(y);
#         require(y >= 0 || z <= x);
#         require(y <= 0 || z >= x);
#     }
#     function sub(uint x, int y) internal pure returns (uint z) {
#         z = x - uint(y);
#         require(y <= 0 || z <= x);
#         require(y >= 0 || z >= x);
#     }
#     function mul(uint x, int y) internal pure returns (int z) {
#         z = int(x) * y;
#         require(int(x) >= 0);
#         require(y == 0 || z / y == int(x));
#     }
#     function add(uint x, uint y) internal pure returns (uint z) {
#         require((z = x + y) >= x);
#     }
#     function sub(uint x, uint y) internal pure returns (uint z) {
#         require((z = x - y) <= x);
#     }
#     function mul(uint x, uint y) internal pure returns (uint z) {
#         require(y == 0 || (z = x * y) / y == x);
#     }

#     // --- Administration ---
#     function init(bytes32 ilk) external auth {
#         require(ilks[ilk].rate == 0, "Vat/ilk-already-init");
#         ilks[ilk].rate = 10 ** 27;
#     }

#     function either(bool x, bool y) internal pure returns (bool z) {
#         assembly{ z := or(x, y)}
#     }
#     function both(bool x, bool y) internal pure returns (bool z) {
#         assembly{ z := and(x, y)}
#     }

#     // --- CDP Manipulation ---
#     function frob(bytes32 i, address u, address v, address w, int dink, int dart) external {
#         // system is live
#         require(live == 1, "Vat/not-live");

#         Urn memory urn = urns[i][u];
#         Ilk memory ilk = ilks[i];
#         // ilk has been initialised
#         require(ilk.rate != 0, "Vat/ilk-not-init");

#         urn.ink = add(urn.ink, dink);
#         urn.art = add(urn.art, dart);
#         ilk.Art = add(ilk.Art, dart);

#         int dtab = mul(ilk.rate, dart);
#         uint tab = mul(ilk.rate, urn.art);
#         debt     = add(debt, dtab);

#         // either debt has decreased, or debt ceilings are not exceeded
#         require(either(dart <= 0, both(mul(ilk.Art, ilk.rate) <= ilk.line, debt <= Line)), "Vat/ceiling-exceeded");
#         // urn is either less risky than before, or it is safe
#         require(either(both(dart <= 0, dink >= 0), tab <= mul(urn.ink, ilk.spot)), "Vat/not-safe");

#         // urn is either more safe, or the owner consents
#         require(either(both(dart <= 0, dink >= 0), wish(u, msg.sender)), "Vat/not-allowed-u");
#         // collateral src consents
#         require(either(dink <= 0, wish(v, msg.sender)), "Vat/not-allowed-v");
#         // debt dst consents
#         require(either(dart >= 0, wish(w, msg.sender)), "Vat/not-allowed-w");

#         // urn has no debt, or a non-dusty amount
#         require(either(urn.art == 0, tab >= ilk.dust), "Vat/dust");

#         gem[i][v] = sub(gem[i][v], dink);
#         dai[w]    = add(dai[w],    dtab);

#         urns[i][u] = urn;
#         ilks[i]    = ilk;
#     }

@external
func frob{}(i: felt, u: felt, v: felt, w: felt, dink: Uint256, dart: Uint256) -> ():
    alloc_locals

    # system is live
    let (live) = _live.read()
    assert live == 1

    let (local urn) = _urns.read(i, u)
    let (local ilk) = _ilks.read(i)
    # ilk has been initialised
    assert ilk.rate != 0

    urn.ink = uint256_add(urn.ink, dink)
    urn.art = uint256_add(urn.art, dart)
    ilk.Art = uint256_add(ilk.Art, dart)

    let (dtab) = uint256_mul(ilk.rate, dart)
    let (tab) = uint256_mul(ilk.rate, urn.art)
    let (debt) = _debt.read()
    debt = uint256_add(debt, dtab)
    _debt.write(debt)

    return ()
end

# }