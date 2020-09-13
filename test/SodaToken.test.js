const { expectRevert } = require('@openzeppelin/test-helpers');
const SodaToken = artifacts.require('SodaToken');

contract('SodaToken', ([createSoda, bob, carol]) => {
    beforeEach(async () => {
        this.soda = await SodaToken.new({ from: createSoda });
    });

    it('should have correct name and symbol and decimal', async () => {
        const name = await this.soda.name();
        const symbol = await this.soda.symbol();
        const decimals = await this.soda.decimals();
        assert.equal(name.valueOf(), 'SodaToken');
        assert.equal(symbol.valueOf(), 'SODA');
        assert.equal(decimals.valueOf(), '18');
    });

    it('should only allow owner to mint token', async () => {
        await this.soda.mint(createSoda, '100', { from: createSoda });
        await this.soda.mint(bob, '1000', { from: createSoda });
        await expectRevert(
            this.soda.mint(carol, '1000', { from: bob }),
            'Ownable: caller is not the owner',
        );
        const totalSupply = await this.soda.totalSupply();
        const createSodaBal = await this.soda.balanceOf(createSoda);
        const bobBal = await this.soda.balanceOf(bob);
        const carolBal = await this.soda.balanceOf(carol);
        assert.equal(totalSupply.valueOf(), '1100');
        assert.equal(createSodaBal.valueOf(), '100');
        assert.equal(bobBal.valueOf(), '1000');
        assert.equal(carolBal.valueOf(), '0');
    });

    it('should supply token transfers properly', async () => {
        await this.soda.mint(createSoda, '100', { from: createSoda });
        await this.soda.mint(bob, '1000', { from: createSoda });
        await this.soda.transfer(carol, '10', { from: createSoda });
        await this.soda.transfer(carol, '100', { from: bob });
        const totalSupply = await this.soda.totalSupply();
        const createSodaBal = await this.soda.balanceOf(createSoda);
        const bobBal = await this.soda.balanceOf(bob);
        const carolBal = await this.soda.balanceOf(carol);
        assert.equal(totalSupply.valueOf(), '1100');
        assert.equal(createSodaBal.valueOf(), '90');
        assert.equal(bobBal.valueOf(), '900');
        assert.equal(carolBal.valueOf(), '110');
    });

    it('should fail if you try to do bad transfers', async () => {
        await this.soda.mint(createSoda, '100', { from: createSoda });
        await expectRevert(
            this.soda.transfer(carol, '110', { from: createSoda }),
            'ERC20: transfer amount exceeds balance',
        );
        await expectRevert(
            this.soda.transfer(carol, '1', { from: bob }),
            'ERC20: transfer amount exceeds balance',
        );
    });
  });
