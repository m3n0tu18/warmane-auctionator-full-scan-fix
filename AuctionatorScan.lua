-- v1.0 - Initial Release
local addonName, addonTable = ...; 
local zc = addonTable.zc;

KM_NULL_STATE	= 0;
KM_PREQUERY		= 1;
KM_INQUERY		= 2;
KM_POSTQUERY	= 3;
KM_ANALYZING	= 4;
KM_SETTINGSORT	= 5;

local AUCTION_CLASS_WEAPON = 1;
local AUCTION_CLASS_ARMOR  = 2;

local gAllScans = {};

local BIGNUM = 999999999999;

local ATR_SORTBY_NAME_ASC = 0;
local ATR_SORTBY_NAME_DES = 1;
local ATR_SORTBY_PRICE_ASC = 2;
local ATR_SORTBY_PRICE_DES = 3;

-----------------------------------------

AtrScan = {};
AtrScan.__index = AtrScan;

-----------------------------------------

AtrSearch = {};
AtrSearch.__index = AtrSearch;

-----------------------------------------

function Atr_NewSearch (itemName, exact, rescanThreshold, callback)

	local srch = {};
	setmetatable (srch, AtrSearch);
	srch:Init (itemName, exact, rescanThreshold, callback);

	return srch;
end

-----------------------------------------

function AtrSearch:Init (searchText, exact, rescanThreshold, callback)

	if (searchText == nil) then
		searchText = "";
	end

	self.origSearchText = searchText;
	
	if (not exact) then
		if (zc.StringStartsWith (searchText, "\"") and zc.StringEndsWith (searchText, "\"")) then
			searchText = string.sub (searchText, 2, searchText:len()-1);
			exact = true;
		end
	end		

	self.searchText			= searchText;
	self.exact				= exact;
	self.processing_state	= KM_NULL_STATE
	self.current_page		= -1
	self.items				= {};
	self.query				= Atr_NewQuery();
	self.sortedScans		= nil;
	self.sortHow			= ATR_SORTBY_PRICE_ASC;
	self.callback			= callback;
	
	if (exact) then	

		if (rescanThreshold and rescanThreshold > 0) then
			local scan = Atr_FindScan (searchText);
			if (scan and (time() - scan.whenScanned) <= rescanThreshold) then
				self.items[searchText] = scan;
			end
		end
		
		if (not self.items[searchText]) then		
			self.items[searchText] = Atr_FindScanAndInit (searchText);
		end
		
	end
	
end

-----------------------------------------

function Atr_FindScanAndInit (itemName)

	return Atr_FindScan (itemName, true);
end

-----------------------------------------

function Atr_FindScan (itemName, init)

	if (itemName == nil or itemName == "") then
		itemName = "nil";
	end

	local itemNameLC = string.lower (itemName);

	if (gAllScans[itemNameLC] == nil) then

		local scn = {};
		setmetatable (scn, AtrScan);
		scn:Init (itemName);

		gAllScans[itemNameLC] = scn;
	elseif (init) then
		gAllScans[itemNameLC]:Init (itemName);
	end
	
	return gAllScans[itemNameLC];
end

-----------------------------------------

function Atr_ClearScanCache ()

--	zc.msg_red ("Clearing Scan Cache");

	for a,v in pairs (gAllScans) do
		if (a ~= "nil") then
			gAllScans[a] = nil;
		end
	end

end

-----------------------------------------

function AtrScan:Init (itemName)
	self.itemName			= itemName;
	self.itemLink			= nil;
	self.texture            = nil;
	self.scanData			= {};
	self.sortedData			= {};
	self.whenScanned		= 0;
	self.lowprices			= {BIGNUM, BIGNUM, BIGNUM};
	self.absoluteBest		= nil;
	self.itemClass			= 0;
	self.itemSubclass		= 0;
	self.yourBestPrice		= nil;
	self.yourWorstPrice		= nil;
	self.numYourSingletons	= 0;
	self.itemTextColor 		= { 1.0, 1.0, 1.0 };
	self.searchText			= nil;
	
	self:UpdateItemLink (Atr_GetItemLink (itemName));
end

-----------------------------------------

function AtrScan:UpdateItemLink (itemLink)

	self.itemLink = itemLink;
	
	if (itemLink) then
	
		Atr_AddToItemLinkCache (self.itemName, itemLink);

		local _, _, quality, _, _, sType, sSubType = GetItemInfo(itemLink);

		self.itemQuality	= quality;
		self.itemClass		= Atr_ItemType2AuctionClass (sType);
		self.itemSubclass	= Atr_SubType2AuctionSubclass (self.itemClass, sSubType);	

		self.itemTextColor = { 1.0, 1.0, 1.0 };

		if (quality == 0)	then	self.itemTextColor = { 0.6, 0.6, 0.6 };	end
		if (quality == 2)	then	self.itemTextColor = { 0.2, 1.0, 0.0 };	end
		if (quality == 3)	then	self.itemTextColor = { 0.0, 0.5, 1.0 };	end
		if (quality == 4)	then	self.itemTextColor = { 0.7, 0.3, 1.0 };	end
	end

end


-----------------------------------------

function AtrSearch:NumScans()

	if (self.sortedScans) then
		return #self.sortedScans;
	end

	local count = 0;
	for name,scn in pairs (self.items) do
		count = count + 1;
	end

	return count;
end

-----------------------------------------

function AtrSearch:NumSortedScans()

	if (self.sortedScans) then
		return #self.sortedScans;
	end

	return 0;
end

-----------------------------------------

function AtrSearch:GetFirstScan()

	if (self.sortedScans) then
		return self.sortedScans[1];
	end

	for name,scn in pairs (self.items) do
		return scn;
	end
	
	return nil;

end


-----------------------------------------

function AtrSearch:Start ()

	if (self.searchText == "") then
		return;
	end
	
	if (Atr_IsCompoundSearch (self.searchText)) then
			
		local _, itemClass = Atr_ParseCompoundSearch (self.searchText);
	
		if (itemClass == 0) then
			Atr_Error_Display (ZT("The first part of this compound\n\nsearch is not a valid category."));
			return;
		end

		self.sortHow = ATR_SORTBY_PRICE_DES;

	end
	
	self.processing_state = KM_SETTINGSORT;
	
	SortAuctionClearSort ("list");

	BrowseName:SetText (self.searchText);		-- not necessary but nice when user switches to Browse tab

	self.current_page		= 0;
	self.processing_state	= KM_PREQUERY;

	self:Continue();
	
end

-----------------------------------------

function AtrSearch:Abort ()

	if (self.processing_state == KM_NULL_STATE) then
		return;
	end

	self.processing_state = KM_NULL_STATE;
	self:Init();
end

-----------------------------------------

function AtrSearch:CheckForDuplicatePage ()

	local isDup = self.query:CheckForDuplicatePage(self.current_page);

	if (isDup) then
--		zc.msg_red ("DUPLICATE PAGE FOUND: ", "  current_page: ", self.current_page, "  numDupPages: ", self.query.numDupPages);

		self.current_page	= self.current_page - 1;   -- requery the page
		
		self.processing_state = KM_PREQUERY;
	end
		
	return isDup;
end


-----------------------------------------

function AtrSearch:AnalyzeResultsPage()

	self.processing_state = KM_ANALYZING;

	if (self.query.numDupPages > 10) then 	 -- hopefully this will never happen but need check to avoid looping
		return true;						 -- done
	end


	local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");

	if (self.current_page == 1 and totalAuctions > 3000) then -- give Blizz servers a break
		Atr_Error_Display (ZT("Too many results\n\nPlease narrow your search"));
		return true;  -- done
	end

	if (totalAuctions >= 50) then
		Atr_SetMessage (string.format (ZT("Scanning auctions: page %d"), self.current_page));
	end

	-- analyze

	local numNilOwners = 0;

	if (numBatchAuctions > 0) then

		local x;

		for x = 1, numBatchAuctions do

			local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner = GetAuctionItemInfo("list", x);

			if (owner == nil) then
				numNilOwners = numNilOwners + 1;
			end
			
			local exactMatch = zc.StringSame (name, self.searchText);

			if (exactMatch or not self.exact) then

				if (self.items[name] == nil) then
					self.items[name] = Atr_FindScanAndInit (name);
                    self.items[name].texture = texture
				end
                if self.items[name].texture and texture ~= self.items[name].texture then
                    name = name .. " "
                    if (self.items[name] == nil) then
                        self.items[name] = Atr_FindScanAndInit (name);
                        self.items[name].texture = texture
                    end
                end
                
				local curpage = (tonumber(self.current_page)-1);

				local scn = self.items[name];

				scn:AddScanItem (name, count, buyoutPrice, owner, 1, curpage);
				
				if (scn.itemLink == nil or self.itemClass == nil) then
					scn:UpdateItemLink (GetAuctionItemLink("list", x));
				end

				if (self.callback) then
					self.callback (x, numBatchAuctions, count, buyoutPrice, owner);
				end
				
			end
		end
	end
	
	local done = (numBatchAuctions < 50);

	if (not done) then
		self.processing_state = KM_PREQUERY;
	end
	
	return done;
end

-----------------------------------------

function AtrScan:AddScanItem (name, stackSize, buyoutPrice, owner, numAuctions, curpage)

	local sd = {};
	local i;

	if (numAuctions == nil) then
		numAuctions = 1;
	end

	for i = 1, numAuctions do
		sd["stackSize"]		= stackSize;
		sd["buyoutPrice"]	= buyoutPrice;
		sd["owner"]			= owner;
		sd["pagenum"]		= curpage;

		tinsert (self.scanData, sd);
		
		if (buyoutPrice) then
			local itemPrice = math.floor (buyoutPrice / stackSize);

			Atr_AddToLowPrices (self.lowprices, itemPrice);
		end
	end

end


-----------------------------------------

function AtrScan:AddSDXToScan (price, owner, volume)	-- helper function for AddExternalDataToScan

	local sd = {};

	if (price and price > 0) then
		sd["stackSize"]		= 1;
		sd["buyoutPrice"]	= price;
		sd["owner"]			= owner;

		if (volume) then
			sd["volume"] = volume;
		end

		tinsert (self.scanData, sd);
	end
	
end

-----------------------------------------

function AtrScan:AddExternalDataToScan ()

	if (self.itemLink == nil) then
		return;
	end

	-- Wowecon

	if (Wowecon and Wowecon.API) then
	
		local priceG, volG = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.GLOBAL_PRICE)
		local priceS, volS = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.SERVER_PRICE)

		self:AddSDXToScan (priceG, "__wowEconG", volG);
		self:AddSDXToScan (priceS, "__wowEconS", volS);
		
	end
	
	-- GoingPrice Wowhead
	
	local id = zc.ItemIDfromLink (self.itemLink);
	
	id = tonumber(id);

	if (GoingPrice_Wowhead_Data and GoingPrice_Wowhead_Data[id] and GoingPrice_Wowhead_SV._index) then
		local index = GoingPrice_Wowhead_SV._index["Buyout price"];

		if (index ~= nil) then
			local price = GoingPrice_Wowhead_Data[id][index];
		
			self:AddSDXToScan (price, "__wowHead");
		end
	end

	-- GoingPrice Allakhazam
	
	if (GoingPrice_Allakhazam_Data and GoingPrice_Allakhazam_Data[id] and GoingPrice_Allakhazam_SV._index) then
		local index = GoingPrice_Allakhazam_SV._index["Median"];

		if (index ~= nil) then
			local price = GoingPrice_Allakhazam_Data[id][index];
		
			self:AddSDXToScan (price, "__allakhazam");
		end
	end

	-- most recent historical price
	
	local price = Atr_Process_Historydata();
	if (price ~= nil) then
		self:AddSDXToScan (price, "__atrLast");
	end

end

-----------------------------------------

function AtrScan:SubtractScanItem (name, stackSize, buyoutPrice)

	local sd;
	local i;

	for i,sd in ipairs (self.scanData) do
		
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice) then
			
			tremove (self.scanData, i);
			return;
		end
	end

end

-----------------------------------------

function Atr_IsCompoundSearch (searchString)
	
	return zc.StringContains (searchString, ">") or zc.StringContains (searchString, "/");
end

-----------------------------------------

function Atr_ParseCompoundSearch (searchString)

	local delim = "/";

	if (zc.StringContains (searchString, ">")) then
		delim = ">";
	end

	local tbl	= { strsplit (delim, searchString) };
	
	local queryString	= "";
	local itemClass		= 0;
	local itemSubclass	= 0;
	local minLevel		= nil;
	local maxLevel		= nil;
	local prevWasItemClass;
	local n;
	
	for n = 1,#tbl do
		local s = tbl[n];

		local handled = false;

		if (not handled and tonumber(s)) then
			if (minLevel == nil) then
				minLevel = tonumber(s);
			elseif (maxLevel == nil) then
				maxLevel = tonumber(s);
			end
			
			handled = true;
			prevWasItemClass = false;
		end
		
		if (not handled and prevWasItemClass and itemSubclass == 0) then
			itemSubclass = Atr_SubType2AuctionSubclass (itemClass, s);
			if (itemSubclass > 0) then
				handled = true;
				prevWasItemClass = false;
			end
		end
		
		if (not handled and itemClass == 0) then

			itemClass = Atr_ItemType2AuctionClass (s);

			if (itemClass > 0) then
				prevWasItemClass = true;
				handled = true;
			end
		end
		
		if (not handled) then
			queryString = s;
			handled = true;
		end
	end	

	return queryString, itemClass, itemSubclass, minLevel, maxLevel;
end

-----------------------------------------

function AtrSearch:Continue()

	if (CanSendAuctionQuery()) then

		self.processing_state = KM_IN_QUERY;

		local queryString = self.searchText;

--	zc.md (queryString.."  page:"..self.current_page);
		
		local itemClass		= 0;
		local itemSubclass	= 0;
		local minLevel		= nil;
		local maxLevel		= nil;
		
		if (self.exact) then
			local scn = self:GetFirstScan();
			itemClass		= scn.itemClass;
			itemSubclass	= scn.itemSubclass;
		end

		if (Atr_IsCompoundSearch(queryString)) then
		
			queryString, itemClass, itemSubclass, minLevel, maxLevel = Atr_ParseCompoundSearch (queryString);
		
		end

		queryString = zc.UTF8_Truncate (queryString,63);	-- attempting to reduce number of disconnects

		QueryAuctionItems (queryString, minLevel, maxLevel, nil, itemClass, itemSubclass, self.current_page, nil, nil);

		self.query_sent_when	= gAtr_ptime;
		self.processing_state	= KM_POSTQUERY;
		self.current_page		= self.current_page + 1;
	end

end

-----------------------------------------

local gSortScansBy;

-----------------------------------------

local function Atr_SortScans (x, y)

	if (gSortScansBy == ATR_SORTBY_NAME_ASC) then		return string.lower (x.itemName) < string.lower (y.itemName);	end
	if (gSortScansBy == ATR_SORTBY_NAME_DES) then		return string.lower (x.itemName) > string.lower (y.itemName);	end

	local xprice = 0;
	local yprice = 0;
	
	if (x.absoluteBest) then	xprice = zc.round(x.absoluteBest.buyoutPrice/x.absoluteBest.stackSize);		end;
	if (y.absoluteBest) then	yprice = zc.round(y.absoluteBest.buyoutPrice/y.absoluteBest.stackSize);		end;
	
	if (gSortScansBy == ATR_SORTBY_PRICE_ASC) then		return xprice < yprice;		end
	if (gSortScansBy == ATR_SORTBY_PRICE_DES) then		return xprice > yprice;		end

end

-----------------------------------------

function AtrSearch:Finish()

	local finishTime = time();
	
	self.processing_state	= KM_NULL_STATE;
	self.current_page		= -1;
	self.query_sent_when	= nil;
	
	self.sortedScans = nil;
	
	local wasExactSearch = (self:NumScans() == 1);		-- search returned only 1 item
	
	local x = 1;
	self.sortedScans = {};
	
	for name,scn in pairs (self.items) do
	
		self.sortedScans[x] = scn;
		x = x + 1;
		
		scn.whenScanned		= finishTime;
		scn.searchText		= self.searchText;

		scn:CondenseAndSort ();

		-- update the fullscan DB
		
		local newprice = Atr_CalcNewDBprice (scn.itemName, scn.lowprices);
		
		if (newprice > 0) then
			if (scn.itemQuality + 1 >= AUCTIONATOR_SCAN_MINLEVEL) then
				gAtr_ScanDB[scn.itemName] = newprice;
			end
		end
	end
	
	Atr_ClearBrowseListings();
	
	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
	
end

-----------------------------------------

function AtrSearch:ClickPriceCol()

	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		self.sortHow = ATR_SORTBY_PRICE_DES;
	else
		self.sortHow = ATR_SORTBY_PRICE_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);

end

-----------------------------------------

function AtrSearch:ClickNameCol()

	if (self.sortHow == ATR_SORTBY_NAME_ASC) then
		self.sortHow = ATR_SORTBY_NAME_DES;
	else
		self.sortHow = ATR_SORTBY_NAME_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
end

-----------------------------------------

function AtrSearch:UpdateArrows()

	Atr_Col1_Heading_ButtonArrow:Hide();
	Atr_Col3_Heading_ButtonArrow:Hide();
	
	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_PRICE_DES) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	elseif (self.sortHow == ATR_SORTBY_NAME_ASC) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_NAME_DES) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	end
end

-----------------------------------------

function Atr_ClearBrowseListings()
	
	local start = time();

	while (time() - start < 5) do
	
		if (CanSendAuctionQuery()) then
			QueryAuctionItems("xyzzy", 43, 43, 0, 7, 0);
			break;
		end
	end

end

-----------------------------------------

function Atr_SortAuctionData (x, y)

	return x.itemPrice < y.itemPrice;

end

-----------------------------------------

function AtrScan:CondenseAndSort ()

	----- Condense the scan data into a table that has only a single entry per stacksize/price combo

	self.sortedData	= {};

	local i,sd;
	local conddata = {};

	for i,sd in ipairs (self.scanData) do

		local ownerCode = "x";
		local dataType  = "n";		-- normal
		
		if (sd.owner == UnitName("player")) then
			ownerCode = "y";
--		elseif (Atr_IsMyToon (sd.owner)) then
--			ownerCode = sd.owner;
		elseif (sd.owner == "__wowEconG") then
			dataType = "eg";
		elseif (sd.owner == "__wowEconS") then
			dataType = "es";
		elseif (sd.owner == "__wowHead") then
			dataType = "h";
		elseif (sd.owner == "__allakhazam") then
			dataType = "k";
		elseif (sd.owner == "__atrLast") then
			dataType = "a";
		end

		local key = "_"..sd.stackSize.."_"..sd.buyoutPrice.."_"..ownerCode..dataType;

		if (conddata[key]) then
			conddata[key].count		= conddata[key].count + 1;
			conddata[key].minpage 	= zc.Min (conddata[key].minpage, sd.pagenum);
			conddata[key].maxpage 	= zc.Max (conddata[key].maxpage, sd.pagenum);
		else
			local data = {};

			data.stackSize 		= sd.stackSize;
			data.buyoutPrice	= sd.buyoutPrice;
			data.itemPrice		= sd.buyoutPrice / sd.stackSize;
			data.minpage		= sd.pagenum;
			data.maxpage		= sd.pagenum;
			data.count			= 1;
			data.type			= dataType;
			data.yours			= (ownerCode == "y");
			
			if (ownerCode ~= "x" and ownerCode ~= "y") then
				data.altname = ownerCode;
			end
			
			if (sd.volume) then
				data.volume = sd.volume;
			end
			
			conddata[key] = data;
		end

	end

	----- create a table of these entries

	local n = 1;

	local i, v;

	for i,v in pairs (conddata) do
		self.sortedData[n] = v;
		n = n + 1;
	end

	-- sort the table by itemPrice

	table.sort (self.sortedData, Atr_SortAuctionData);

	-- analyze and store some info about the data

	self:AnalyzeSortData ();

end

-----------------------------------------

function AtrScan:AnalyzeSortData ()

	self.absoluteBest			= nil;
	self.bestPrices				= {};		-- a table with one entry per stacksize that is the cheapest auction for that particular stacksize
	self.numMatches				= 0;
	self.numMatchesWithBuyout	= 0;
	self.hasStack				= false;
	self.yourBestPrice			= nil;
	self.yourWorstPrice			= nil;
	self.numYourSingletons		= 0;

	local j, sd;

	----- find the best price per stacksize and overall -----

	for j,sd in ipairs(self.sortedData) do

		if (sd.type == "n") then

			self.numMatches = self.numMatches + 1;

			if (sd.itemPrice > 0) then

				self.numMatchesWithBuyout = self.numMatchesWithBuyout + 1;

				if (self.bestPrices[sd.stackSize] == nil or self.bestPrices[sd.stackSize].itemPrice >= sd.itemPrice) then
					self.bestPrices[sd.stackSize] = sd;
				end

				if (self.absoluteBest == nil or self.absoluteBest.itemPrice > sd.itemPrice) then
					self.absoluteBest = sd;
				end
				
				if (sd.yours) then
					if (self.yourBestPrice == nil or self.yourBestPrice > sd.itemPrice) then
						self.yourBestPrice = sd.itemPrice;
					end
					
					if (self.yourWorstPrice == nil or self.yourWorstPrice < sd.itemPrice) then
						self.yourWorstPrice = sd.itemPrice;
					end
					
					if (sd.stackSize == 1) then
						self.numYourSingletons = self.numYourSingletons + sd.count;
					end
				end
			end

			if (sd.stackSize > 1) then
				self.hasStack = true;
			end
		end
	end
end

-----------------------------------------

function AtrScan:FindInSortedData (stackSize, buyoutPrice)
	local j = 1;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice and sd.yours) then
			return j;
		end
	end
	
	return 0;
end


-----------------------------------------

function AtrScan:FindMatchByStackSize (stackSize)

	local index = nil;

	local basedata = self.absoluteBest;

	if (self.bestPrices[stackSize]) then
		basedata = self.bestPrices[stackSize];
	end

	local numrows = #self.sortedData;

	local n;

	for n = 1,numrows do

		local data = self.sortedData[n];

		if (basedata and data.itemPrice == basedata.itemPrice and data.stackSize == basedata.stackSize and data.yours == basedata.yours) then
			index = n;
			break;
		end
	end

	return index;
	
end

-----------------------------------------

function AtrScan:FindMatchByYours ()

	local index = nil;

	local j;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.yours) then
			index = j;
			break;
		end
	end

	return index;

end

-----------------------------------------

function AtrScan:FindCheapest ()

	local index = nil;

	local j;
	for j = 1,#self.sortedData do
		sd = self.sortedData[j];
		if (sd.itemPrice > 0) then
			index = j;
			break;
		end
	end

	return index;

end


-----------------------------------------

function AtrScan:GetNumAvailable ()

	local num = 0;

	local j, data;
	for j = 1,#self.sortedData do

		data = self.sortedData[j];
		num = num + (data.count * data.stackSize);
	end
	
	return num;
end

-----------------------------------------

function AtrScan:IsNil ()

	if (self.itemName == nil or self.itemName == "" or self.itemName == "nil") then
		return true;
	end
	
	return false;
end

-----------------------------------------

ATR_FS_NULL            = 0;
ATR_FS_STARTED         = 1;
ATR_FS_ANALYZING       = 2;
ATR_FS_CLEANING_UP     = 3;

ATR_FSS_NULL           = 0;
ATR_FSS_WAITING_PAGE   = 1;
ATR_FSS_STALE_PAGE     = 2;
ATR_FSS_BUILDING_DB    = 3;

gAtr_FullScanState      = ATR_FS_NULL;
gAtr_FullScanSubState   = ATR_FSS_NULL;

local gAtr_FullScanStart;
local gAtr_FullScanDur;

-- ==========================================================
-- Warmane-safe high-speed paginated Full Scan
-- ==========================================================
--
-- Warmane disconnects this client when the old WotLK
-- QueryAuctionItems(..., getAll=true) request is used.
--
-- This scanner therefore uses normal 50-row AH pages, but has
-- ZERO artificial delay between successful pages:
--
--   query page
--       -> AUCTION_ITEM_LIST_UPDATE
--       -> process page
--       -> immediately submit next page as soon as
--          CanSendAuctionQuery() opens
--
-- It also:
--
--   * shows live page / auction / speed / ETA information;
--   * commits scanned prices into gAtr_ScanDB after EVERY page;
--   * checkpoints scan progress into AUCTIONATOR_SAVEDVARS;
--   * pauses cleanly if the Auction House is closed;
--   * resumes an interrupted scan when Full Scan is opened again;
--   * retries stale or missing AH responses safely.
--
-- Shift-click "Resume Scan" to discard a saved checkpoint and
-- begin again from page zero.
-- ==========================================================

local ATR_FULLSCAN_PAGE_SIZE              = 50;
local ATR_FULLSCAN_STALE_POLL_TIMEOUT     = 1.50;
local ATR_FULLSCAN_RESPONSE_TIMEOUT       = 15.00;
local ATR_FULLSCAN_MAX_PAGE_RETRIES       = 6;
local ATR_FULLSCAN_DB_CHUNK               = 250;
local ATR_FULLSCAN_SPEED_SAMPLE_COUNT     = 40;
local ATR_FULLSCAN_CHECKPOINT_MAX_AGE     = 60 * 60;
local ATR_FULLSCAN_CHECKPOINT_KEY         = "FULL_SCAN_CHECKPOINT_V2";

-- Live scanner state.
local gAtr_FullScanPage                   = 0;   -- zero-based NEXT/current page
local gAtr_FullScanTotalPages             = 0;
local gAtr_FullScanTotalAuctions          = 0;
local gAtr_FullScanAuctionsScanned        = 0;
local gAtr_FullScanLastPageSignature      = nil;
local gAtr_FullScanPageRetries            = 0;
local gAtr_FullScanQuerySentAt            = nil;
local gAtr_FullScanStaleStartedAt         = nil;
local gAtr_FullScanAwaitingResponse       = false;

-- Speed / ETA state.
local gAtr_FullScanSpeedSamples           = {};

-- Aggregated data built across all accepted pages.
local gAtr_FullScanLowprices              = nil;
local gAtr_FullScanQualities              = nil;

-- Tracks whether an item existed before this scan touched it.
-- Required because partial page commits update gAtr_ScanDB live.
local gAtr_FullScanExistingAtStart        = nil;

-- Final database build state.
local gAtr_FullScanDBNames                = nil;
local gAtr_FullScanDBIndex                = 1;
local gAtr_FullScanNumEachQual            = nil;
local gAtr_FullScanNumRemoved             = nil;
local gAtr_FullScanTotalItems             = 0;

-----------------------------------------

function Atr_GetDBsize()

    local n = 0;
    local a,v;

    for a,v in pairs (gAtr_ScanDB) do
        n = n + 1;
    end

    return n;
end

-----------------------------------------

local gNumAdded, gNumUpdated;

-----------------------------------------
-- Small formatting helpers
-----------------------------------------

local function Atr_FullScanFormatNumber (value)

    local s = tostring (math.floor (tonumber(value) or 0));

    while true do

        local replaced;

        s, replaced = string.gsub (
            s,
            "^(-?%d+)(%d%d%d)",
            "%1,%2"
        );

        if (replaced == 0) then
            break;
        end
    end

    return s;
end

-----------------------------------------

local function Atr_FullScanFormatRemaining (seconds)

    seconds = math.max (
        0,
        math.floor ((tonumber(seconds) or 0) + 0.5)
    );

    local hours = math.floor (seconds / 3600);
    local minutes = math.floor ((seconds % 3600) / 60);
    local secs = seconds % 60;

    -- ==========================================================
    -- Human-readable duration rather than clock-style MM:SS.
    --
    -- Examples:
    --   42 seconds       -> "42 secs"
    --   16m 46s         -> "16 mins 46 secs"
    --   1h 12m          -> "1 hr 12 mins"
    -- ==========================================================

    if (hours > 0) then

        local hourLabel = "hrs";

        if (hours == 1) then
            hourLabel = "hr";
        end

        local minuteLabel = "mins";

        if (minutes == 1) then
            minuteLabel = "min";
        end

        if (minutes > 0) then

            return string.format (
                "%d %s %d %s",
                hours,
                hourLabel,
                minutes,
                minuteLabel
            );

        end

        return string.format (
            "%d %s",
            hours,
            hourLabel
        );

    end

    if (minutes > 0) then

        local minuteLabel = "mins";
        local secondLabel = "secs";

        if (minutes == 1) then
            minuteLabel = "min";
        end

        if (secs == 1) then
            secondLabel = "sec";
        end

        return string.format (
            "%d %s %d %s",
            minutes,
            minuteLabel,
            secs,
            secondLabel
        );

    end

    local secondLabel = "secs";

    if (secs == 1) then
        secondLabel = "sec";
    end

    return string.format (
        "%d %s",
        secs,
        secondLabel
    );
end

-----------------------------------------
-- Saved checkpoint helpers
-----------------------------------------

local function Atr_FullScanEnsureSavedVars ()

    if (type(AUCTIONATOR_SAVEDVARS) ~= "table") then
        AUCTIONATOR_SAVEDVARS = {};
    end

end

-----------------------------------------

local function Atr_FullScanGetScope ()

    local realm = "";

    if (GetRealmName) then
        realm = GetRealmName() or "";
    end

    local faction = "";

    if (UnitFactionGroup) then
        faction = UnitFactionGroup("player") or "";
    end

    return realm, faction;
end

-----------------------------------------

local function Atr_FullScanClearCheckpoint ()

    Atr_FullScanEnsureSavedVars();

    AUCTIONATOR_SAVEDVARS[ATR_FULLSCAN_CHECKPOINT_KEY] = nil;

end

-----------------------------------------

local function Atr_FullScanGetCheckpoint ()

    if (type(AUCTIONATOR_SAVEDVARS) ~= "table") then
        return nil;
    end

    local checkpoint =
        AUCTIONATOR_SAVEDVARS[ATR_FULLSCAN_CHECKPOINT_KEY];

    if (type(checkpoint) ~= "table") then
        return nil;
    end

    if (checkpoint.version ~= 2) then
        return nil;
    end

    local realm, faction = Atr_FullScanGetScope();

    if (
        checkpoint.realm ~= realm
        or checkpoint.faction ~= faction
    ) then
        return nil;
    end

    if (
        not checkpoint.updatedAt
        or time() - checkpoint.updatedAt
            > ATR_FULLSCAN_CHECKPOINT_MAX_AGE
    ) then

        Atr_FullScanClearCheckpoint();
        return nil;
    end

    if (
        type(checkpoint.lowprices) ~= "table"
        or type(checkpoint.qualities) ~= "table"
        or type(checkpoint.existingAtStart) ~= "table"
    ) then
        return nil;
    end

    return checkpoint;
end

-----------------------------------------

local function Atr_FullScanSaveCheckpoint (phase)

    if (
        not gAtr_FullScanLowprices
        or not gAtr_FullScanQualities
        or not gAtr_FullScanExistingAtStart
    ) then
        return;
    end

    Atr_FullScanEnsureSavedVars();

    local realm, faction = Atr_FullScanGetScope();

    local elapsed = 0;

    if (gAtr_FullScanStart) then
        elapsed = math.max (0, time() - gAtr_FullScanStart);
    end

    AUCTIONATOR_SAVEDVARS[ATR_FULLSCAN_CHECKPOINT_KEY] = {
        version             = 2,
        phase               = phase or "scan",

        realm               = realm,
        faction             = faction,

        updatedAt           = time(),
        elapsed             = elapsed,

        page                = gAtr_FullScanPage,
        totalPages          = gAtr_FullScanTotalPages,
        totalAuctions       = gAtr_FullScanTotalAuctions,
        auctionsScanned     = gAtr_FullScanAuctionsScanned,

        lowprices           = gAtr_FullScanLowprices,
        qualities           = gAtr_FullScanQualities,
        existingAtStart     = gAtr_FullScanExistingAtStart,

        dbNames             = gAtr_FullScanDBNames,
        dbIndex             = gAtr_FullScanDBIndex,
        numEachQual         = gAtr_FullScanNumEachQual,
        numRemoved          = gAtr_FullScanNumRemoved,
        totalItems          = gAtr_FullScanTotalItems,

        numAdded            = gNumAdded or 0,
        numUpdated          = gNumUpdated or 0
    };

end

-----------------------------------------

local function Atr_FullScanRestoreCheckpoint (checkpoint)

    if (not checkpoint) then
        return false;
    end

    gAtr_FullScanPage =
        tonumber(checkpoint.page) or 0;

    gAtr_FullScanTotalPages =
        tonumber(checkpoint.totalPages) or 0;

    gAtr_FullScanTotalAuctions =
        tonumber(checkpoint.totalAuctions) or 0;

    gAtr_FullScanAuctionsScanned =
        tonumber(checkpoint.auctionsScanned) or 0;

    gAtr_FullScanLowprices =
        checkpoint.lowprices or {};

    gAtr_FullScanQualities =
        checkpoint.qualities or {};

    gAtr_FullScanExistingAtStart =
        checkpoint.existingAtStart or {};

    gAtr_FullScanDBNames =
        checkpoint.dbNames;

    gAtr_FullScanDBIndex =
        tonumber(checkpoint.dbIndex) or 1;

    gAtr_FullScanNumEachQual =
        checkpoint.numEachQual
        or {0, 0, 0, 0, 0, 0, 0, 0, 0};

    gAtr_FullScanNumRemoved =
        checkpoint.numRemoved
        or {0, 0, 0, 0, 0, 0, 0, 0};

    gAtr_FullScanTotalItems =
        tonumber(checkpoint.totalItems) or 0;

    gNumAdded =
        tonumber(checkpoint.numAdded) or 0;

    gNumUpdated =
        tonumber(checkpoint.numUpdated) or 0;

    gAtr_FullScanLastPageSignature = nil;
    gAtr_FullScanPageRetries = 0;
    gAtr_FullScanQuerySentAt = nil;
    gAtr_FullScanStaleStartedAt = nil;
    gAtr_FullScanAwaitingResponse = false;

    -- Preserve total elapsed scan time for the final summary.
    gAtr_FullScanStart =
        time() - (tonumber(checkpoint.elapsed) or 0);

    -- Speed / ETA should only be based on the CURRENT connection,
    -- not on time spent disconnected or with the AH closed.
    gAtr_FullScanSpeedSamples = {
        {
            when = GetTime(),
            auctions = gAtr_FullScanAuctionsScanned
        }
    };

    return true;
end

-----------------------------------------
-- Runtime reset
-----------------------------------------

local function Atr_FullScanResetRuntime ()

    gAtr_FullScanPage              = 0;
    gAtr_FullScanTotalPages        = 0;
    gAtr_FullScanTotalAuctions     = 0;
    gAtr_FullScanAuctionsScanned   = 0;
    gAtr_FullScanLastPageSignature = nil;
    gAtr_FullScanPageRetries       = 0;
    gAtr_FullScanQuerySentAt       = nil;
    gAtr_FullScanStaleStartedAt    = nil;
    gAtr_FullScanAwaitingResponse  = false;

    gAtr_FullScanLowprices         = {};
    gAtr_FullScanQualities         = {};
    gAtr_FullScanExistingAtStart   = {};

    gAtr_FullScanDBNames           = nil;
    gAtr_FullScanDBIndex           = 1;
    gAtr_FullScanNumEachQual       = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    gAtr_FullScanNumRemoved        = {0, 0, 0, 0, 0, 0, 0, 0};
    gAtr_FullScanTotalItems        = 0;

    gAtr_FullScanSpeedSamples = {
        {
            when = GetTime(),
            auctions = 0
        }
    };

end

-----------------------------------------
-- Stale-page fingerprint
-----------------------------------------

local function Atr_FullScanPageSignature (numBatchAuctions)

    if (not numBatchAuctions or numBatchAuctions <= 0) then
        return "empty";
    end

    -- Sampling first / middle / last is enough to detect the
    -- stale-page behaviour without making another full 50-row pass.
    local middle = math.floor ((numBatchAuctions + 1) / 2);
    local indexes = {1, middle, numBatchAuctions};
    local parts = { tostring (numBatchAuctions) };

    local n;

    for n = 1, #indexes do

        local x = indexes[n];

        local name, texture, count, quality, canUse, level,
            minBid, minIncrement, buyoutPrice, bidAmount =
            GetAuctionItemInfo ("list", x);

        table.insert (
            parts,
            tostring(name or "?")
            .. "/" .. tostring(count or 0)
            .. "/" .. tostring(minBid or 0)
            .. "/" .. tostring(buyoutPrice or 0)
            .. "/" .. tostring(bidAmount or 0)
        );
    end

    return table.concat (parts, "|");
end

-----------------------------------------
-- Live speed / ETA
-----------------------------------------

local function Atr_FullScanRecordSpeedSample ()

    table.insert (
        gAtr_FullScanSpeedSamples,
        {
            when = GetTime(),
            auctions = gAtr_FullScanAuctionsScanned
        }
    );

    while (
        #gAtr_FullScanSpeedSamples
        > ATR_FULLSCAN_SPEED_SAMPLE_COUNT
    ) do
        table.remove (gAtr_FullScanSpeedSamples, 1);
    end

end

-----------------------------------------

local function Atr_FullScanGetSecondsPerPage ()

    -- ==========================================================
    -- ETA estimator
    -- ==========================================================
    --
    -- A straight auctions/second average can jump around badly on
    -- Warmane because an occasional page may arrive much slower than
    -- the pages around it. The thing we actually care about is how
    -- long a normal 50-auction page takes.
    --
    -- Build a rolling set of NORMALISED page durations from the last
    -- ~40 accepted pages, trim the fastest/slowest 10%, then average
    -- what remains. This keeps real server slowdowns in the ETA while
    -- preventing one bad response from suddenly adding many minutes.
    -- ==========================================================

    if (#gAtr_FullScanSpeedSamples < 2) then
        return nil;
    end

    local durations = {};
    local i;

    for i = 2, #gAtr_FullScanSpeedSamples do

        local previous = gAtr_FullScanSpeedSamples[i - 1];
        local current  = gAtr_FullScanSpeedSamples[i];

        local elapsed = current.when - previous.when;
        local auctions = current.auctions - previous.auctions;

        if (elapsed > 0 and auctions > 0) then

            -- Normalise partial pages to a standard 50-row page.
            table.insert (
                durations,
                elapsed * (ATR_FULLSCAN_PAGE_SIZE / auctions)
            );

        end
    end

    if (#durations == 0) then
        return nil;
    end

    table.sort (durations);

    local firstIndex = 1;
    local lastIndex = #durations;

    -- Once we have enough history, discard the fastest and slowest
    -- 10% before calculating the mean. This makes the countdown much
    -- steadier without hiding sustained server slowdown.
    if (#durations >= 10) then

        local trim = math.floor (#durations * 0.10);

        firstIndex = 1 + trim;
        lastIndex = #durations - trim;

    end

    local total = 0;
    local count = 0;

    for i = firstIndex, lastIndex do
        total = total + durations[i];
        count = count + 1;
    end

    if (count == 0) then
        return nil;
    end

    return total / count;
end

-----------------------------------------

local function Atr_FullScanGetSpeed ()

    local secondsPerPage =
        Atr_FullScanGetSecondsPerPage();

    if (not secondsPerPage or secondsPerPage <= 0) then
        return 0;
    end

    return ATR_FULLSCAN_PAGE_SIZE / secondsPerPage;
end

-----------------------------------------

local function Atr_FullScanGetRemainingSeconds ()

    local secondsPerPage =
        Atr_FullScanGetSecondsPerPage();

    if (
        not secondsPerPage
        or secondsPerPage <= 0
        or gAtr_FullScanTotalAuctions <= 0
    ) then
        return nil;
    end

    local remainingAuctions =
        gAtr_FullScanTotalAuctions
        - gAtr_FullScanAuctionsScanned;

    if (remainingAuctions <= 0) then
        return 0;
    end

    local remainingPages =
        remainingAuctions / ATR_FULLSCAN_PAGE_SIZE;

    return remainingPages * secondsPerPage;
end

-----------------------------------------

local function Atr_FullScanUpdateLiveStatus ()

    local pageShown = gAtr_FullScanPage + 1;
    local totalPages = gAtr_FullScanTotalPages;
    local totalAuctions = gAtr_FullScanTotalAuctions;

    local speed =
        math.floor (Atr_FullScanGetSpeed() + 0.5);

    local remaining =
        Atr_FullScanGetRemainingSeconds();

    -- Three short lines are much easier to read in the original
    -- Auctionator dialog than one long status string. The FontString
    -- is constrained to the left side of the panel so these lines do
    -- not run underneath the Start / Done buttons.
    if (totalPages > 0 and totalAuctions > 0) then

        local etaText = "calculating...";

        if (remaining ~= nil) then
            etaText = Atr_FullScanFormatRemaining (remaining);
        end

        Atr_FullScanStatus:SetText (
            string.format (
                "Page: %d / %d\nAuctions: %s / %s\nRemaining: ~%s  (%d/sec)",
                math.min (pageShown, totalPages),
                totalPages,
                Atr_FullScanFormatNumber (
                    gAtr_FullScanAuctionsScanned
                ),
                Atr_FullScanFormatNumber (
                    totalAuctions
                ),
                etaText,
                speed
            )
        );

    else

        Atr_FullScanStatus:SetText (
            string.format (
                "Page: %d\nAuctions: %s\nSpeed: %d/sec",
                pageShown,
                Atr_FullScanFormatNumber (
                    gAtr_FullScanAuctionsScanned
                ),
                speed
            )
        );

    end

    -- Because prices are committed after each page, reflect the
    -- growing database count live in the dialog as well.
    if (Atr_FullScanDBsize) then
        Atr_FullScanDBsize:SetText (Atr_GetDBsize());
    end

end

-----------------------------------------
-- Incremental price commit
-----------------------------------------

local function Atr_FullScanCommitTouchedNames (touchedNames)

    local name;

    for name in pairs (touchedNames) do

        local prices = gAtr_FullScanLowprices[name];
        local quality = gAtr_FullScanQualities[name];

        if (prices and quality ~= nil) then

            local newprice =
                Atr_CalcNewDBprice (name, prices);

            if (newprice > 0) then

                local qx = quality + 1;

                if (qx >= AUCTIONATOR_SCAN_MINLEVEL) then

                    -- IMPORTANT:
                    -- Write the CURRENT scan price directly rather
                    -- than comparing it with the previous saved DB
                    -- value. This means partial scan data is fresh
                    -- and survives an interrupted scan.
                    gAtr_ScanDB[name] = newprice;

                elseif (gAtr_ScanDB[name]) then

                    gAtr_ScanDB[name] = nil;

                end
            end
        end
    end

end

-----------------------------------------
-- Query submission
-----------------------------------------

local function Atr_FullScanSendPage ()

    if (gAtr_FullScanState ~= ATR_FS_STARTED) then
        return false;
    end

    if (gAtr_FullScanAwaitingResponse) then
        return false;
    end

    -- This is the only throttle we obey. There is NO additional
    -- fixed delay, so pages run at the maximum rate the WoW
    -- client / Warmane server currently permits.
    if (not CanSendAuctionQuery()) then
        return false;
    end

    gAtr_FullScanAwaitingResponse = true;
    gAtr_FullScanQuerySentAt = GetTime();
    gAtr_FullScanSubState = ATR_FSS_WAITING_PAGE;

    QueryAuctionItems (
        "",
        nil,
        nil,
        nil,
        nil,
        nil,
        gAtr_FullScanPage,
        nil,
        nil
    );

    return true;
end

-----------------------------------------
-- Pause / abort
-----------------------------------------

local function Atr_FullScanPause (reason)

    if (
        gAtr_FullScanState == ATR_FS_STARTED
        and gAtr_FullScanAuctionsScanned > 0
    ) then

        Atr_FullScanSaveCheckpoint ("scan");

    elseif (
        gAtr_FullScanState == ATR_FS_ANALYZING
        and gAtr_FullScanLowprices
    ) then

        Atr_FullScanSaveCheckpoint ("build");

    end

    gAtr_FullScanState = ATR_FS_NULL;
    gAtr_FullScanSubState = ATR_FSS_NULL;
    gAtr_FullScanAwaitingResponse = false;
    gAtr_FullScanQuerySentAt = nil;
    gAtr_FullScanStaleStartedAt = nil;

    if (Atr_FullScanDone) then
        Atr_FullScanDone:Enable();
    end

    Atr_UpdateFullScanFrame();

    if (reason and Atr_FullScanStatus) then
        Atr_FullScanStatus:SetText (reason);
    end

    if (reason) then
        zc.msg_atr (reason);
    end

end

-----------------------------------------

local function Atr_FullScanAbort (reason)

    local message = reason
        or "Full Scan paused.";

    if (gAtr_FullScanAuctionsScanned > 0) then

        message = message
            .. " Partial prices kept; click Resume Scan to continue.";

    end

    Atr_FullScanPause (message);

end

-----------------------------------------
-- Start / resume
-----------------------------------------

function Atr_FullScanStart()

    local canQuery = CanSendAuctionQuery();

    if (not canQuery) then
        Atr_FullScanStatus:SetText (
            "Waiting for auction query..."
        );
        return;
    end

    -- Shift-click is the escape hatch when the user deliberately
    -- wants to throw away an interrupted checkpoint and start over.
    local discardCheckpoint =
        IsShiftKeyDown and IsShiftKeyDown();

    if (discardCheckpoint) then
        Atr_FullScanClearCheckpoint();
    end

    local checkpoint = Atr_FullScanGetCheckpoint();

    Atr_FullScanStartButton:Disable();
    Atr_FullScanDone:Disable();

    SortAuctionClearSort ("list");

    if (checkpoint) then

        Atr_FullScanRestoreCheckpoint (checkpoint);

        if (checkpoint.phase == "build") then

            gAtr_FullScanState = ATR_FS_ANALYZING;
            gAtr_FullScanSubState = ATR_FSS_BUILDING_DB;

            Atr_FullScanStatus:SetText (
                string.format (
                    "Resuming database %d/%d...",
                    math.max (
                        0,
                        (gAtr_FullScanDBIndex or 1) - 1
                    ),
                    gAtr_FullScanDBNames
                        and #gAtr_FullScanDBNames
                        or 0
                )
            );

            return;
        end

        gAtr_FullScanState = ATR_FS_STARTED;
        gAtr_FullScanSubState = ATR_FSS_WAITING_PAGE;

        Atr_FullScanStatus:SetText (
            string.format (
                "Resuming scan\nPage: %d / %d\nAuctions: %s / %s",
                gAtr_FullScanPage + 1,
                gAtr_FullScanTotalPages,
                Atr_FullScanFormatNumber (
                    gAtr_FullScanAuctionsScanned
                ),
                Atr_FullScanFormatNumber (
                    gAtr_FullScanTotalAuctions
                )
            )
        );

        Atr_FullScanSendPage();
        return;
    end

    -- Completely new scan.
    gAtr_FullScanStart = time();
    gAtr_FullScanDur = nil;

    gNumAdded = 0;
    gNumUpdated = 0;

    Atr_FullScanResetRuntime();

    gAtr_FullScanState = ATR_FS_STARTED;
    gAtr_FullScanSubState = ATR_FSS_WAITING_PAGE;

    Atr_FullScanStatus:SetText (
        "Starting fast page scan..."
    );

    Atr_FullScanSaveCheckpoint ("scan");

    -- Page zero is sent immediately. Further pages are chained
    -- from the AH update event / idle gate with zero fixed delay.
    Atr_FullScanSendPage();

end

-----------------------------------------

function Atr_CalcNewDBprice (name, prices)

    if (prices[1] ~= BIGNUM) then
        return prices[1];
    end

    return 0;

end

-----------------------------------------

function Atr_AddToLowPrices (lowprices, itemPrice)

    if (itemPrice > 0) then
        if (itemPrice < lowprices[1]) then
            if (lowprices[1] < lowprices[2]) then
                lowprices[2] = lowprices[1];
            end
            lowprices[1] = itemPrice;
            return true;
        elseif (itemPrice < lowprices[2]) then
            lowprices[2] = itemPrice;
            return true;
        end
    end

    return false;
end

-----------------------------------------

local gScanDetails = {}

-----------------------------------------

function Atr_FullScanMoreDetails ()

    local minutes = math.floor (gAtr_FullScanDur/60);
    local seconds = gAtr_FullScanDur - (minutes * 60);

    zc.msg (" ");
    zc.msg_atr (string.format ("Scan complete (%d:%02d)", minutes, seconds));
    zc.msg_atr (ZT("Auctions scanned")..": |cffffffff", gScanDetails.numBatchAuctions, " |r("..gScanDetails.totalItems, "items)");
    zc.msg_atr ("|cffa335ee   "..ZT("Epic items")..": |r",        gScanDetails.numEachQual[5]);
    zc.msg_atr ("|cff0070dd   "..ZT("Rare items")..": |r",        gScanDetails.numEachQual[4]);
    zc.msg_atr ("|cff1eff00   "..ZT("Uncommon items")..": |r",    gScanDetails.numEachQual[3]);
    zc.msg_atr ("|cffffffff   "..ZT("Common items")..": |r",        gScanDetails.numEachQual[2]);
    zc.msg_atr ("|cff9d9d9d   "..ZT("Poor items")..": |r",        gScanDetails.numEachQual[1]);

    if (gScanDetails.numRemoved[4] > 0) then        zc.msg_atr (ZT("Rare items").." "..ZT("removed from database")..": |cffffffff",        gScanDetails.numRemoved[4]);        end
    if (gScanDetails.numRemoved[3] > 0) then        zc.msg_atr (ZT("Uncommon items").." "..ZT("removed from database")..": |cffffffff",    gScanDetails.numRemoved[3]);        end
    if (gScanDetails.numRemoved[2] > 0) then        zc.msg_atr (ZT("Common items").." "..ZT("removed from database")..": |cffffffff",    gScanDetails.numRemoved[2]);        end
    if (gScanDetails.numRemoved[1] > 0) then        zc.msg_atr (ZT("Poor items").." "..ZT("removed from database")..": |cffffffff",        gScanDetails.numRemoved[1]);        end

    zc.msg_atr (ZT("Items added to database")..": |cffffffff", gScanDetails.gNumAdded);
    zc.msg_atr (ZT("Items updated in database")..": |cffffffff", gScanDetails.gNumUpdated);
    zc.msg_atr (ZT("Items ignored")..": |cffffffff", gScanDetails.totalItems - (gScanDetails.gNumAdded + gScanDetails.gNumUpdated));
    zc.msg (" ");
end

-----------------------------------------
-- Final DB build
-----------------------------------------

local function Atr_FullScanBeginDatabaseBuild ()

    gAtr_FullScanState = ATR_FS_ANALYZING;
    gAtr_FullScanSubState = ATR_FSS_BUILDING_DB;
    gAtr_FullScanAwaitingResponse = false;

    gAtr_FullScanDBNames = {};

    local name;

    for name in pairs (gAtr_FullScanLowprices) do
        table.insert (gAtr_FullScanDBNames, name);
    end

    gAtr_FullScanDBIndex = 1;
    gAtr_FullScanNumEachQual =
        {0, 0, 0, 0, 0, 0, 0, 0, 0};

    gAtr_FullScanNumRemoved =
        {0, 0, 0, 0, 0, 0, 0, 0};

    gAtr_FullScanTotalItems = 0;
    gNumAdded = 0;
    gNumUpdated = 0;

    Atr_FullScanSaveCheckpoint ("build");

    Atr_FullScanStatus:SetText (
        string.format (
            "Finalising prices 0/%d...",
            #gAtr_FullScanDBNames
        )
    );

end

-----------------------------------------

local function Atr_FullScanFinalize ()

    gAtr_FullScanDur =
        time() - gAtr_FullScanStart;

    gScanDetails.numBatchAuctions =
        gAtr_FullScanAuctionsScanned;

    gScanDetails.totalItems =
        gAtr_FullScanTotalItems;

    gScanDetails.numEachQual =
        gAtr_FullScanNumEachQual;

    gScanDetails.numRemoved =
        gAtr_FullScanNumRemoved;

    gScanDetails.gNumAdded =
        gNumAdded;

    gScanDetails.gNumUpdated =
        gNumUpdated;

    gAtr_FullScanState = ATR_FS_CLEANING_UP;
    gAtr_FullScanSubState = ATR_FSS_NULL;

    Atr_FullScanMoreDetails();

    Atr_FullScanDone:Enable();

    Atr_FSR_scanned_count:SetText (
        gAtr_FullScanAuctionsScanned
    );

    Atr_FSR_added_count:SetText (
        gNumAdded
    );

    Atr_FSR_updated_count:SetText (
        gNumUpdated
    );

    Atr_FSR_ignored_count:SetText (
        gAtr_FullScanTotalItems
        - (gNumAdded + gNumUpdated)
    );

    Atr_FullScanHTML:Hide();
    Atr_FullScanResults:Show();

    Atr_FullScanResults:SetBackdropColor (
        0.3,
        0.3,
        0.4
    );

    AUCTIONATOR_LAST_SCAN_TIME = time();

    Atr_FullScanClearCheckpoint();

    local speed =
        math.floor (Atr_FullScanGetSpeed() + 0.5);

    local completeText =
        string.format (
            "Done | %s auctions | %d pages | %d/s",
            Atr_FullScanFormatNumber (
                gAtr_FullScanAuctionsScanned
            ),
            gAtr_FullScanTotalPages,
            speed
        );

    Atr_UpdateFullScanFrame();

    Atr_FullScanStatus:SetText (
        completeText
    );

    collectgarbage ("collect");

end

-----------------------------------------

local function Atr_FullScanProcessDatabaseChunk ()

    if (
        gAtr_FullScanState ~= ATR_FS_ANALYZING
        or not gAtr_FullScanDBNames
    ) then
        return;
    end

    local finalIndex = math.min (
        gAtr_FullScanDBIndex + ATR_FULLSCAN_DB_CHUNK - 1,
        #gAtr_FullScanDBNames
    );

    local i;

    for i = gAtr_FullScanDBIndex, finalIndex do

        local name =
            gAtr_FullScanDBNames[i];

        local prices =
            gAtr_FullScanLowprices[name];

        local quality =
            gAtr_FullScanQualities[name];

        if (prices and quality ~= nil) then

            local newprice =
                Atr_CalcNewDBprice (name, prices);

            if (newprice > 0) then

                local qx = quality + 1;

                gAtr_FullScanNumEachQual[qx] =
                    (gAtr_FullScanNumEachQual[qx] or 0)
                    + 1;

                gAtr_FullScanTotalItems =
                    gAtr_FullScanTotalItems + 1;

                if (qx < AUCTIONATOR_SCAN_MINLEVEL) then

                    if (gAtr_FullScanExistingAtStart[name]) then

                        gAtr_FullScanNumRemoved[qx] =
                            (gAtr_FullScanNumRemoved[qx] or 0)
                            + 1;

                    end

                    gAtr_ScanDB[name] = nil;

                else

                    -- Stats must use the DB state from BEFORE this
                    -- scan because pages have already committed live.
                    if (gAtr_FullScanExistingAtStart[name]) then
                        gNumUpdated = gNumUpdated + 1;
                    else
                        gNumAdded = gNumAdded + 1;
                    end

                    gAtr_ScanDB[name] = newprice;

                    if (gAtr_MeanDB[name] == nil) then
                        gAtr_MeanDB[name] = {};
                    end

                    if (#gAtr_MeanDB[name] < 15) then

                        table.insert (
                            gAtr_MeanDB[name],
                            newprice
                        );

                    else

                        table.remove (
                            gAtr_MeanDB[name],
                            math.random (
                                1,
                                #gAtr_MeanDB[name]
                            )
                        );

                        table.insert (
                            gAtr_MeanDB[name],
                            newprice
                        );

                    end

                    table.sort (
                        gAtr_MeanDB[name]
                    );

                end
            end
        end
    end

    gAtr_FullScanDBIndex =
        finalIndex + 1;

    Atr_FullScanSaveCheckpoint ("build");

    Atr_FullScanStatus:SetText (
        string.format (
            "Finalising prices %d/%d...",
            math.min (
                finalIndex,
                #gAtr_FullScanDBNames
            ),
            #gAtr_FullScanDBNames
        )
    );

    if (
        gAtr_FullScanDBIndex
        > #gAtr_FullScanDBNames
    ) then

        Atr_FullScanFinalize();

    end

end

-----------------------------------------
-- Accept a completed page
-----------------------------------------

local function Atr_FullScanAcceptCurrentPage (
    numBatchAuctions,
    totalAuctions
)

    local touchedNames = {};
    local x;

    for x = 1, numBatchAuctions do

        local name, texture, count, quality, canUse, level,
            minBid, minIncrement, buyoutPrice =
            GetAuctionItemInfo ("list", x);

        if (
            name ~= nil
            and count ~= nil
            and count > 0
            and buyoutPrice ~= nil
        ) then

            -- Capture pre-scan DB existence BEFORE the live commit
            -- changes gAtr_ScanDB.
            if (
                gAtr_FullScanExistingAtStart[name]
                == nil
            ) then

                gAtr_FullScanExistingAtStart[name] =
                    (gAtr_ScanDB[name] ~= nil);

            end

            gAtr_FullScanQualities[name] =
                quality;

            local itemPrice =
                math.floor (buyoutPrice / count);

            if (itemPrice > 0) then

                if (
                    not gAtr_FullScanLowprices[name]
                ) then

                    gAtr_FullScanLowprices[name] = {
                        BIGNUM,
                        BIGNUM,
                        BIGNUM
                    };

                end

                Atr_AddToLowPrices (
                    gAtr_FullScanLowprices[name],
                    itemPrice
                );

                touchedNames[name] = true;
            end
        end
    end

    -- Commit this page immediately. If the scan is interrupted,
    -- everything accepted up to this point remains useful.
    Atr_FullScanCommitTouchedNames (
        touchedNames
    );

    gAtr_FullScanAuctionsScanned =
        gAtr_FullScanAuctionsScanned
        + numBatchAuctions;

    gAtr_FullScanTotalAuctions =
        totalAuctions
        or gAtr_FullScanTotalAuctions;

    if (gAtr_FullScanTotalAuctions > 0) then

        gAtr_FullScanTotalPages =
            math.ceil (
                gAtr_FullScanTotalAuctions
                / ATR_FULLSCAN_PAGE_SIZE
            );

    end

    gAtr_FullScanPageRetries = 0;
    gAtr_FullScanStaleStartedAt = nil;
    gAtr_FullScanAwaitingResponse = false;

    Atr_FullScanRecordSpeedSample();
    Atr_FullScanUpdateLiveStatus();

    local pageNumber =
        gAtr_FullScanPage + 1;

    local done = false;

    if (
        numBatchAuctions
        < ATR_FULLSCAN_PAGE_SIZE
    ) then

        done = true;

    elseif (
        gAtr_FullScanTotalPages > 0
        and pageNumber
            >= gAtr_FullScanTotalPages
    ) then

        done = true;

    end

    if (done) then

        Atr_FullScanBeginDatabaseBuild();
        return;

    end

    -- Advance to the NEXT page before checkpointing. Therefore a
    -- resume never intentionally repeats an already accepted page.
    gAtr_FullScanPage =
        gAtr_FullScanPage + 1;

    gAtr_FullScanSubState =
        ATR_FSS_WAITING_PAGE;

    Atr_FullScanSaveCheckpoint ("scan");

    -- Try immediately in the same event. If the client throttle is
    -- still closed the idle handler will retry every frame.
    Atr_FullScanSendPage();

end

-----------------------------------------
-- AUCTION_ITEM_LIST_UPDATE handler
-----------------------------------------

function Atr_FullScanAnalyze()

    if (
        gAtr_FullScanState
        ~= ATR_FS_STARTED
    ) then
        return;
    end

    if (not gAtr_FullScanAwaitingResponse) then
        return;
    end

    local numBatchAuctions, totalAuctions =
        GetNumAuctionItems ("list");

    if (
        not numBatchAuctions
        or not totalAuctions
    ) then
        return;
    end

    -- Empty page zero can be transient on a busy realm.
    if (
        gAtr_FullScanPage == 0
        and numBatchAuctions == 0
        and totalAuctions == 0
    ) then

        gAtr_FullScanAwaitingResponse =
            false;

        gAtr_FullScanPageRetries =
            gAtr_FullScanPageRetries + 1;

        if (
            gAtr_FullScanPageRetries
            > ATR_FULLSCAN_MAX_PAGE_RETRIES
        ) then

            Atr_FullScanAbort (
                "Full Scan stopped: Warmane repeatedly returned an empty first page."
            );

            return;
        end

        return;
    end

    local signature =
        Atr_FullScanPageSignature (
            numBatchAuctions
        );

    if (
        gAtr_FullScanPage > 0
        and gAtr_FullScanLastPageSignature ~= nil
        and signature
            == gAtr_FullScanLastPageSignature
    ) then

        -- Do NOT instantly re-query. 3.3.5 can fire the update
        -- event just before its local list swaps to the new page.
        gAtr_FullScanSubState =
            ATR_FSS_STALE_PAGE;

        if (not gAtr_FullScanStaleStartedAt) then

            gAtr_FullScanStaleStartedAt =
                GetTime();

        end

        return;
    end

    gAtr_FullScanLastPageSignature =
        signature;

    Atr_FullScanAcceptCurrentPage (
        numBatchAuctions,
        totalAuctions
    );

end

-----------------------------------------
-- Full Scan dialog
-----------------------------------------

function Atr_ShowFullScanFrame()

    -- Keep multi-line scan information on the left side of the
    -- dialog. The original XML leaves this FontString unconstrained,
    -- which is why long status text previously ran beneath the buttons.
    if (Atr_FullScanStatus) then
        Atr_FullScanStatus:SetWidth (245);
        Atr_FullScanStatus:SetJustifyH ("LEFT");
        Atr_FullScanStatus:SetJustifyV ("TOP");
    end

    -- Give the three-line yellow scan status some breathing room
    -- before the explanatory grey text below it.
    if (Atr_FullScanHTML) then
        Atr_FullScanHTML:ClearAllPoints();
        Atr_FullScanHTML:SetPoint (
            "TOPLEFT",
            Atr_FullScanFrame,
            "TOPLEFT",
            27,
            -190
        );
        Atr_FullScanHTML:SetWidth (405);
        Atr_FullScanHTML:SetHeight (285);
    end

    Atr_FullScanHTML:Show();
    Atr_FullScanResults:Hide();

    Atr_FullScanFrame:Show();
    Atr_FullScanFrame:SetBackdropColor(
        0,
        0,
        0,
        100
    );

    Atr_UpdateFullScanFrame();

    local checkpoint =
        Atr_FullScanGetCheckpoint();

    if (
        gAtr_FullScanState == ATR_FS_NULL
        and not checkpoint
    ) then

        Atr_FullScanStatus:SetText ("");

    end

    local expText =
        "<html><body>"
        .. "<p>"
        .. ZT("Scanning is entirely optional.")
        .. "<br/><br/>"
        .. ZT("SCAN_EXPLANATION")
        .. "</p>"
        .. "</body></html>";

    Atr_FullScanHTML:SetText (expText);
    Atr_FullScanHTML:SetSpacing (3);

end

-----------------------------------------

function Atr_UpdateFullScanFrame()

    Atr_FullScanDBsize:SetText (
        Atr_GetDBsize()
    );

    if (AUCTIONATOR_LAST_SCAN_TIME) then

        Atr_FullScanDBwhen:SetText (
            date (
                "%A, %B %d at %I:%M %p",
                AUCTIONATOR_LAST_SCAN_TIME
            )
        );

    else

        Atr_FullScanDBwhen:SetText (
            ZT("Never")
        );

    end

    local canQuery =
        CanSendAuctionQuery();

    if (gAtr_FullScanState == ATR_FS_NULL) then

        local checkpoint =
            Atr_FullScanGetCheckpoint();

        if (checkpoint) then

            Atr_FullScanStartButton:SetText (
                "Resume Scan"
            );

            Atr_FullScanStartButton:Enable();

            if (checkpoint.phase == "build") then

                Atr_FullScanNext:SetText (
                    "Resume processing"
                );

                Atr_FullScanStatus:SetText (
                    string.format (
                        "Saved scan | %s auctions | resume processing",
                        Atr_FullScanFormatNumber (
                            checkpoint.auctionsScanned or 0
                        )
                    )
                );

            else

                Atr_FullScanNext:SetText (
                    string.format (
                        "Resume page %d",
                        (checkpoint.page or 0) + 1
                    )
                );

                Atr_FullScanStatus:SetText (
                    string.format (
                        "Saved scan\nPage: %d / %d\nAuctions: %s / %s",
                        (checkpoint.page or 0) + 1,
                        checkpoint.totalPages or 0,
                        Atr_FullScanFormatNumber (
                            checkpoint.auctionsScanned or 0
                        ),
                        Atr_FullScanFormatNumber (
                            checkpoint.totalAuctions or 0
                        )
                    )
                );

            end

        else

            Atr_FullScanStartButton:SetText (
                "Start Scanning"
            );

            if (canQuery) then

                Atr_FullScanStartButton:Enable();

                Atr_FullScanNext:SetText (
                    ZT("Now")
                );

            else

                Atr_FullScanStartButton:Disable();

                Atr_FullScanNext:SetText (
                    ZT("waiting for auction query")
                );

            end

        end

    else

        Atr_FullScanStartButton:Disable();

        Atr_FullScanNext:SetText (
            "Scanning"
        );

    end

end

-----------------------------------------

function Atr_FullScan_GetDurString()

    local duration =
        gAtr_FullScanDur;

    if (
        duration == nil
        and gAtr_FullScanStart
    ) then

        duration =
            time() - gAtr_FullScanStart;

    end

    duration = duration or 0;

    local minutes =
        math.floor (duration / 60);

    local seconds =
        duration - (minutes * 60);

    return string.format (
        "%d:%02d",
        minutes,
        seconds
    );

end

-----------------------------------------
-- Always-on lifecycle frame
-----------------------------------------

local gAtr_FullScanLifecycleFrame =
    CreateFrame ("Frame");

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "AUCTION_HOUSE_CLOSED"
);

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "PLAYER_LOGOUT"
);

gAtr_FullScanLifecycleFrame:SetScript (
    "OnEvent",
    function (self, event)

        if (event == "PLAYER_LOGOUT") then

            if (
                gAtr_FullScanState
                == ATR_FS_STARTED
            ) then

                Atr_FullScanSaveCheckpoint (
                    "scan"
                );

            elseif (
                gAtr_FullScanState
                == ATR_FS_ANALYZING
            ) then

                Atr_FullScanSaveCheckpoint (
                    "build"
                );

            end

            return;
        end

        if (
            event == "AUCTION_HOUSE_CLOSED"
            and (
                gAtr_FullScanState
                    == ATR_FS_STARTED
                or gAtr_FullScanState
                    == ATR_FS_ANALYZING
            )
        ) then

            Atr_FullScanPause (
                string.format (
                    "Paused | %s auctions saved | reopen AH to resume",
                    Atr_FullScanFormatNumber (
                        gAtr_FullScanAuctionsScanned
                    )
                )
            );

        end

    end
);

-----------------------------------------
-- OnUpdate driver
-----------------------------------------

function Atr_FullScanFrameIdle()

    -- ==========================================================
    -- Active page scan
    -- ==========================================================
    if (
        gAtr_FullScanState
        == ATR_FS_STARTED
    ) then

        gAtr_FullScanDur =
            time() - gAtr_FullScanStart;

        -- ------------------------------------------------------
        -- Stale page handling
        -- ------------------------------------------------------
        if (
            gAtr_FullScanSubState
                == ATR_FSS_STALE_PAGE
            and gAtr_FullScanAwaitingResponse
        ) then

            local numBatchAuctions, totalAuctions =
                GetNumAuctionItems ("list");

            if (
                numBatchAuctions
                and totalAuctions
            ) then

                local signature =
                    Atr_FullScanPageSignature (
                        numBatchAuctions
                    );

                -- The requested page has now appeared in the
                -- client cache. Accept without another query.
                if (
                    signature
                    ~= gAtr_FullScanLastPageSignature
                ) then

                    gAtr_FullScanLastPageSignature =
                        signature;

                    Atr_FullScanAcceptCurrentPage (
                        numBatchAuctions,
                        totalAuctions
                    );

                    return;
                end
            end

            -- Still showing the previous page. Poll locally every
            -- frame first; only re-query after the grace window.
            if (
                gAtr_FullScanStaleStartedAt
                and GetTime()
                    - gAtr_FullScanStaleStartedAt
                    >= ATR_FULLSCAN_STALE_POLL_TIMEOUT
            ) then

                gAtr_FullScanPageRetries =
                    gAtr_FullScanPageRetries + 1;

                if (
                    gAtr_FullScanPageRetries
                    > ATR_FULLSCAN_MAX_PAGE_RETRIES
                ) then

                    Atr_FullScanAbort (
                        string.format (
                            "Full Scan paused: page %d remained stale after %d retries.",
                            gAtr_FullScanPage + 1,
                            ATR_FULLSCAN_MAX_PAGE_RETRIES
                        )
                    );

                    return;
                end

                gAtr_FullScanAwaitingResponse =
                    false;

                gAtr_FullScanStaleStartedAt =
                    nil;

                gAtr_FullScanSubState =
                    ATR_FSS_WAITING_PAGE;

                Atr_FullScanStatus:SetText (
                    string.format (
                        "Retry pg %d/%d | stale response %d/%d",
                        gAtr_FullScanPage + 1,
                        gAtr_FullScanTotalPages,
                        gAtr_FullScanPageRetries,
                        ATR_FULLSCAN_MAX_PAGE_RETRIES
                    )
                );

                Atr_FullScanSendPage();

                return;
            end

        -- ------------------------------------------------------
        -- Waiting for permission to send next page.
        -- ------------------------------------------------------
        elseif (
            gAtr_FullScanSubState
                == ATR_FSS_WAITING_PAGE
            and not gAtr_FullScanAwaitingResponse
        ) then

            Atr_FullScanSendPage();

        -- ------------------------------------------------------
        -- Query sent, but Warmane never returned an update.
        -- ------------------------------------------------------
        elseif (
            gAtr_FullScanSubState
                == ATR_FSS_WAITING_PAGE
            and gAtr_FullScanAwaitingResponse
            and gAtr_FullScanQuerySentAt
            and GetTime()
                - gAtr_FullScanQuerySentAt
                >= ATR_FULLSCAN_RESPONSE_TIMEOUT
        ) then

            gAtr_FullScanPageRetries =
                gAtr_FullScanPageRetries + 1;

            if (
                gAtr_FullScanPageRetries
                > ATR_FULLSCAN_MAX_PAGE_RETRIES
            ) then

                Atr_FullScanAbort (
                    string.format (
                        "Full Scan paused: no response for page %d after %d retries.",
                        gAtr_FullScanPage + 1,
                        ATR_FULLSCAN_MAX_PAGE_RETRIES
                    )
                );

                return;
            end

            gAtr_FullScanAwaitingResponse =
                false;

            gAtr_FullScanQuerySentAt =
                nil;

            Atr_FullScanStatus:SetText (
                string.format (
                    "Retry pg %d/%d | no response %d/%d",
                    gAtr_FullScanPage + 1,
                    gAtr_FullScanTotalPages,
                    gAtr_FullScanPageRetries,
                    ATR_FULLSCAN_MAX_PAGE_RETRIES
                )
            );

            Atr_FullScanSendPage();

        end

    -- ==========================================================
    -- Final database / history build
    -- ==========================================================
    elseif (
        gAtr_FullScanState
        == ATR_FS_ANALYZING
    ) then

        Atr_FullScanProcessDatabaseChunk();

    -- ==========================================================
    -- Finished
    -- ==========================================================
    elseif (
        gAtr_FullScanState
        == ATR_FS_CLEANING_UP
    ) then

        local completedText =
            Atr_FullScanStatus:GetText();

        gAtr_FullScanState =
            ATR_FS_NULL;

        gAtr_FullScanSubState =
            ATR_FSS_NULL;

        Atr_UpdateFullScanFrame();

        if (completedText) then
            Atr_FullScanStatus:SetText (
                completedText
            );
        end

    end

end