*! kgunit 1.0  -- kg per reported unit for packaged agricultural inputs
*  usage:  kgunit <unitvar> <newvar>, type(fert|seed)
*  fert: units of the fertiliser / coupon / purchase questions
*        (1 g, 2 kg, 3 2kg bag, 4 3kg bag, 5 5kg bag, 6 10kg bag, 7 50kg bag,
*         8 litre, 9 ml, 10 bucket, 11 wheelbarrow, 12 ox-cart)
*  seed: units of the seed questions
*        (1 g, 2 kg, 3 2kg bag, 4 3kg bag, 5 3.7kg bag, 6 5kg bag,
*         7 10kg bag, 8 50kg bag)
*  Bucket = 20 l x 0.5375 kg/l, wheelbarrow = 80 kg, ox-cart = 800 kg
*  (EPAR Malawi conversion conventions).
program define kgunit
	version 18
	syntax varlist(min=1 max=1) , GENerate(name) Type(string)
	local u `varlist'
	quietly {
		gen double `generate' = .
		if "`type'" == "fert" {
			replace `generate' = 0.001 if `u' == 1
			replace `generate' = 1     if `u' == 2
			replace `generate' = 2     if `u' == 3
			replace `generate' = 3     if `u' == 4
			replace `generate' = 5     if `u' == 5
			replace `generate' = 10    if `u' == 6
			replace `generate' = 50    if `u' == 7
			replace `generate' = 1     if `u' == 8
			replace `generate' = 0.001 if `u' == 9
			replace `generate' = 10.75 if `u' == 10
			replace `generate' = 80    if `u' == 11
			replace `generate' = 800   if `u' == 12
		}
		else if "`type'" == "seed" {
			replace `generate' = 0.001 if `u' == 1
			replace `generate' = 1     if `u' == 2
			replace `generate' = 2     if `u' == 3
			replace `generate' = 3     if `u' == 4
			replace `generate' = 3.7   if `u' == 5
			replace `generate' = 5     if `u' == 6
			replace `generate' = 10    if `u' == 7
			replace `generate' = 50    if `u' == 8
		}
		else {
			noisily di as error "kgunit: type() must be fert or seed"
			exit 198
		}
	}
end
