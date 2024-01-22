const RegexValidator = artifacts.require("TwelveDigitsValidator");
const { expect, assert } = require('chai');


let regexValidator;

contract("TwelveDigitsValidator", function (accounts) {

  before(async () => {
    regexValidator = await RegexValidator.new();
  });

  describe("Matches", async () => {
    it("should not match less than 12 digits", async () => {
      assert.equal(await regexValidator.matches('012345678'), false);
    });

    it("should not match more than 12 digits", async () => {
        assert.equal(await regexValidator.matches('0123456789123456'), false);
    });

    it("should not match alpha-numeric characters", async () => {
        assert.equal(await regexValidator.matches('01234567891a'), false);
    });

    it("should match exactly 12 digits", async () => {
        assert.equal(await regexValidator.matches('012345678912'), true);
    });
  });
});
