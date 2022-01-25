"""vat.cairo test file."""
import os

import pytest
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException

# The path to the contract source code.

CONTRACT_FILE = os.path.join("contracts", "vat.cairo")


# Util functions

def to_split_uint(a: int) -> tuple:
    return (a & ((1 << 128) - 1), a >> 128)

def to_uint(a: tuple) -> int:
    return a[0] + (a[1] << 128)

async def assert_revert(expression, expected_err_msg=None):
    try:
        await expression
        assert False
    except StarkException as err:
        if expected_err_msg:
            assert expected_err_msg in err.message, "Could not find error message:\nexpected: {}\nactual: {}\n".format(expected_err_msg, err.message)
        _, error = err.args
        assert error['code'] == StarknetErrorCode.TRANSACTION_FAILED


# Contract-related constants

ILK = 5678
CALLER = 1234
USER_U = 1001
USER_V = 1002
USER_W = 1003
DINK = to_split_uint(10)
NEG_DINK = to_split_uint(-10)
DART = to_split_uint(1)
NEG_DART = to_split_uint(-1)
ZERO = to_split_uint(0)
SPOT = to_split_uint(10 ** 30)
LINE = to_split_uint(10 ** 30)
DUST = to_split_uint(2 ** 255 - 1)


# Fixtures

@pytest.fixture
async def starknet() -> Starknet:
    return await Starknet.empty()

@pytest.fixture
async def contract(starknet: Starknet) -> StarknetContract:
    return await starknet.deploy(
        source=CONTRACT_FILE,
        constructor_calldata=[CALLER]
    )

# Tests

@pytest.mark.asyncio
async def test_init(contract: StarknetContract):
    # Invoke init function.
    await contract.init(i=ILK).invoke(caller_address=CALLER)
    
    # Check that an exception is thrown when one wants to init the same vault twice.
    await assert_revert(contract.init(i=ILK).invoke(caller_address=CALLER), "Vat/ilk-already-init")


@pytest.mark.asyncio
async def test_frob_condition_one(contract: StarknetContract):
    # Invoke init function.
    await contract.init(i=ILK).invoke(caller_address=CALLER)

    # Exception because condition 1 is not matched.
    await assert_revert(contract.frob(i=ILK, u=USER_U, v=USER_V, w=USER_W, dink=DINK, dart=DART).invoke(caller_address=CALLER), "Vat/ceiling-exceeded")


@pytest.mark.asyncio
async def test_frob_condition_two(contract: StarknetContract):
    # Invoke init function.
    await contract.init(i=ILK).invoke(caller_address=CALLER)

    # Edit ilk.spot
    await contract.file_ilk(i=ILK, what=1, data=SPOT).invoke(caller_address=CALLER)

    # Edit ilk.line
    await contract.file_ilk(i=ILK, what=2, data=LINE).invoke(caller_address=CALLER)

    # Edit Line
    await contract.file_Line(data=LINE).invoke(caller_address=CALLER)

    # Exception because condition 2 is not matched.
    await assert_revert(contract.frob(i=ILK, u=USER_U, v=USER_V, w=USER_W, dink=ZERO, dart=DART).invoke(caller_address=CALLER), "Vat/not-safe")


@pytest.mark.asyncio
async def test_frob_condition_three(contract: StarknetContract):
    # Invoke init function.
    await contract.init(i=ILK).invoke(caller_address=CALLER)

    # Edit ilk.spot
    await contract.file_ilk(i=ILK, what=1, data=SPOT).invoke(caller_address=CALLER)

    # Exception because condition 3 is not matched.
    await assert_revert(contract.frob(i=ILK, u=USER_U, v=USER_V, w=USER_W, dink=NEG_DINK, dart=ZERO).invoke(caller_address=CALLER), "Vat/not-allowed-u")


@pytest.mark.asyncio
async def test_frob_condition_four(contract: StarknetContract):
    # Invoke init function.
    await contract.init(i=ILK).invoke(caller_address=CALLER)

    # Exception because condition 4 is not matched.
    await assert_revert(contract.frob(i=ILK, u=USER_U, v=USER_V, w=USER_W, dink=DINK, dart=ZERO).invoke(caller_address=CALLER), "Vat/not-allowed-v")


@pytest.mark.asyncio
async def test_frob_condition_five(contract: StarknetContract):
    # Invoke init function.
    await contract.init(i=ILK).invoke(caller_address=CALLER)

    # Exception because condition 5 is not matched.
    await assert_revert(contract.frob(i=ILK, u=CALLER, v=CALLER, w=USER_W, dink=DINK, dart=NEG_DART).invoke(caller_address=CALLER), "Vat/not-allowed-w")


# @pytest.mark.asyncio
# async def test_frob_condition_six(contract: StarknetContract):
#     # Invoke init function.
#     await contract.init(i=ILK).invoke(caller_address=CALLER)

#     # Edit ilk.dust
#     await contract.file_ilk(i=ILK, what=3, data=DUST).invoke(caller_address=CALLER)

#     # Exception because condition 6 is not matched.
#     await assert_revert(contract.frob(i=ILK, u=CALLER, v=CALLER, w=CALLER, dink=DINK, dart=NEG_DART).invoke(caller_address=CALLER), "Vat/dust")


@pytest.mark.asyncio
async def test_frob(contract: StarknetContract):
    # Invoke init function.
    await contract.init(i=ILK).invoke(caller_address=CALLER)

    # Call frob function.
    await contract.frob(i=ILK, u=CALLER, v=CALLER, w=CALLER, dink=DINK, dart=NEG_DART).invoke(caller_address=CALLER)
