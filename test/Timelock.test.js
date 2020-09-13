const { expectRevert, time } = require('@openzeppelin/test-helpers');
const ethers = require('ethers');
const CreateSoda = artifacts.require('CreateSoda');
const SodaToken = artifacts.require('SodaToken');
const SodaPool = artifacts.require('SodaPool');
const SodaMaster = artifacts.require('SodaMaster');
const MockERC20 = artifacts.require('MockERC20');
const Timelock = artifacts.require('Timelock');
const WETHVault = artifacts.require('WETHVault');

function encodeParameters(types, values) {
    const abi = new ethers.utils.AbiCoder();
    return abi.encode(types, values);
}

contract('Timelock', ([alice, bob, carol, dev, minter, incent]) => {
    beforeEach(async () => {
        this.sodaMaster = await SodaMaster.new({ from: alice });

        this.wETH = await MockERC20.new('Fake Wrapped Ethereum', 'WETH', '1000000', { from: alice });
        await this.sodaMaster.setWETH(this.wETH.address);

        this.soda = await SodaToken.new({ from: alice });
        await this.sodaMaster.setSoda(this.soda.address);

        this.pool = await SodaPool.new({ from: alice });
        await this.sodaMaster.setPool(this.pool.address);

        this.createSoda = await CreateSoda.new(this.sodaMaster.address, { from: alice });
        const K_STRATEGY_CREATE_SODA = 0;
        await this.sodaMaster.addStrategy(K_STRATEGY_CREATE_SODA, this.createSoda.address);

        this.wethVault = await WETHVault.new(this.sodaMaster.address, this.createSoda.address, { from: alice });
        const K_VAULT_WETH = 0;
        await this.sodaMaster.addVault(K_VAULT_WETH, this.wethVault.address);

        this.timelock = await Timelock.new(bob, '259200', { from: alice });

        await this.sodaMaster.transferOwnership(this.timelock.address, { from: alice });
        await this.soda.transferOwnership(this.createSoda.address, { from: alice });
        await this.pool.transferOwnership(this.timelock.address, { from: alice });
        await this.createSoda.transferOwnership(this.timelock.address, { from: alice });
        await this.wethVault.transferOwnership(this.timelock.address, { from: alice });
    });

    it('should not allow non-owner to do operation', async () => {
        await expectRevert(
            this.sodaMaster.transferOwnership(carol, { from: alice }),
            'Ownable: caller is not the owner',
        );
        await expectRevert(
            this.sodaMaster.transferOwnership(carol, { from: bob }),
            'Ownable: caller is not the owner',
        );
        await expectRevert(
            this.timelock.queueTransaction(
                this.soda.address, '0', 'transferOwnership(address)',
                encodeParameters(['address'], [carol]),
                (await time.latest()).add(time.duration.days(4)),
                { from: alice },
            ),
            'Timelock::queueTransaction: Call must come from admin.',
        );
    });

    it('should do the timelock thing', async () => {
        const eta = (await time.latest()).add(time.duration.days(4));
        await this.timelock.queueTransaction(
            this.sodaMaster.address, '0', 'transferOwnership(address)',
            encodeParameters(['address'], [carol]), eta, { from: bob },
        );
        await time.increase(time.duration.days(1));
        await expectRevert(
            this.timelock.executeTransaction(
                this.sodaMaster.address, '0', 'transferOwnership(address)',
                encodeParameters(['address'], [carol]), eta, { from: bob },
            ),
            "Timelock::executeTransaction: Transaction hasn't surpassed time lock.",
        );
        await time.increase(time.duration.days(4));
        await this.timelock.executeTransaction(
            this.sodaMaster.address, '0', 'transferOwnership(address)',
            encodeParameters(['address'], [carol]), eta, { from: bob },
        );
        assert.equal((await this.sodaMaster.owner()).valueOf(), carol);
    });

    it('should also work with SodaPool', async () => {
        const eta = (await time.latest()).add(time.duration.days(3));
        await this.timelock.queueTransaction(
            this.pool.address, '0', 'setPoolInfo(uint256,address,address,uint256)',
            encodeParameters(['uint256', 'address', 'address', 'uint256'], ['0', this.wETH.address, this.wethVault.address, '1234']), eta, { from: bob },
        );
        await time.increase(time.duration.days(3));
        await this.timelock.executeTransaction(
            this.pool.address, '0', 'setPoolInfo(uint256,address,address,uint256)',
            encodeParameters(['uint256', 'address', 'address', 'uint256'], ['0', this.wETH.address, this.wethVault.address, '1234']), eta, { from: bob },
        );
        assert.equal((await this.pool.poolMap('0')).valueOf().startTime, '1234');
    });
});
