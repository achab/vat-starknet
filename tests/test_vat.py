"""vat.cairo test file."""
import os

import pytest
from starkware.starknet.testing.starknet import Starknet

# The path to the contract source code.
CONTRACT_FILE = os.path.join("contracts", "vat.cairo")


@pytest.mark.asyncio
async def test_init_ilk():
    """Test init method."""
    # Create a new Starknet class that simulates the StarkNet
    # system.
    starknet = await Starknet.empty()

    # Deploy the contract.
    caller = 1234
    contract = await starknet.deploy(
        source=CONTRACT_FILE,
        constructor_calldata=[caller]
    )

    # # Invoke init().
    # await contract.init(i="abc").invoke()

    # # Check the result of get_balance().
    # execution_info = await contract.get_balance().call()
    # assert execution_info.result == (30,)
