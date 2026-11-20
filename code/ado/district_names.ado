*! district_names 1.0 -- GADM 4.1 district name (NAME_1) from the IHPS
*  district code in variable -district- (cities merged into their district)
program define district_names
	version 18
	capture drop NAME_1
	gen str20 NAME_1 = ""
	local codes "101 Chitipa 102 Karonga 103 Nkhata_Bay 104 Rumphi 105 Mzimba 106 Likoma 107 Mzimba 201 Kasungu 202 Nkhotakota 203 Ntchisi 204 Dowa 205 Salima 206 Lilongwe 207 Mchinji 208 Dedza 209 Ntcheu 210 Lilongwe 301 Mangochi 302 Machinga 303 Zomba 304 Chiradzulu 305 Blantyre 306 Mwanza 307 Thyolo 308 Mulanje 309 Phalombe 310 Chikwawa 311 Nsanje 312 Balaka 313 Neno 314 Zomba 315 Blantyre"
	local n : word count `codes'
	forvalues i = 1(2)`n' {
		local c : word `i' of `codes'
		local nm : word `=`i'+1' of `codes'
		quietly replace NAME_1 = subinstr("`nm'", "_", " ", .) if district == `c'
	}
end
