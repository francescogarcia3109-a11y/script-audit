return function()
	local Inventory = require(script.Parent.Parent.Inventory)

	describe("Inventory", function()
		it("starts empty", function()
			local inv = Inventory.new()
			expect(inv:count()).to.equal(0)
		end)

		it("rejects bad slots", function()
			local inv = Inventory.new()
			expect(function()
				inv:get(-1)
			end).to.throw()
		end)
	end)
end
