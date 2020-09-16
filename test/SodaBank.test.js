const { expectRevert, time } = require('@openzeppelin/test-helpers');
const ethers = require('ethers');
const CreateSoda = artifacts.require('CreateSoda');
const SodaToken = artifacts.require('SodaToken');
const SodaEthereum = artifacts.require('SodaEthereum');
const SodaPool = artifacts.require('SodaPool');
const SodaBank = artifacts.require('SodaBank');
const SodaDev = artifacts.require('SodaDev');
const SodaMaster = artifacts.require('SodaMaster');
const MockERC20 = artifacts.require('MockERC20');
const Timelock = artifacts.require('Timelock');
const WETHCalculator = artifacts.require('WETHCalculator');
const WETHVault = artifacts.require('WETHVault');

function encodeParameters(types, values) {
    const abi = new ethers.utils.AbiCoder();
    return abi.encode(types, values);
}

contract('SodaBank', ([alice, bob, carol]) => {
    beforeEach(async () => {
        this.sodaMaster = await SodaMaster.new({ from: alice });

        this.wETH = await MockERC20.new('Fake Wrapped Ethereum', 'WETH', 3100000, { from: alice });
        await this.sodaMaster.setWETH(this.wETH.address);

        this.soda = await SodaToken.new({ from: alice });
        await this.sodaMaster.setSoda(this.soda.address, { from: alice });

        const K_MADE_SOETH = 0;
        this.soETH = await SodaEthereum.new({ from: alice }, { from: alice });
        await this.sodaMaster.addSodaMade(K_MADE_SOETH, this.soETH.address, { from: alice });

        this.pool = await SodaPool.new({ from: alice });
        await this.sodaMaster.setPool(this.pool.address, { from: alice });

        this.bank = await SodaBank.new(this.sodaMaster.address, { from: alice });
        await this.sodaMaster.setBank(this.bank.address, { from: alice });

        this.revenue = await SodaDev.new(this.sodaMaster.address, { from: alice });
        await this.sodaMaster.setRevenue(this.revenue.address, { from: alice });

        this.dev = await SodaDev.new(this.sodaMaster.address, { from: alice });
        await this.sodaMaster.setDev(this.dev.address, { from: alice });

        this.createSoda = await CreateSoda.new(this.sodaMaster.address, { from: alice });
        const K_STRATEGY_CREATE_SODA = 0;
        await this.sodaMaster.addStrategy(K_STRATEGY_CREATE_SODA, this.createSoda.address, { from: alice });

        this.wethVault = await WETHVault.new(this.sodaMaster.address, this.createSoda.address, { from: alice });
        const K_VAULT_WETH = 0;
        await this.sodaMaster.addVault(K_VAULT_WETH, this.wethVault.address, { from: alice });

        this.calculator = await WETHCalculator.new(this.sodaMaster.address, { from: alice });
        await this.calculator.changeRateAndLTV(500, 70, 90, { from: alice });
        const K_CALCULATOR_WETH = 0;
        await this.sodaMaster.addCalculator(K_CALCULATOR_WETH, this.calculator.address, { from: alice });

        const now = Math.floor((new Date()).getTime() / 1000);
        // Let the pool start now.
        await this.pool.setPoolInfo(0, this.wETH.address, this.wethVault.address, now, { from: alice });
        await this.createSoda.setPoolInfo(0, this.wethVault.address, this.wETH.address, 1, false, { from: alice });
        await this.bank.setPoolInfo(0, this.soETH.address, this.wethVault.address, this.calculator.address, { from: alice });

        await this.soda.transferOwnership(this.createSoda.address, { from: alice });
        await this.soETH.transferOwnership(this.bank.address, { from: alice });
    });

    it('should work', async () => {
        // alice give bob 100 for test purpose.
        await this.wETH.transfer(bob, 1100000, { from: alice });
        await this.wETH.transfer(carol, 2000000, { from: alice });
        // bob stakes 110.
        await this.wETH.approve(this.pool.address, 1100000, { from: bob });
        await this.pool.deposit(0, 1100000, { from: bob });
        // 2 block later, he should get some SODA.
        await time.advanceBlock(); // Block 0
        await this.pool.claim(0, { from: bob });  // Block 1
        var balanceOfSoda = await this.soda.balanceOf(bob);
        // 95% is for farmers, 5% goes to the dev pool.
        assert.equal(balanceOfSoda.valueOf(), Math.floor(2000 * 1e18 * 0.95));

        // Mow borrow some SoETH. The user can borrow at most 770000
        await expectRevert(
            this.bank.borrow(0, 800000, { from: bob }),  // Block 2
            'Vault: lock too much',
        );
        await this.bank.borrow(0, 600000, { from: bob }),  // Block 3
        await expectRevert(
            this.bank.borrow(0, 200000, { from: bob }),  // Block 4
            'Vault: lock too much',
        );
        await this.bank.borrow(0, 100000, { from: bob });  // Block 5

        // Now he should have 700000 soETH
        var balanceOfSoETH = await this.soETH.balanceOf(bob);
        assert.equal(balanceOfSoETH.valueOf(), 700000);

        await this.pool.claim(0, { from: bob });  // Block 6

        // He is still mining soda.
        balanceOfSoda = await this.soda.balanceOf(bob);
        // 95% is for farmers, 5% goes to the dev pool.
        assert.equal(balanceOfSoda.valueOf(), Math.floor(7000 * 1e18 * 0.95));

        // Most of his WETH is locked now.
        await expectRevert(
            this.pool.withdraw(0, 500000, { from: bob }),  // Block 7
            'Vault: burn too much'
        );

        // Withdrawing 100000 is ok.
        await this.pool.withdraw(0, 100000, { from: bob });  // Block 8
        // Now he has 100000 WETH.
        var balanceOfWETH = await this.wETH.balanceOf(bob);
        assert.equal(balanceOfWETH.valueOf(), 100000);

        // Now he can return loan of index 0.
        await this.soETH.approve(this.bank.address, 1000000, { from: bob });  // Block 9
        await this.bank.payBackInFull(0, { from: bob });

        // He paid 600000 + 600000 * 0.0005 = 600300
        // has 99700 remaining.
        balanceOfSoETH = await this.soETH.balanceOf(bob);
        assert.equal(balanceOfSoETH.valueOf(), 99700);

        // Bob can withdraw now.
        this.pool.withdraw(0, 500000, { from: bob });  // Block 10

        // Not enough soETH left, he can't pay off index 1 now.
        await expectRevert(
            this.bank.payBackInFull(1, { from: bob }),  // Block 11
            'burn amount exceeds balance'
        );

        // 2 years later. Someone else, carol can collect the debt.
        //await this.bank.collectDebt(0, { from: bob });
        await time.increase(time.duration.years(2));

        // Bob has some vault asset locked.
        var balanceOfBobVault = await this.wethVault.balanceOf(bob);
        assert.equal(balanceOfBobVault.valueOf(), 500000);
        var lockedBalanceOfBobVault = await this.wethVault.lockedAmount(bob);
        // 100000 * 100 / 70 = 142857 is locked.
        assert.equal(lockedBalanceOfBobVault.valueOf(), 142857);

        // Carol stakes 2000000, and quickly borrows 1400000
        await this.wETH.approve(this.pool.address, 2000000, { from: carol });
        await this.pool.deposit(0, 2000000, { from: carol });
        await this.bank.borrow(0, 1400000, { from: carol });
        balanceOfSoETH = await this.soETH.balanceOf(carol);
        assert.equal(balanceOfSoETH.valueOf(), 1400000);

        // Now carol can collect bob's debt, which are loanId = 0 and 1.
        await this.soETH.approve(this.bank.address, 1400000, { from: carol });
        await this.bank.collectDebt(0, 1, { from: carol });
        // The accumulated debt of loanId #1 is 100000 / 70 * 90 = 128571
        // The loaded WETH account is 100000 / 70 * 100 = 142857
        // Coral needs to pay 128571 + (142857 - 128571) / 2 = 135714
        balanceOfSoETH = await this.soETH.balanceOf(carol);
        // 1400000 - 135714 = 1264286
        assert.equal(balanceOfSoETH.valueOf(), 1264286);

        // Bob should lose his locked asset. 500000 - 142857 = 357143
        balanceOfBobVault = await this.wethVault.balanceOf(bob);
        assert.equal(balanceOfBobVault.valueOf(), 357143);
        lockedBalanceOfBobVault = await this.wethVault.lockedAmount(bob);
        assert.equal(lockedBalanceOfBobVault.valueOf(), 0);

        // Now carol has more vault assets.
        var balanceOfCarolVault = await this.wethVault.balanceOf(carol);
        assert.equal(balanceOfCarolVault.valueOf(), 2142857);
        var lockedBalanceOfCarolVault = await this.wethVault.lockedAmount(carol);
        // Carol still has 2000000 locked.
        assert.equal(lockedBalanceOfCarolVault.valueOf(), 2000000);
    });
});
