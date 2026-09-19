-- v1.0.1 - Smart Quick Refresh + disenchant pricing + sell recommendations + database controls
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

-- ==========================================================
-- v1.0.1 Quick Refresh / market metadata
-- ==========================================================
--
-- Quick Refresh is deliberately separate from Full Scan.
-- Full Scan remains the market-wide baseline, while Quick Refresh
-- asks the AH only about items that are immediately useful to the
-- player: bags, a cached bank snapshot, shopping lists and recent
-- exact item searches.
--
-- The bank cannot normally be open at the same time as the Auction
-- House. For that reason we snapshot auctionable bank item names when
-- the bank is opened and reuse that snapshot later at the AH.
-- ==========================================================

local ATR_MARKET_META_KEY                  = "MARKET_ITEM_META_V1";
local ATR_QUICK_BANK_CACHE_KEY             = "QUICK_REFRESH_BANK_CACHE_V1";
local ATR_QUICK_RESPONSE_TIMEOUT           = 15.00;
local ATR_QUICK_STALE_POLL_TIMEOUT         = 1.25;
local ATR_QUICK_MAX_RETRIES                = 6;
local ATR_QUICK_ETA_SAMPLE_COUNT           = 15;

-- Reuse recently checked prices instead of querying Warmane again.
-- This is the main reason repeated Quick Refreshes can complete much
-- faster than the first run.
local ATR_QUICK_FRESH_SECONDS              = 15 * 60;

local gAtr_QuickRefreshActive              = false;
local gAtr_QuickRefreshQueue               = {};
local gAtr_QuickRefreshIndex               = 1;
local gAtr_QuickRefreshPage                = 0;
local gAtr_QuickRefreshAwaitingResponse    = false;
local gAtr_QuickRefreshQuerySentAt         = nil;
local gAtr_QuickRefreshStaleStartedAt      = nil;
local gAtr_QuickRefreshRetries             = 0;
local gAtr_QuickRefreshLastSignature       = nil;
local gAtr_QuickRefreshLowprices           = nil;
local gAtr_QuickRefreshQuality             = nil;
local gAtr_QuickRefreshItemStartedAt       = nil;
local gAtr_QuickRefreshStartedAt           = nil;
local gAtr_QuickRefreshDurations           = {};
local gAtr_QuickRefreshUpdated             = 0;
local gAtr_QuickRefreshAdded               = 0;
local gAtr_QuickRefreshUnchanged           = 0;
local gAtr_QuickRefreshNoAuctions          = 0;
local gAtr_QuickRefreshSkipped             = 0;
local gAtr_QuickRefreshFreshSkipped        = 0;
local gAtr_QuickRefreshCandidateCount      = 0;
local gAtr_QuickRefreshBankOpen            = false;
local gAtr_QuickRefreshDEMaterialCount      = 0;

-- ==========================================================
-- Disenchant material support
-- ==========================================================
--
-- Auctionator's existing disenchant calculator values an item
-- by looking up the current AH prices of the possible dusts,
-- essences, shards and crystals. A narrow Quick Refresh can
-- therefore leave "Disenchant: unknown" even when the equipment
-- itself has just been refreshed.
--
-- Include the standard Vanilla / TBC / WotLK disenchant materials
-- in Quick Refresh so AuctionatorHints.lua can use its ORIGINAL
-- disenchant formula without any changes to that file.
--
-- IDs are preferred so localized clients can resolve their own
-- names. English names are retained as a fallback when an item is
-- not yet present in the local item cache.
-- ==========================================================

local ATR_QUICK_DE_MATERIALS = {
    { id = 10938, name = "Lesser Magic Essence" },
    { id = 10939, name = "Greater Magic Essence" },
    { id = 10940, name = "Strange Dust" },
    { id = 10978, name = "Small Glimmering Shard" },
    { id = 10998, name = "Lesser Astral Essence" },
    { id = 11082, name = "Greater Astral Essence" },
    { id = 11083, name = "Soul Dust" },
    { id = 11084, name = "Large Glimmering Shard" },
    { id = 11134, name = "Lesser Mystic Essence" },
    { id = 11135, name = "Greater Mystic Essence" },
    { id = 11137, name = "Vision Dust" },
    { id = 11138, name = "Small Glowing Shard" },
    { id = 11139, name = "Large Glowing Shard" },
    { id = 11174, name = "Lesser Nether Essence" },
    { id = 11175, name = "Greater Nether Essence" },
    { id = 11176, name = "Dream Dust" },
    { id = 11177, name = "Small Radiant Shard" },
    { id = 11178, name = "Large Radiant Shard" },
    { id = 14343, name = "Small Brilliant Shard" },
    { id = 14344, name = "Large Brilliant Shard" },
    { id = 16202, name = "Lesser Eternal Essence" },
    { id = 16203, name = "Greater Eternal Essence" },
    { id = 16204, name = "Illusion Dust" },
    { id = 20725, name = "Nexus Crystal" },
    { id = 22445, name = "Arcane Dust" },
    { id = 22446, name = "Greater Planar Essence" },
    { id = 22447, name = "Lesser Planar Essence" },
    { id = 22448, name = "Small Prismatic Shard" },
    { id = 22449, name = "Large Prismatic Shard" },
    { id = 22450, name = "Void Crystal" },
    { id = 34052, name = "Dream Shard" },
    { id = 34053, name = "Small Dream Shard" },
    { id = 34054, name = "Infinite Dust" },
    { id = 34055, name = "Greater Cosmic Essence" },
    { id = 34056, name = "Lesser Cosmic Essence" },
    { id = 34057, name = "Abyss Crystal" }
};

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
-- Market metadata helpers
-----------------------------------------

local function Atr_MarketMetaGetScopeKey ()

    local realm, faction = Atr_FullScanGetScope();

    return tostring(realm)
        .. "|"
        .. tostring(faction);
end

-----------------------------------------

local function Atr_MarketMetaGetStore ()

    Atr_FullScanEnsureSavedVars();

    local root = AUCTIONATOR_SAVEDVARS[ATR_MARKET_META_KEY];

    if (type(root) ~= "table" or root.version ~= 1) then

        root = {
            version = 1,
            scopes = {}
        };

        AUCTIONATOR_SAVEDVARS[ATR_MARKET_META_KEY] = root;
    end

    if (type(root.scopes) ~= "table") then
        root.scopes = {};
    end

    local scopeKey = Atr_MarketMetaGetScopeKey();

    if (type(root.scopes[scopeKey]) ~= "table") then
        root.scopes[scopeKey] = {};
    end

    return root.scopes[scopeKey];
end

-----------------------------------------

local function Atr_MarketMetaMarkSeen (name, price, source)

    if (not name or not price or price <= 0) then
        return;
    end

    local store = Atr_MarketMetaGetStore();
    local meta = store[name];

    if (type(meta) ~= "table") then
        meta = {};
        store[name] = meta;
    end

    if (
        meta.currentPrice
        and meta.currentPrice ~= price
    ) then
        meta.previousPrice = meta.currentPrice;
    end

    meta.currentPrice = price;
    meta.lastSeen = time();
    meta.lastChecked = time();
    meta.stale = false;
    meta.source = source or "scan";
end

-----------------------------------------

local function Atr_MarketMetaMarkMissing (name, source)

    if (not name) then
        return;
    end

    local store = Atr_MarketMetaGetStore();
    local meta = store[name];

    if (type(meta) ~= "table") then
        meta = {};
        store[name] = meta;
    end

    -- Keep the last known price. Auctionator intentionally uses its
    -- historical database when there are no current auctions, so a
    -- missing item is marked stale rather than deleting useful data.
    meta.lastChecked = time();
    meta.stale = true;
    meta.source = source or "scan";
end

-----------------------------------------

local function Atr_MarketMetaMarkFullScanStale ()

    if (not gAtr_FullScanLowprices) then
        return;
    end

    local name;

    for name in pairs (gAtr_ScanDB) do

        if (not gAtr_FullScanLowprices[name]) then
            Atr_MarketMetaMarkMissing (name, "full");
        end
    end
end

-----------------------------------------

local function Atr_QuickRefreshIsFresh (name)

    if (
        not name
        or type(AUCTIONATOR_SAVEDVARS) ~= "table"
    ) then
        return false;
    end

    local root =
        AUCTIONATOR_SAVEDVARS[ATR_MARKET_META_KEY];

    if (
        type(root) ~= "table"
        or root.version ~= 1
        or type(root.scopes) ~= "table"
    ) then
        return false;
    end

    local store =
        root.scopes[
            Atr_MarketMetaGetScopeKey()
        ];

    if (type(store) ~= "table") then
        return false;
    end

    local meta = store[name];

    if (
        type(meta) ~= "table"
        or not meta.lastChecked
    ) then
        return false;
    end

    local checkedAt =
        tonumber (meta.lastChecked);

    if (not checkedAt) then
        return false;
    end

    local age =
        time() - checkedAt;

    return (
        age >= 0
        and age < ATR_QUICK_FRESH_SECONDS
    );
end

-----------------------------------------
-- Cached bank snapshot helpers
-----------------------------------------

local function Atr_QuickRefreshGetCharacterScopeKey ()

    local realm, faction = Atr_FullScanGetScope();
    local player = UnitName and UnitName("player") or "";

    return tostring(realm)
        .. "|"
        .. tostring(faction)
        .. "|"
        .. tostring(player or "");
end

-----------------------------------------

local function Atr_QuickRefreshGetBankCacheRoot ()

    Atr_FullScanEnsureSavedVars();

    local root =
        AUCTIONATOR_SAVEDVARS[ATR_QUICK_BANK_CACHE_KEY];

    if (type(root) ~= "table" or root.version ~= 1) then

        root = {
            version = 1,
            characters = {}
        };

        AUCTIONATOR_SAVEDVARS[ATR_QUICK_BANK_CACHE_KEY] = root;
    end

    if (type(root.characters) ~= "table") then
        root.characters = {};
    end

    return root;
end

-----------------------------------------

local function Atr_QuickRefreshGetBankCache ()

    if (type(AUCTIONATOR_SAVEDVARS) ~= "table") then
        return nil;
    end

    local root =
        AUCTIONATOR_SAVEDVARS[ATR_QUICK_BANK_CACHE_KEY];

    if (
        type(root) ~= "table"
        or root.version ~= 1
        or type(root.characters) ~= "table"
    ) then
        return nil;
    end

    return root.characters[
        Atr_QuickRefreshGetCharacterScopeKey()
    ];
end

-----------------------------------------

local function Atr_QuickRefreshIsBagItemAuctionable (
    bag,
    slot,
    link,
    quality
)

    if (not link) then
        return false;
    end

    if (Atr_IsItemSellableOnAH) then

        local ok, result = pcall (
            Atr_IsItemSellableOnAH,
            bag,
            slot,
            link,
            quality
        );

        if (ok) then
            return result and true or false;
        end
    end

    -- If the optional Auctionator helper is unavailable, keep the
    -- item. The AH query itself is still read-only and safe.
    return true;
end

-----------------------------------------

local function Atr_QuickRefreshSnapshotBank ()

    if (not gAtr_QuickRefreshBankOpen) then
        return;
    end

    local items = {};
    local seen = {};

    local function addContainer (bag)

        local numSlots = GetContainerNumSlots (bag) or 0;
        local slot;

        for slot = 1, numSlots do

            local texture, count, locked, quality,
                readable, lootable, itemLink =
                GetContainerItemInfo (bag, slot);

            local link =
                itemLink or GetContainerItemLink (bag, slot);

            if (
                link
                and Atr_QuickRefreshIsBagItemAuctionable (
                    bag,
                    slot,
                    link,
                    quality
                )
            ) then

                local itemName, canonicalLink =
                    GetItemInfo (link);

                if (itemName) then

                    local key = string.lower (itemName);

                    if (not seen[key]) then

                        seen[key] = true;

                        table.insert (
                            items,
                            {
                                name = itemName,
                                link = canonicalLink or link
                            }
                        );
                    end
                end
            end
        end
    end

    addContainer (BANK_CONTAINER or -1);

    local firstBankBag = (NUM_BAG_SLOTS or 4) + 1;
    local bankBagCount = NUM_BANKBAGSLOTS or 7;
    local bag;

    for bag = firstBankBag, firstBankBag + bankBagCount - 1 do
        addContainer (bag);
    end

    local root = Atr_QuickRefreshGetBankCacheRoot();

    root.characters[
        Atr_QuickRefreshGetCharacterScopeKey()
    ] = {
        updatedAt = time(),
        items = items
    };
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
-- Quick Refresh engine
-----------------------------------------

local function Atr_QuickRefreshNamesSame (a, b)

    if (not a or not b) then
        return false;
    end

    if (zc and zc.StringSame) then
        return zc.StringSame (a, b);
    end

    return string.lower(a) == string.lower(b);
end

-----------------------------------------

local function Atr_QuickRefreshBuildEntry (name, link, source, forceInclude)

    if (not name and not link) then
        return nil;
    end

    local candidate = link or name;

    if (
        not link
        and Atr_GetItemLink
        and name
    ) then
        candidate = Atr_GetItemLink (name) or name;
    end

    local itemName, itemLink, quality,
        itemLevel, reqLevel, itemType, itemSubType =
        GetItemInfo (candidate);

    -- Shopping-list history can contain broad text searches. Only
    -- add normal entries that resolve to a real item so Quick Refresh
    -- does not accidentally turn into another market-wide scan.
    --
    -- Disenchant materials are a controlled built-in list, so they may
    -- fall back to the supplied name while the client item cache warms.
    if (not itemName or not itemLink) then

        if (
            forceInclude
            and type(name) == "string"
            and name ~= ""
        ) then

            itemName = name;
            itemLink = link;
            quality = quality or 1;

        else
            return nil;
        end
    end

    if (
        not forceInclude
        and quality ~= nil
        and AUCTIONATOR_SCAN_MINLEVEL
        and quality + 1 < AUCTIONATOR_SCAN_MINLEVEL
    ) then
        return nil;
    end

    local itemClass = 0;
    local itemSubclass = 0;

    if (itemType) then
        itemClass =
            Atr_ItemType2AuctionClass (itemType) or 0;
    end

    if (itemClass > 0 and itemSubType) then
        itemSubclass =
            Atr_SubType2AuctionSubclass (
                itemClass,
                itemSubType
            ) or 0;
    end

    return {
        name = itemName,
        link = itemLink,
        quality = quality,
        itemLevel = itemLevel,
        itemType = itemType,
        itemClass = itemClass,
        itemSubclass = itemSubclass,
        source = source
    };
end

-----------------------------------------
-- Determine which disenchant materials an item can produce
-----------------------------------------

local function Atr_QuickRefreshGetDEMaterialIDs (entry)

    local ids = {};

    if (
        not entry
        or not entry.quality
        or not entry.itemLevel
        or (
            entry.itemClass ~= AUCTION_CLASS_WEAPON
            and entry.itemClass ~= AUCTION_CLASS_ARMOR
        )
    ) then
        return ids;
    end

    local quality = entry.quality;
    local level = entry.itemLevel;

    -- ----------------------------------------------------------
    -- Uncommon / green
    -- ----------------------------------------------------------
    if (quality == 2) then

        if (level >= 5 and level <= 15) then
            return {10940, 10938}; -- Strange Dust, Lesser Magic
        elseif (level <= 20) then
            return {10940, 10939, 10978};
        elseif (level <= 25) then
            return {10940, 10998, 10978};
        elseif (level <= 30) then
            return {11083, 11082, 11084};
        elseif (level <= 35) then
            return {11083, 11134, 11138};
        elseif (level <= 40) then
            return {11137, 11135, 11139};
        elseif (level <= 45) then
            return {11137, 11174, 11177};
        elseif (level <= 50) then
            return {11176, 11175, 11178};
        elseif (level <= 55) then
            return {11176, 16202, 14343};
        elseif (level <= 65) then
            return {16204, 16203, 14344};
        elseif (level <= 99) then
            return {22445, 22447, 22448};
        elseif (level <= 120) then
            return {22445, 22446, 22449};
        elseif (level <= 151) then
            return {34054, 34056, 34053};
        elseif (level <= 200) then
            return {34054, 34055, 34052};
        end

    -- ----------------------------------------------------------
    -- Rare / blue
    -- ----------------------------------------------------------
    elseif (quality == 3) then

        if (level >= 11 and level <= 25) then
            return {10978};
        elseif (level >= 26 and level <= 30) then
            return {11084};
        elseif (level >= 31 and level <= 35) then
            return {11138};
        elseif (level >= 36 and level <= 40) then
            return {11139};
        elseif (level >= 41 and level <= 45) then
            return {11177};
        elseif (level >= 46 and level <= 50) then
            return {11178};
        elseif (level >= 51 and level <= 55) then
            return {14343};
        elseif (level >= 56 and level <= 65) then
            return {14344, 20725};
        elseif (level >= 66 and level <= 99) then
            return {22448, 20725};
        elseif (level >= 100 and level <= 120) then
            return {22449, 22450};
        elseif (level >= 121 and level <= 164) then
            return {34053, 34057};
        elseif (level >= 165) then
            return {34052, 34057};
        end

    -- ----------------------------------------------------------
    -- Epic / purple
    -- ----------------------------------------------------------
    elseif (quality == 4) then

        if (level >= 40 and level <= 45) then
            return {11177};
        elseif (level >= 46 and level <= 50) then
            return {11178};
        elseif (level >= 51 and level <= 55) then
            return {14343};
        elseif (level >= 56 and level <= 80) then
            return {20725};
        elseif (level >= 95 and level <= 100) then
            return {22450};
        elseif (level >= 105 and level <= 164) then
            return {22450};
        elseif (level >= 165) then
            return {34057};
        end
    end

    return ids;
end

-----------------------------------------

local function Atr_QuickRefreshBuildQueue ()

    local queue = {};
    local seen = {};
    local requiredDEMaterials = {};

    local function rememberDEMaterials (entry)

        if (
            not entry
            or entry.source == "disenchant-material"
        ) then
            return;
        end

        local ids =
            Atr_QuickRefreshGetDEMaterialIDs (
                entry
            );

        local _, itemID;

        for _, itemID in ipairs (ids) do
            requiredDEMaterials[itemID] = true;
        end
    end

    local function add (
        name,
        link,
        source,
        forceInclude
    )

        local entry =
            Atr_QuickRefreshBuildEntry (
                name,
                link,
                source,
                forceInclude
            );

        if (not entry) then
            return false;
        end

        local key =
            string.lower (entry.name);

        if (seen[key]) then
            return false;
        end

        -- Mark the item as seen before applying freshness. A duplicate
        -- from another source should not be queried simply because the
        -- first copy was already fresh.
        seen[key] = true;

        gAtr_QuickRefreshCandidateCount =
            gAtr_QuickRefreshCandidateCount + 1;

        -- Even if the equipment itself is still fresh, its possible
        -- disenchant outputs may not be. Work out those dependencies
        -- before deciding whether this entry needs an AH query.
        rememberDEMaterials (entry);

        if (
            Atr_QuickRefreshIsFresh (
                entry.name
            )
        ) then

            gAtr_QuickRefreshFreshSkipped =
                gAtr_QuickRefreshFreshSkipped + 1;

            return false;
        end

        table.insert (
            queue,
            entry
        );

        return true;
    end

    -- ----------------------------------------------------------
    -- Current bags
    -- ----------------------------------------------------------
    local bag;

    for bag = 0, (NUM_BAG_SLOTS or 4) do

        local numSlots =
            GetContainerNumSlots (bag) or 0;

        local slot;

        for slot = 1, numSlots do

            local texture, count, locked, quality,
                readable, lootable, itemLink =
                GetContainerItemInfo (
                    bag,
                    slot
                );

            local link =
                itemLink
                or GetContainerItemLink (
                    bag,
                    slot
                );

            if (
                link
                and Atr_QuickRefreshIsBagItemAuctionable (
                    bag,
                    slot,
                    link,
                    quality
                )
            ) then

                add (
                    nil,
                    link,
                    "bag"
                );
            end
        end
    end

    -- ----------------------------------------------------------
    -- Last bank snapshot
    -- ----------------------------------------------------------
    local bankCache =
        Atr_QuickRefreshGetBankCache();

    if (
        bankCache
        and type(bankCache.items) == "table"
    ) then

        local _, bankItem;

        for _, bankItem in ipairs (bankCache.items) do

            if (type(bankItem) == "table") then

                add (
                    bankItem.name,
                    bankItem.link,
                    "bank"
                );
            end
        end
    end

    -- ----------------------------------------------------------
    -- Shopping lists + Recent Searches
    -- ----------------------------------------------------------
    if (type(AUCTIONATOR_SHOPPING_LISTS) == "table") then

        local _, slist;

        for _, slist in ipairs (
            AUCTIONATOR_SHOPPING_LISTS
        ) do

            if (
                type(slist) == "table"
                and type(slist.items) == "table"
            ) then

                local _, itemName;

                for _, itemName in ipairs (
                    slist.items
                ) do

                    add (
                        itemName,
                        nil,
                        "list"
                    );
                end
            end
        end
    end

    -- ----------------------------------------------------------
    -- Only the disenchant materials actually required by the
    -- equipment above.
    -- ----------------------------------------------------------
    --
    -- Walk the master catalogue in its stable order, but enqueue
    -- only IDs referenced by the relevant green/blue/purple gear.
    local _, material;

    for _, material in ipairs (
        ATR_QUICK_DE_MATERIALS
    ) do

        if (
            requiredDEMaterials[material.id]
        ) then

            local materialName, materialLink =
                GetItemInfo (material.id);

            if (
                not materialName
                and AtrScanningTooltip
                and AtrScanningTooltip.SetHyperlink
            ) then

                pcall (
                    AtrScanningTooltip.SetHyperlink,
                    AtrScanningTooltip,
                    "item:"
                        .. tostring(material.id)
                        .. ":0:0:0:0:0:0:0"
                );

                materialName, materialLink =
                    GetItemInfo (material.id);
            end

            local before = #queue;

            add (
                materialName or material.name,
                materialLink,
                "disenchant-material",
                true
            );

            if (#queue > before) then

                gAtr_QuickRefreshDEMaterialCount =
                    gAtr_QuickRefreshDEMaterialCount + 1;
            end
        end
    end

    return queue;
end

-----------------------------------------

local function Atr_QuickRefreshPageSignature (numBatchAuctions)

    if (not numBatchAuctions or numBatchAuctions <= 0) then
        return "empty";
    end

    local middle = math.floor ((numBatchAuctions + 1) / 2);
    local indexes = {1, middle, numBatchAuctions};
    local parts = { tostring(numBatchAuctions) };
    local i;

    for i = 1, #indexes do

        local x = indexes[i];

        local name, texture, count, quality, canUse, level,
            minBid, minIncrement, buyoutPrice, bidAmount,
            highBidder, owner =
            GetAuctionItemInfo ("list", x);

        table.insert (
            parts,
            tostring(name or "?")
            .. "/" .. tostring(count or 0)
            .. "/" .. tostring(buyoutPrice or 0)
            .. "/" .. tostring(bidAmount or 0)
            .. "/" .. tostring(owner or "?")
        );
    end

    return table.concat (parts, "|");
end

-----------------------------------------

local function Atr_QuickRefreshCurrentEntry ()

    return gAtr_QuickRefreshQueue[
        gAtr_QuickRefreshIndex
    ];
end

-----------------------------------------

local function Atr_QuickRefreshAverageItemSeconds ()

    if (#gAtr_QuickRefreshDurations == 0) then
        return nil;
    end

    local total = 0;
    local i;

    for i = 1, #gAtr_QuickRefreshDurations do
        total = total + gAtr_QuickRefreshDurations[i];
    end

    return total / #gAtr_QuickRefreshDurations;
end

-----------------------------------------

local function Atr_QuickRefreshUpdateStatus ()

    if (not Atr_FullScanStatus) then
        return;
    end

    local entry = Atr_QuickRefreshCurrentEntry();
    local total = #gAtr_QuickRefreshQueue;
    local average = Atr_QuickRefreshAverageItemSeconds();
    local eta = "calculating...";

    if (average and average > 0) then

        local remainingItems =
            math.max (0, total - gAtr_QuickRefreshIndex);

        eta = Atr_FullScanFormatRemaining (
            average * remainingItems
        );
    end

    local itemText =
        entry and entry.name or "Finishing...";

    if (
        entry
        and entry.source == "disenchant-material"
    ) then
        itemText = itemText .. "  [DE material]";
    end

    Atr_FullScanStatus:SetText (
        string.format (
            "Quick Refresh: %d / %d\n%s\nRemaining: ~%s  |  %d fresh",
            math.min (gAtr_QuickRefreshIndex, total),
            total,
            itemText,
            eta,
            gAtr_QuickRefreshFreshSkipped
        )
    );

    if (Atr_FullScanDBsize) then
        Atr_FullScanDBsize:SetText (Atr_GetDBsize());
    end
end

-----------------------------------------

local function Atr_QuickRefreshResetItem ()

    gAtr_QuickRefreshPage = 0;
    gAtr_QuickRefreshAwaitingResponse = false;
    gAtr_QuickRefreshQuerySentAt = nil;
    gAtr_QuickRefreshStaleStartedAt = nil;
    gAtr_QuickRefreshRetries = 0;
    gAtr_QuickRefreshLowprices = {
        BIGNUM,
        BIGNUM,
        BIGNUM
    };
    gAtr_QuickRefreshQuality = nil;
    gAtr_QuickRefreshItemStartedAt = GetTime();
end

-----------------------------------------

local function Atr_QuickRefreshSendPage ()

    if (
        not gAtr_QuickRefreshActive
        or gAtr_FullScanState ~= ATR_FS_STARTED
        or gAtr_QuickRefreshAwaitingResponse
    ) then
        return false;
    end

    local entry = Atr_QuickRefreshCurrentEntry();

    if (not entry) then
        return false;
    end

    if (not CanSendAuctionQuery()) then
        return false;
    end

    if (BrowseName) then
        BrowseName:SetText (entry.name);
    end

    gAtr_QuickRefreshAwaitingResponse = true;
    gAtr_QuickRefreshQuerySentAt = GetTime();
    gAtr_QuickRefreshStaleStartedAt = nil;

    QueryAuctionItems (
        zc.UTF8_Truncate (entry.name, 63),
        nil,
        nil,
        nil,
        entry.itemClass or 0,
        entry.itemSubclass or 0,
        gAtr_QuickRefreshPage,
        nil,
        nil
    );

    return true;
end

-----------------------------------------

local function Atr_QuickRefreshFinishAll ()

    local elapsed = 0;

    if (gAtr_QuickRefreshStartedAt) then
        elapsed = GetTime() - gAtr_QuickRefreshStartedAt;
    end

    local total = #gAtr_QuickRefreshQueue;
    local elapsedText =
        Atr_FullScanFormatRemaining (elapsed);

    gAtr_QuickRefreshActive = false;
    gAtr_FullScanState = ATR_FS_NULL;
    gAtr_FullScanSubState = ATR_FSS_NULL;
    gAtr_QuickRefreshAwaitingResponse = false;
    gAtr_QuickRefreshQuerySentAt = nil;
    gAtr_QuickRefreshStaleStartedAt = nil;

    if (Atr_FullScanDone) then
        Atr_FullScanDone:Enable();
    end

    Atr_UpdateFullScanFrame();

    local normalItemCount =
        math.max (
            0,
            total - gAtr_QuickRefreshDEMaterialCount
        );

    Atr_FullScanStatus:SetText (
        string.format (
            "Quick Refresh complete\n%d queried + %d fresh in %s\n%d DE mats | Added %d | Changed %d | No AH %d",
            total,
            gAtr_QuickRefreshFreshSkipped,
            elapsedText,
            gAtr_QuickRefreshDEMaterialCount,
            gAtr_QuickRefreshAdded,
            gAtr_QuickRefreshUpdated,
            gAtr_QuickRefreshNoAuctions
        )
    );

    zc.msg_atr (
        string.format (
            "Quick Refresh complete: %d queries sent, %d recently checked prices reused, %d DE materials queried; %d added, %d changed, %d unchanged, %d with no current auctions.",
            total,
            gAtr_QuickRefreshFreshSkipped,
            gAtr_QuickRefreshDEMaterialCount,
            gAtr_QuickRefreshAdded,
            gAtr_QuickRefreshUpdated,
            gAtr_QuickRefreshUnchanged,
            gAtr_QuickRefreshNoAuctions
        )
    );

    collectgarbage ("collect");
end

-----------------------------------------

local function Atr_QuickRefreshStop (reason)

    gAtr_QuickRefreshActive = false;
    gAtr_FullScanState = ATR_FS_NULL;
    gAtr_FullScanSubState = ATR_FSS_NULL;
    gAtr_QuickRefreshAwaitingResponse = false;
    gAtr_QuickRefreshQuerySentAt = nil;
    gAtr_QuickRefreshStaleStartedAt = nil;

    if (Atr_FullScanDone) then
        Atr_FullScanDone:Enable();
    end

    Atr_UpdateFullScanFrame();

    if (reason and Atr_FullScanStatus) then
        Atr_FullScanStatus:SetText (reason);
        zc.msg_atr (reason);
    end
end

-----------------------------------------

local function Atr_QuickRefreshFinishItem ()

    local entry = Atr_QuickRefreshCurrentEntry();

    if (not entry) then
        Atr_QuickRefreshFinishAll();
        return;
    end

    local oldPrice = gAtr_ScanDB[entry.name];
    local newPrice =
        Atr_CalcNewDBprice (
            entry.name,
            gAtr_QuickRefreshLowprices
        );

    local quality =
        gAtr_QuickRefreshQuality;

    if (quality == nil) then
        quality = entry.quality;
    end

    local forceInclude =
        entry.source == "disenchant-material";

    if (
        newPrice > 0
        and quality ~= nil
        and (
            forceInclude
            or quality + 1 >= AUCTIONATOR_SCAN_MINLEVEL
        )
    ) then

        gAtr_ScanDB[entry.name] = newPrice;

        if (oldPrice == nil) then
            gAtr_QuickRefreshAdded =
                gAtr_QuickRefreshAdded + 1;

        elseif (oldPrice ~= newPrice) then
            gAtr_QuickRefreshUpdated =
                gAtr_QuickRefreshUpdated + 1;

        else
            gAtr_QuickRefreshUnchanged =
                gAtr_QuickRefreshUnchanged + 1;
        end

        Atr_MarketMetaMarkSeen (
            entry.name,
            newPrice,
            "quick"
        );

    elseif (newPrice <= 0) then

        -- Keep Auctionator's last known database value. The metadata
        -- records that the item was checked and had no current buyout,
        -- so future UI work can distinguish fresh from stale values.
        gAtr_QuickRefreshNoAuctions =
            gAtr_QuickRefreshNoAuctions + 1;

        Atr_MarketMetaMarkMissing (
            entry.name,
            "quick"
        );

    else

        gAtr_QuickRefreshSkipped =
            gAtr_QuickRefreshSkipped + 1;
    end

    if (gAtr_QuickRefreshItemStartedAt) then

        local duration =
            math.max (
                0.01,
                GetTime() - gAtr_QuickRefreshItemStartedAt
            );

        table.insert (
            gAtr_QuickRefreshDurations,
            duration
        );

        while (
            #gAtr_QuickRefreshDurations
            > ATR_QUICK_ETA_SAMPLE_COUNT
        ) do
            table.remove (
                gAtr_QuickRefreshDurations,
                1
            );
        end
    end

    gAtr_QuickRefreshIndex =
        gAtr_QuickRefreshIndex + 1;

    if (
        gAtr_QuickRefreshIndex
        > #gAtr_QuickRefreshQueue
    ) then
        Atr_QuickRefreshFinishAll();
        return;
    end

    Atr_QuickRefreshResetItem();
    Atr_QuickRefreshUpdateStatus();
    Atr_QuickRefreshSendPage();
end

-----------------------------------------

local function Atr_QuickRefreshAcceptPage (
    numBatchAuctions,
    totalAuctions
)

    local entry = Atr_QuickRefreshCurrentEntry();

    if (not entry) then
        Atr_QuickRefreshFinishAll();
        return;
    end

    local x;

    for x = 1, numBatchAuctions do

        local name, texture, count, quality, canUse, level,
            minBid, minIncrement, buyoutPrice =
            GetAuctionItemInfo ("list", x);

        if (
            name
            and Atr_QuickRefreshNamesSame (
                name,
                entry.name
            )
            and count
            and count > 0
            and buyoutPrice
            and buyoutPrice > 0
        ) then

            local itemPrice =
                math.floor (buyoutPrice / count);

            if (itemPrice > 0) then

                Atr_AddToLowPrices (
                    gAtr_QuickRefreshLowprices,
                    itemPrice
                );

                if (quality ~= nil) then
                    gAtr_QuickRefreshQuality = quality;
                end
            end
        end
    end

    gAtr_QuickRefreshRetries = 0;
    gAtr_QuickRefreshStaleStartedAt = nil;
    gAtr_QuickRefreshAwaitingResponse = false;

    local totalPages = 0;

    if (totalAuctions and totalAuctions > 0) then
        totalPages = math.ceil (
            totalAuctions / ATR_FULLSCAN_PAGE_SIZE
        );
    end

    local pageNumber =
        gAtr_QuickRefreshPage + 1;

    local done =
        numBatchAuctions < ATR_FULLSCAN_PAGE_SIZE;

    if (
        not done
        and totalPages > 0
        and pageNumber >= totalPages
    ) then
        done = true;
    end

    if (done) then
        Atr_QuickRefreshFinishItem();
        return;
    end

    gAtr_QuickRefreshPage =
        gAtr_QuickRefreshPage + 1;

    Atr_QuickRefreshUpdateStatus();
    Atr_QuickRefreshSendPage();
end

-----------------------------------------

local function Atr_QuickRefreshAnalyze ()

    if (
        not gAtr_QuickRefreshActive
        or not gAtr_QuickRefreshAwaitingResponse
    ) then
        return;
    end

    local numBatchAuctions, totalAuctions =
        GetNumAuctionItems ("list");

    if (
        numBatchAuctions == nil
        or totalAuctions == nil
    ) then
        return;
    end

    -- A genuine empty result is valid for Quick Refresh. It means
    -- there are currently no auctions for this item.
    if (
        numBatchAuctions == 0
        and totalAuctions == 0
    ) then

        gAtr_QuickRefreshLastSignature = "empty";

        Atr_QuickRefreshAcceptPage (
            numBatchAuctions,
            totalAuctions
        );

        return;
    end

    local signature =
        Atr_QuickRefreshPageSignature (
            numBatchAuctions
        );

    if (
        gAtr_QuickRefreshLastSignature ~= nil
        and gAtr_QuickRefreshLastSignature ~= "empty"
        and signature == gAtr_QuickRefreshLastSignature
    ) then

        if (not gAtr_QuickRefreshStaleStartedAt) then
            gAtr_QuickRefreshStaleStartedAt = GetTime();
        end

        return;
    end

    gAtr_QuickRefreshLastSignature = signature;

    Atr_QuickRefreshAcceptPage (
        numBatchAuctions,
        totalAuctions
    );
end

-----------------------------------------

local function Atr_QuickRefreshFrameIdle ()

    if (not gAtr_QuickRefreshActive) then
        return;
    end

    if (
        gAtr_QuickRefreshAwaitingResponse
        and gAtr_QuickRefreshStaleStartedAt
    ) then

        local numBatchAuctions, totalAuctions =
            GetNumAuctionItems ("list");

        if (
            numBatchAuctions ~= nil
            and totalAuctions ~= nil
        ) then

            if (
                numBatchAuctions == 0
                and totalAuctions == 0
            ) then

                gAtr_QuickRefreshLastSignature = "empty";

                Atr_QuickRefreshAcceptPage (
                    numBatchAuctions,
                    totalAuctions
                );

                return;
            end

            local signature =
                Atr_QuickRefreshPageSignature (
                    numBatchAuctions
                );

            if (
                signature
                ~= gAtr_QuickRefreshLastSignature
            ) then

                gAtr_QuickRefreshLastSignature =
                    signature;

                Atr_QuickRefreshAcceptPage (
                    numBatchAuctions,
                    totalAuctions
                );

                return;
            end
        end

        if (
            GetTime() - gAtr_QuickRefreshStaleStartedAt
            >= ATR_QUICK_STALE_POLL_TIMEOUT
        ) then

            gAtr_QuickRefreshRetries =
                gAtr_QuickRefreshRetries + 1;

            if (
                gAtr_QuickRefreshRetries
                > ATR_QUICK_MAX_RETRIES
            ) then

                Atr_QuickRefreshStop (
                    "Quick Refresh stopped: repeated stale AH responses."
                );

                return;
            end

            gAtr_QuickRefreshAwaitingResponse = false;
            gAtr_QuickRefreshStaleStartedAt = nil;
            gAtr_QuickRefreshQuerySentAt = nil;

            Atr_QuickRefreshSendPage();
            return;
        end

    elseif (
        gAtr_QuickRefreshAwaitingResponse
        and gAtr_QuickRefreshQuerySentAt
        and GetTime() - gAtr_QuickRefreshQuerySentAt
            >= ATR_QUICK_RESPONSE_TIMEOUT
    ) then

        gAtr_QuickRefreshRetries =
            gAtr_QuickRefreshRetries + 1;

        if (
            gAtr_QuickRefreshRetries
            > ATR_QUICK_MAX_RETRIES
        ) then

            Atr_QuickRefreshStop (
                "Quick Refresh stopped: Warmane stopped responding to AH queries."
            );

            return;
        end

        gAtr_QuickRefreshAwaitingResponse = false;
        gAtr_QuickRefreshQuerySentAt = nil;

        Atr_QuickRefreshSendPage();
        return;

    elseif (not gAtr_QuickRefreshAwaitingResponse) then

        Atr_QuickRefreshSendPage();
    end
end

-----------------------------------------
-- Scrollable Full Scan help
-----------------------------------------

local function Atr_FullScanEnsureHelpScroll ()

    local existing =
        _G["Atr_FullScanHelpScroll"];

    if (existing) then
        return existing;
    end

    local scroll = CreateFrame (
        "ScrollFrame",
        "Atr_FullScanHelpScroll",
        Atr_FullScanFrame,
        "UIPanelScrollFrameTemplate"
    );

    scroll:SetPoint (
        "TOPLEFT",
        Atr_FullScanFrame,
        "TOPLEFT",
        27,
        -220
    );

    scroll:SetWidth (385);
    scroll:SetHeight (175);

    local child = CreateFrame (
        "Frame",
        "Atr_FullScanHelpScrollChild",
        scroll
    );

    child:SetWidth (355);
    child:SetHeight (175);

    scroll:SetScrollChild (child);

    local helpText = child:CreateFontString (
        "Atr_FullScanHelpText",
        "ARTWORK",
        "GameFontLightGraySmall"
    );

    helpText:SetPoint (
        "TOPLEFT",
        child,
        "TOPLEFT",
        0,
        0
    );

    helpText:SetWidth (355);
    helpText:SetJustifyH ("LEFT");
    helpText:SetJustifyV ("TOP");

    scroll:EnableMouseWheel (true);

    scroll:SetScript (
        "OnMouseWheel",
        function (self, delta)

            local current =
                self:GetVerticalScroll() or 0;

            local maximum =
                self:GetVerticalScrollRange() or 0;

            local nextScroll =
                current - (delta * 30);

            if (nextScroll < 0) then
                nextScroll = 0;
            elseif (nextScroll > maximum) then
                nextScroll = maximum;
            end

            self:SetVerticalScroll (
                nextScroll
            );
        end
    );

    return scroll;
end

-----------------------------------------

local function Atr_FullScanUpdateHelpText ()

    local scroll =
        Atr_FullScanEnsureHelpScroll();

    local child =
        _G["Atr_FullScanHelpScrollChild"];

    local helpText =
        _G["Atr_FullScanHelpText"];

    if (
        not scroll
        or not child
        or not helpText
    ) then
        return;
    end

    local help =
        "Full Scan scans the entire Auction House and builds Auctionator's broad price database."
        .. "\n\n"
        .. "If a Full Scan is interrupted, its progress is saved. Resume Scan continues from the saved page instead of starting again."
        .. "\n\n"
        .. "Quick Refresh updates exact items from your bags, cached bank contents, shopping lists and Recent Searches. It only adds disenchant materials relevant to that equipment, and prices checked within the last 15 minutes are reused instead of querying Warmane again. It can be used while a Full Scan is paused without deleting the saved Full Scan progress."
        .. "\n\n"
        .. "Clear DB removes the current realm/faction scan price database so you can rebuild only the items you care about with Quick Refresh. It also discards any saved Resume Scan checkpoint."
        .. "\n\n"
        .. "Open your bank once to refresh the bank cache. Shift-click Resume Scan if you intentionally want to discard the saved Full Scan and start over.";

    helpText:SetText (help);

    local textHeight =
        helpText:GetStringHeight() or 0;

    child:SetHeight (
        math.max (
            175,
            textHeight + 12
        )
    );

    scroll:SetVerticalScroll (0);
end

-----------------------------------------
-- Clear price database
-----------------------------------------

local function Atr_ClearDatabaseTable (db)

    if (type(db) ~= "table") then
        return;
    end

    local key;

    for key in pairs (db) do
        db[key] = nil;
    end
end

-----------------------------------------

local function Atr_ClearDatabaseCurrentScopeMetadata ()

    if (type(AUCTIONATOR_SAVEDVARS) ~= "table") then
        return;
    end

    local root =
        AUCTIONATOR_SAVEDVARS[ATR_MARKET_META_KEY];

    if (
        type(root) == "table"
        and type(root.scopes) == "table"
    ) then

        root.scopes[
            Atr_MarketMetaGetScopeKey()
        ] = nil;
    end
end

-----------------------------------------

local function Atr_ClearDatabaseNow ()

    -- Never allow a destructive clear while an AH query sequence is
    -- actively running.
    if (
        gAtr_FullScanState ~= ATR_FS_NULL
        or gAtr_QuickRefreshActive
    ) then

        Atr_FullScanStatus:SetText (
            "Wait for the current scan to finish or pause it before clearing the database."
        );

        return;
    end

    -- Clear the current realm/faction price tables in-place so the
    -- existing gAtr_ScanDB / gAtr_MeanDB references remain valid.
    Atr_ClearDatabaseTable (gAtr_ScanDB);
    Atr_ClearDatabaseTable (gAtr_MeanDB);

    -- Remove metadata that belongs to the cleared price database.
    Atr_ClearDatabaseCurrentScopeMetadata();

    -- A saved Full Scan contains prices gathered before this clear.
    -- Discard it as well, otherwise Resume Scan could repopulate old
    -- partial data immediately after the user intentionally cleared it.
    Atr_FullScanClearCheckpoint();

    -- Clear any in-memory scan objects that may still contain prices
    -- from before the database reset.
    if (Atr_ClearScanCache) then
        Atr_ClearScanCache();
    end

    Atr_FullScanResetRuntime();

    gAtr_FullScanStart = nil;
    gAtr_FullScanDur = nil;
    AUCTIONATOR_LAST_SCAN_TIME = nil;

    if (Atr_FullScanResults) then
        Atr_FullScanResults:Hide();
    end

    if (Atr_FullScanHTML) then
        Atr_FullScanHTML:Hide();
    end

    local helpScroll =
        Atr_FullScanEnsureHelpScroll();

    Atr_FullScanUpdateHelpText();
    helpScroll:Show();

    Atr_UpdateFullScanFrame();

    if (Atr_FullScanStatus) then

        Atr_FullScanStatus:SetText (
            "Database cleared\n0 items in price database\nUse Quick Refresh or Start Scanning"
        );

    end

    zc.msg_atr (
        "Auctionator scan database cleared for this realm/faction. Shopping lists, Recent Searches and the bank cache were kept."
    );

    collectgarbage ("collect");
end

-----------------------------------------

local function Atr_ClearDatabaseShowConfirm ()

    if (
        gAtr_FullScanState ~= ATR_FS_NULL
        or gAtr_QuickRefreshActive
    ) then

        Atr_FullScanStatus:SetText (
            "Wait for the current scan to finish or pause it before clearing the database."
        );

        return;
    end

    if (not StaticPopupDialogs["ATR_CLEAR_SCAN_DATABASE"]) then

        StaticPopupDialogs["ATR_CLEAR_SCAN_DATABASE"] = {
            text = "",
            button1 = YES,
            button2 = NO,

            OnAccept = function ()
                Atr_ClearDatabaseNow();
            end,

            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1
        };
    end

    local warning =
        "Clear Auctionator's scan price database for this realm/faction?\n\n"
        .. "This clears Full Scan / Quick Refresh price data and mean-price data. "
        .. "Shopping lists, Recent Searches, normal pricing history and the cached bank list are kept.";

    if (Atr_FullScanGetCheckpoint()) then

        warning = warning
            .. "\n\nThe saved Resume Scan checkpoint will also be discarded.";

    end

    StaticPopupDialogs[
        "ATR_CLEAR_SCAN_DATABASE"
    ].text = warning;

    StaticPopup_Show (
        "ATR_CLEAR_SCAN_DATABASE"
    );
end

-----------------------------------------

local function Atr_ClearDatabaseEnsureButton ()

    if (_G["Atr_ClearDatabaseButton"]) then
        return _G["Atr_ClearDatabaseButton"];
    end

    local button = CreateFrame (
        "Button",
        "Atr_ClearDatabaseButton",
        Atr_FullScanFrame,
        "UIPanelButtonTemplate"
    );

    button:SetWidth (80);
    button:SetHeight (22);
    button:SetPoint (
        "TOPRIGHT",
        Atr_FullScanFrame,
        "TOPRIGHT",
        -30,
        -185
    );
    button:SetText ("Clear DB");

    button:SetScript (
        "OnClick",
        function ()
            Atr_ClearDatabaseShowConfirm();
        end
    );

    button:SetScript (
        "OnEnter",
        function (self)

            GameTooltip:SetOwner (self, "ANCHOR_RIGHT");
            GameTooltip:SetText ("Clear Database");

            GameTooltip:AddLine (
                "Clears Auctionator's scan price database and mean-price database for this realm/faction.",
                1,
                1,
                1,
                true
            );

            GameTooltip:AddLine (
                "Shopping lists, Recent Searches, normal pricing history and the cached bank list are kept.",
                0.75,
                0.75,
                0.75,
                true
            );

            if (Atr_FullScanGetCheckpoint()) then

                GameTooltip:AddLine (
                    "The saved Resume Scan checkpoint will also be discarded.",
                    1,
                    0.35,
                    0.35,
                    true
                );

            end

            GameTooltip:Show();
        end
    );

    button:SetScript (
        "OnLeave",
        function ()
            GameTooltip:Hide();
        end
    );

    return button;
end

-----------------------------------------

local function Atr_QuickRefreshEnsureButton ()

    if (_G["Atr_QuickRefreshButton"]) then
        return _G["Atr_QuickRefreshButton"];
    end

    local button = CreateFrame (
        "Button",
        "Atr_QuickRefreshButton",
        Atr_FullScanFrame,
        "UIPanelButtonTemplate"
    );

    button:SetWidth (120);
    button:SetHeight (22);
    button:SetPoint (
        "TOPRIGHT",
        Atr_FullScanFrame,
        "TOPRIGHT",
        -114,
        -185
    );
    button:SetText ("Quick Refresh");

    button:SetScript (
        "OnClick",
        function ()
            Atr_QuickRefreshStart();
        end
    );

    button:SetScript (
        "OnEnter",
        function (self)

            GameTooltip:SetOwner (self, "ANCHOR_RIGHT");
            GameTooltip:SetText ("Quick Refresh");
            GameTooltip:AddLine (
                "Refreshes exact items from bags, cached bank contents, shopping lists and Recent Searches. Only relevant disenchant materials are added, and prices checked within 15 minutes are reused without another AH query.",
                1,
                1,
                1,
                true
            );

            if (Atr_FullScanGetCheckpoint()) then

                GameTooltip:AddLine (
                    "A paused Full Scan is saved. Quick Refresh will not discard or advance that checkpoint.",
                    0.35,
                    1,
                    0.35,
                    true
                );

            end

            local bankCache =
                Atr_QuickRefreshGetBankCache();

            if (
                bankCache
                and bankCache.updatedAt
                and type(bankCache.items) == "table"
            ) then

                local age =
                    math.max (
                        0,
                        time() - bankCache.updatedAt
                    );

                GameTooltip:AddLine (
                    string.format (
                        "Bank cache: %d items, captured %s ago.",
                        #bankCache.items,
                        Atr_FullScanFormatRemaining (age)
                    ),
                    0.75,
                    0.75,
                    0.75,
                    true
                );

            else

                GameTooltip:AddLine (
                    "Bank cache: not captured yet. Open your bank once to populate it.",
                    0.75,
                    0.75,
                    0.75,
                    true
                );
            end

            GameTooltip:Show();
        end
    );

    button:SetScript (
        "OnLeave",
        function ()
            GameTooltip:Hide();
        end
    );

    return button;
end

-----------------------------------------

function Atr_QuickRefreshStart ()

    if (gAtr_FullScanState ~= ATR_FS_NULL) then
        return;
    end

    if (
        gCurrentPane
        and gCurrentPane.activeSearch
        and gCurrentPane.activeSearch.processing_state
        and gCurrentPane.activeSearch.processing_state
            ~= KM_NULL_STATE
    ) then

        Atr_FullScanStatus:SetText (
            "Please wait for the current Auctionator search to finish."
        );

        return;
    end

    if (not CanSendAuctionQuery()) then

        Atr_FullScanStatus:SetText (
            "Waiting for auction query..."
        );

        return;
    end

    gAtr_QuickRefreshDEMaterialCount = 0;
    gAtr_QuickRefreshFreshSkipped = 0;
    gAtr_QuickRefreshCandidateCount = 0;

    gAtr_QuickRefreshQueue =
        Atr_QuickRefreshBuildQueue();

    if (#gAtr_QuickRefreshQueue == 0) then

        if (gAtr_QuickRefreshFreshSkipped > 0) then

            Atr_FullScanStatus:SetText (
                string.format (
                    "Quick Refresh complete\n%d prices are still fresh\nNo Warmane queries needed",
                    gAtr_QuickRefreshFreshSkipped
                )
            );

            zc.msg_atr (
                string.format (
                    "Quick Refresh: %d items were checked recently enough to reuse; no Auction House queries were needed.",
                    gAtr_QuickRefreshFreshSkipped
                )
            );

        else

            Atr_FullScanStatus:SetText (
                "Quick Refresh found no exact auctionable items in bags, bank cache or lists."
            );

        end

        return;
    end

    gAtr_QuickRefreshActive = true;
    gAtr_QuickRefreshIndex = 1;
    gAtr_QuickRefreshLastSignature = nil;
    gAtr_QuickRefreshStartedAt = GetTime();
    gAtr_QuickRefreshDurations = {};
    gAtr_QuickRefreshUpdated = 0;
    gAtr_QuickRefreshAdded = 0;
    gAtr_QuickRefreshUnchanged = 0;
    gAtr_QuickRefreshNoAuctions = 0;
    gAtr_QuickRefreshSkipped = 0;

    gAtr_FullScanState = ATR_FS_STARTED;
    gAtr_FullScanSubState = ATR_FSS_WAITING_PAGE;

    SortAuctionClearSort ("list");

    if (Atr_FullScanStartButton) then
        Atr_FullScanStartButton:Disable();
    end

    if (Atr_FullScanDone) then
        Atr_FullScanDone:Disable();
    end

    local button = Atr_QuickRefreshEnsureButton();
    button:Disable();

    if (_G["Atr_ClearDatabaseButton"]) then
        _G["Atr_ClearDatabaseButton"]:Disable();
    end

    Atr_QuickRefreshResetItem();
    Atr_QuickRefreshUpdateStatus();
    Atr_QuickRefreshSendPage();
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

    if (_G["Atr_QuickRefreshButton"]) then
        _G["Atr_QuickRefreshButton"]:Disable();
    end

    if (_G["Atr_ClearDatabaseButton"]) then
        _G["Atr_ClearDatabaseButton"]:Disable();
    end

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

    if (_G["Atr_FullScanHelpScroll"]) then
        _G["Atr_FullScanHelpScroll"]:Hide();
    end

    if (_G["Atr_QuickRefreshButton"]) then
        _G["Atr_QuickRefreshButton"]:Hide();
    end

    if (_G["Atr_ClearDatabaseButton"]) then
        _G["Atr_ClearDatabaseButton"]:Hide();
    end

    Atr_FullScanResults:Show();

    Atr_FullScanResults:SetBackdropColor (
        0.3,
        0.3,
        0.4
    );

    AUCTIONATOR_LAST_SCAN_TIME = time();

    -- Record which old DB entries were not seen anywhere in this
    -- complete scan. Keep their historical price, but mark it stale.
    Atr_MarketMetaMarkFullScanStale();

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

                    Atr_MarketMetaMarkSeen (
                        name,
                        newprice,
                        "full"
                    );

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

    -- Auctionator.lua already routes AUCTION_ITEM_LIST_UPDATE here
    -- while gAtr_FullScanState == ATR_FS_STARTED. Reuse that route
    -- for Quick Refresh so no other addon file needs modifying.
    if (gAtr_QuickRefreshActive) then
        Atr_QuickRefreshAnalyze();
        return;
    end

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
-- Recommended sell price helpers
-----------------------------------------

local gAtr_RecommendedSellHooksInstalled = false;

local function Atr_GetRecommendedSellPrice (item)

    local itemName =
        GetItemInfo (item);

    if (not itemName) then
        return nil;
    end

    local marketPrice =
        gAtr_ScanDB
        and gAtr_ScanDB[itemName]
        or nil;

    if (
        type(marketPrice) ~= "number"
        or marketPrice <= 0
    ) then
        return nil;
    end

    local recommended =
        marketPrice;

    if (Atr_CalcUndercutPrice) then

        local ok, value =
            pcall (
                Atr_CalcUndercutPrice,
                marketPrice
            );

        if (
            ok
            and type(value) == "number"
            and value > 0
        ) then
            recommended = value;
        end
    end

    return math.floor (
        recommended + 0.5
    );
end

-----------------------------------------

local function Atr_RecommendedSellItemCanAuction (link)

    if (not link) then
        return false;
    end

    local itemID;

    if (
        zc
        and zc.ItemIDfromLink
    ) then

        -- ItemIDfromLink can return more than one value in this old
        -- Auctionator utility. Passing the call directly into tonumber()
        -- forwards those extra return values, making Lua treat the
        -- second one as tonumber's optional numeric base.
        --
        -- Store the first return value explicitly before converting it.
        local rawItemID =
            zc.ItemIDfromLink (link);

        itemID =
            tonumber (rawItemID);
    end

    if (
        itemID
        and Atr_GetBonding
    ) then

        local ok, bonding =
            pcall (
                Atr_GetBonding,
                itemID
            );

        if (ok) then

            -- 1 = Bind on Pickup.
            -- 4 / 5 are quest-item binding states in the old
            -- Auctionator tooltip code.
            if (
                bonding == 1
                or bonding == 4
                or bonding == 5
            ) then
                return false;
            end
        end
    end

    return true;
end

-----------------------------------------

local function Atr_AppendRecommendedSellToTooltip (
    tip,
    link,
    count
)

    if (
        not tip
        or not link
        or AUCTIONATOR_A_TIPS ~= 1
        or not Atr_RecommendedSellItemCanAuction (link)
    ) then
        return;
    end

    local recommended =
        Atr_GetRecommendedSellPrice (link);

    if (
        not recommended
        or recommended <= 0
    ) then
        return;
    end

    local xstring = "";
    local displayPrice = recommended;
    local showStackPrices = IsShiftKeyDown();

    if (AUCTIONATOR_SHIFT_TIPS == 2) then
        showStackPrices = not IsShiftKeyDown();
    end

    if (
        count
        and count > 1
        and showStackPrices
    ) then

        displayPrice =
            displayPrice * count;

        xstring =
            "|cFFAAAAFF x"
            .. tostring(count)
            .. "|r";
    end

    tip:AddDoubleLine (
        "Recommended sell" .. xstring,
        "|cFFFFFFFF"
            .. zc.priceToMoneyString (
                displayPrice
            )
    );

    tip:Show();
end

-----------------------------------------

local function Atr_InstallRecommendedSellTooltipHooks ()

    if (
        gAtr_RecommendedSellHooksInstalled
        or not hooksecurefunc
        or not GameTooltip
    ) then
        return;
    end

    gAtr_RecommendedSellHooksInstalled = true;

    -- Register these AFTER AuctionatorHints.lua has loaded so the
    -- recommended sell line appears underneath Auctionator's existing
    -- Auction / Disenchant values.
    hooksecurefunc (
        GameTooltip,
        "SetBagItem",
        function (tip, bag, slot)

            local _, count =
                GetContainerItemInfo (
                    bag,
                    slot
                );

            Atr_AppendRecommendedSellToTooltip (
                tip,
                GetContainerItemLink (
                    bag,
                    slot
                ),
                count
            );
        end
    );

    hooksecurefunc (
        GameTooltip,
        "SetAuctionItem",
        function (tip, listType, index)

            local _, _, count =
                GetAuctionItemInfo (
                    listType,
                    index
                );

            Atr_AppendRecommendedSellToTooltip (
                tip,
                GetAuctionItemLink (
                    listType,
                    index
                ),
                count
            );
        end
    );

    hooksecurefunc (
        GameTooltip,
        "SetAuctionSellItem",
        function (tip)

            local name, _, count =
                GetAuctionSellItemInfo();

            local _, link =
                GetItemInfo (name);

            Atr_AppendRecommendedSellToTooltip (
                tip,
                link,
                count
            );
        end
    );

    hooksecurefunc (
        GameTooltip,
        "SetInventoryItem",
        function (tip, unit, slot)

            Atr_AppendRecommendedSellToTooltip (
                tip,
                GetInventoryItemLink (
                    unit,
                    slot
                ),
                GetInventoryItemCount (
                    unit,
                    slot
                )
            );
        end
    );

    if (GameTooltip.SetGuildBankItem) then

        hooksecurefunc (
            GameTooltip,
            "SetGuildBankItem",
            function (tip, tab, slot)

                local link =
                    GetGuildBankItemLink
                    and GetGuildBankItemLink (
                        tab,
                        slot
                    )
                    or nil;

                local _, count;

                if (GetGuildBankItemInfo) then
                    _, count =
                        GetGuildBankItemInfo (
                            tab,
                            slot
                        );
                end

                Atr_AppendRecommendedSellToTooltip (
                    tip,
                    link,
                    count
                );
            end
        );
    end
end

-----------------------------------------
-- Sell-pane database prefill
-----------------------------------------

local function Atr_PrefillSellPriceFromDatabase ()

    if (
        not Atr_IsModeCreateAuction
        or not Atr_IsModeCreateAuction()
        or not GetAuctionSellItemInfo
    ) then
        return;
    end

    local itemName, texture, count =
        GetAuctionSellItemInfo();

    if (
        not itemName
        or not count
        or count <= 0
    ) then
        return;
    end

    local recommended =
        Atr_GetRecommendedSellPrice (
            itemName
        );

    if (
        not recommended
        or recommended <= 0
    ) then
        return;
    end

    local stackSize = count;

    if (Atr_StackSize) then

        local current =
            tonumber (
                Atr_StackSize()
            );

        if (
            current
            and current > 0
        ) then
            stackSize = current;
        end
    end

    local stackPrice =
        recommended * stackSize;

    if (
        Atr_ItemPrice
        and MoneyInputFrame_SetCopper
    ) then

        MoneyInputFrame_SetCopper (
            Atr_ItemPrice,
            recommended
        );
    end

    if (
        Atr_StackPrice
        and MoneyInputFrame_SetCopper
    ) then

        MoneyInputFrame_SetCopper (
            Atr_StackPrice,
            stackPrice
        );
    end

    if (
        Atr_StartingPrice
        and MoneyInputFrame_SetCopper
    ) then

        local startPrice =
            recommended;

        if (Atr_CalcStartPrice) then

            local ok, value =
                pcall (
                    Atr_CalcStartPrice,
                    recommended
                );

            if (
                ok
                and type(value) == "number"
                and value > 0
            ) then
                startPrice = value;
            end
        end

        MoneyInputFrame_SetCopper (
            Atr_StartingPrice,
            startPrice * stackSize
        );
    end

    -- This is only an immediate database fallback. Auctionator's normal
    -- live search still runs and may replace these fields with fresher
    -- AH data when that search completes.
    if (Atr_Recommend_Basis_Text) then

        Atr_Recommend_Basis_Text:SetText (
            "(based on refreshed Auctionator scan data)"
        );

        Atr_Recommend_Basis_Text:SetTextColor (
            0.8,
            0.8,
            1.0
        );
    end
end

-----------------------------------------
-- Full Scan dialog mask
-----------------------------------------

local gAtr_FullScanMaskOriginal = nil;

local function Atr_FullScanRememberMaskLayout ()

    if (
        not Atr_Mask
        or gAtr_FullScanMaskOriginal
    ) then
        return;
    end

    local point, relativeTo, relativePoint, x, y =
        Atr_Mask:GetPoint (1);

    gAtr_FullScanMaskOriginal = {
        width         = Atr_Mask:GetWidth(),
        height        = Atr_Mask:GetHeight(),
        alpha         = Atr_Mask:GetAlpha(),
        point         = point,
        relativeTo    = relativeTo,
        relativePoint = relativePoint,
        x             = x,
        y             = y
    };
end

-----------------------------------------

local function Atr_FullScanUseCompactMask ()

    if (
        not Atr_Mask
        or not Atr_FullScanFrame
    ) then
        return;
    end

    Atr_FullScanRememberMaskLayout();

    -- Keep only a small dimmed area immediately behind the Full Scan
    -- dialog. The rest of the Auction House remains fully interactive,
    -- including its Close button.
    Atr_Mask:ClearAllPoints();

    Atr_Mask:SetWidth (
        Atr_FullScanFrame:GetWidth() + 20
    );

    Atr_Mask:SetHeight (
        Atr_FullScanFrame:GetHeight() + 20
    );

    Atr_Mask:SetPoint (
        "CENTER",
        Atr_FullScanFrame,
        "CENTER",
        0,
        0
    );

    -- Keep a subtle visual separation from the Auction House without
    -- dimming the entire window.
    Atr_Mask:SetAlpha (0.45);
    Atr_Mask:Show();
end

-----------------------------------------

local function Atr_FullScanRestoreMaskLayout ()

    if (
        not Atr_Mask
        or not gAtr_FullScanMaskOriginal
    ) then
        return;
    end

    local saved =
        gAtr_FullScanMaskOriginal;

    Atr_Mask:ClearAllPoints();

    Atr_Mask:SetWidth (
        saved.width
    );

    Atr_Mask:SetHeight (
        saved.height
    );

    Atr_Mask:SetPoint (
        saved.point or "TOPLEFT",
        saved.relativeTo or UIParent,
        saved.relativePoint or saved.point or "TOPLEFT",
        saved.x or 0,
        saved.y or 0
    );

    Atr_Mask:SetAlpha (
        saved.alpha or 1
    );
end

-----------------------------------------
-- Full Scan dialog
-----------------------------------------

function Atr_ShowFullScanFrame()

    local quickButton = Atr_QuickRefreshEnsureButton();
    quickButton:Show();

    local clearButton = Atr_ClearDatabaseEnsureButton();
    clearButton:Show();

    -- Auctionator normally stretches Atr_Mask across the whole Auction
    -- House while this dialog is open. Restrict it to a small area just
    -- behind this dialog so the surrounding AH UI (including Close)
    -- remains usable.
    if (
        Atr_FullScanFrame
        and not Atr_FullScanFrame.atrCompactMaskHooked
    ) then

        Atr_FullScanFrame.atrCompactMaskHooked = true;

        Atr_FullScanFrame:HookScript (
            "OnShow",
            function ()
                Atr_FullScanUseCompactMask();
            end
        );

        Atr_FullScanFrame:HookScript (
            "OnHide",
            function ()
                Atr_FullScanRestoreMaskLayout();
            end
        );
    end

    -- Keep multi-line scan information on the left side of the
    -- dialog. The original XML leaves this FontString unconstrained,
    -- which is why long status text previously ran beneath the buttons.
    if (Atr_FullScanStatus) then
        Atr_FullScanStatus:SetWidth (245);
        Atr_FullScanStatus:SetJustifyH ("LEFT");
        Atr_FullScanStatus:SetJustifyV ("TOP");
    end

    -- The stock SimpleHTML control does not clip long content cleanly
    -- in this WotLK client. Use a proper scroll frame for the help text
    -- so it always remains inside the Full Scan dialog.
    if (Atr_FullScanHTML) then
        Atr_FullScanHTML:Hide();
    end

    local helpScroll =
        Atr_FullScanEnsureHelpScroll();

    Atr_FullScanUpdateHelpText();
    helpScroll:Show();

    Atr_FullScanResults:Hide();

    Atr_FullScanFrame:Show();

    -- Apply immediately as well as through the OnShow hook so this
    -- works on the first opening after installing the patch.
    Atr_FullScanUseCompactMask();

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

    local quickButton =
        _G["Atr_QuickRefreshButton"];

    local clearButton =
        _G["Atr_ClearDatabaseButton"];

    if (clearButton) then

        if (
            gAtr_FullScanState == ATR_FS_NULL
            and not gAtr_QuickRefreshActive
            and (
                Atr_GetDBsize() > 0
                or Atr_FullScanGetCheckpoint()
            )
        ) then
            clearButton:Enable();
        else
            clearButton:Disable();
        end

    end

    if (gAtr_FullScanState == ATR_FS_NULL) then

        local checkpoint =
            Atr_FullScanGetCheckpoint();

        if (checkpoint) then

            Atr_FullScanStartButton:SetText (
                "Resume Scan"
            );

            Atr_FullScanStartButton:Enable();

            -- A saved Full Scan checkpoint is passive data only.
            -- Quick Refresh may safely run while that scan is paused;
            -- the checkpoint remains untouched and Resume Scan will
            -- still continue from the same saved page afterwards.
            if (quickButton) then

                if (canQuery) then
                    quickButton:Enable();
                else
                    quickButton:Disable();
                end

            end

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

                if (quickButton) then
                    quickButton:Enable();
                end

            else

                Atr_FullScanStartButton:Disable();

                Atr_FullScanNext:SetText (
                    ZT("waiting for auction query")
                );

                if (quickButton) then
                    quickButton:Disable();
                end

            end

        end

    else

        Atr_FullScanStartButton:Disable();

        if (quickButton) then
            quickButton:Disable();
        end

        if (gAtr_QuickRefreshActive) then

            Atr_FullScanNext:SetText (
                "Quick Refresh"
            );

        else

            Atr_FullScanNext:SetText (
                "Scanning"
            );

        end

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

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "BANKFRAME_OPENED"
);

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "BANKFRAME_CLOSED"
);

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "PLAYERBANKSLOTS_CHANGED"
);

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "BAG_UPDATE"
);

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "ADDON_LOADED"
);

gAtr_FullScanLifecycleFrame:RegisterEvent (
    "NEW_AUCTION_UPDATE"
);

gAtr_FullScanLifecycleFrame:SetScript (
    "OnEvent",
    function (self, event, ...)

        -- ------------------------------------------------------
        -- Install tooltip hooks after every Auctionator file has
        -- finished loading. AuctionatorHints.lua loads after this
        -- file, so hooking on ADDON_LOADED keeps our line underneath
        -- the original Auction / Disenchant tooltip information.
        -- ------------------------------------------------------
        if (event == "ADDON_LOADED") then

            local loadedAddon =
                select (1, ...);

            if (
                loadedAddon == addonName
                or loadedAddon == "Auctionator"
            ) then

                Atr_InstallRecommendedSellTooltipHooks();

                self:UnregisterEvent (
                    "ADDON_LOADED"
                );
            end

            return;
        end

        -- ------------------------------------------------------
        -- When an item is placed in Auctionator's Sell pane, fill
        -- the price fields immediately from Quick Refresh / Full
        -- Scan data. Auctionator's normal live AH search may replace
        -- this with fresher information a moment later.
        -- ------------------------------------------------------
        if (event == "NEW_AUCTION_UPDATE") then

            Atr_PrefillSellPriceFromDatabase();
            return;
        end

        -- ------------------------------------------------------
        -- Keep a persistent bank snapshot for Quick Refresh.
        -- ------------------------------------------------------
        if (event == "BANKFRAME_OPENED") then

            gAtr_QuickRefreshBankOpen = true;
            Atr_QuickRefreshSnapshotBank();
            return;
        end

        if (event == "BANKFRAME_CLOSED") then

            -- Keep the last valid snapshot captured while the bank
            -- was open. Some 3.3.5 clients clear bank containers
            -- before BANKFRAME_CLOSED is dispatched.
            gAtr_QuickRefreshBankOpen = false;
            return;
        end

        if (
            gAtr_QuickRefreshBankOpen
            and (
                event == "PLAYERBANKSLOTS_CHANGED"
                or event == "BAG_UPDATE"
            )
        ) then

            Atr_QuickRefreshSnapshotBank();
            return;
        end

        -- ------------------------------------------------------
        -- SavedVariables are flushed by WoW on normal logout.
        -- Quick Refresh itself needs no resume checkpoint because
        -- every completed item is committed immediately.
        -- ------------------------------------------------------
        if (event == "PLAYER_LOGOUT") then

            if (gAtr_QuickRefreshActive) then
                return;
            end

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

        if (event == "AUCTION_HOUSE_CLOSED") then

            -- Restore Auctionator's original mask geometry/opacity so
            -- other dialogs continue to behave exactly as before.
            Atr_FullScanRestoreMaskLayout();

            if (gAtr_QuickRefreshActive) then

                Atr_QuickRefreshStop (
                    "Quick Refresh stopped: Auction House closed. Completed item prices were kept."
                );

                return;
            end

            if (
                gAtr_FullScanState
                    == ATR_FS_STARTED
                or gAtr_FullScanState
                    == ATR_FS_ANALYZING
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

    end
);
-----------------------------------------
-- OnUpdate driver
-----------------------------------------

function Atr_FullScanFrameIdle()

    if (gAtr_QuickRefreshActive) then
        Atr_QuickRefreshFrameIdle();
        return;
    end

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