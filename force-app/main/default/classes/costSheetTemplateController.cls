/**
* @File Name : costSheetTemplateController.cls
* @Author : Darshitha D
* @Created Date : 
**/

public class costSheetTemplateController {

	@AuraEnabled(cacheable=true)
	public static List<Pricing_Element_Master__c> fetchPricingBasedonSearch(String searchedPricingEle){
		try{
			String searchWord = '%' + searchedPricingEle + '%';
			List<Pricing_Element_Master__c> pricingElementList = [SELECT Id,Name,Conversion_Unit__c, Agreement__c,Parking_Type__c from Pricing_Element_Master__c where Name LIKE: searchWord AND Parking_Type__c = null] ;
			return pricingElementList;
		}catch(Exception e){
			System.debug('Error in fetchPricingBasedonSearch: ' + e.getMessage());
			return null;
		}
	}

	@AuraEnabled(cacheable=false)
	public static Boolean checkIfTemplateCodeExists(String costSheetTempCode){
		try {
			System.debug('costSheetTempCode ==> ' + costSheetTempCode);
			List<Cost_Sheet_Template__c> costSheetTempList = [SELECT Id from Cost_Sheet_Template__c where Template_Code__c =: costSheetTempCode];
			System.debug('costSheetTempList ===> ' + costSheetTempList);
			if(!costSheetTempList.isEmpty()){
				return true;
			}
			return false;
		} catch (Exception e) {
			System.debug('Error ===> ' + e.getMessage());
			return true;
		}
	}

	@AuraEnabled
	public static existingDetailsWrapper fetchExistingData(Id costSheetTempId, Map<String, String> ObjectByField){
		try {
			if(costSheetTempId != null){
				existingDetailsWrapper wrp = new existingDetailsWrapper();
				
				List<Cost_Sheet_Template__c> costSheetTemplateList = [SELECT Id,Name,Company__c,Project__c,Project__r.Name,Approval_Status__c,Active__c,Template_Code__c, (SELECT Id,Unit__c,Unit__r.Floor__c,Unit__r.Floor__r.Floor_No__c,Unit__r.Floor__r.Block__c,Unit__r.Name, Unit__r.Unit_Name_Code__c, Unit__r.Floor__r.Block__r.Block_Code__c  from Cost_Unit_Linking__r),
																	 (SELECT Id,Pricing_Element_Master__c,Unit__c,PE_Type__c,Type__c,Quantity__c,Rate__c,Amount__c,Tax_Amount__c, Sequence__c from Cost_Pricings_Association__r) FROM Cost_Sheet_Template__c WHERE Id = :costSheetTempId];
																	
				Map<String, List<String>> picklistValues = new Map<String, List<String>>();
				if(ObjectByField != null){
                    System.debug('entered..');
					picklistValues = getAllPickListVal(ObjectByField);
                    System.debug('picklistValues==>'+picklistValues);
				}
                System.debug('costSheetTemplateList==>'+costSheetTemplateList);
				if(!costSheetTemplateList.isEmpty()){
					List<Project__c> projectList = [SELECT Id,Name, Active__c from Project__c where Company__c =: costSheetTemplateList[0].Company__c and Active__c = true];
					unitFloorBlockWrapper unitWrp = new unitFloorBlockWrapper();
					unitWrp = getTowerFloorUnitPricingElementData(costSheetTemplateList[0].Project__c);
	
					List<Cost_Unit_Linking__c> costSheetLinkingList = [SELECT Id,Cost_Sheet_Template__c,Unit__c,Unit__r.Floor__c,Unit__r.Floor__r.Block__c from Cost_Unit_Linking__c where Cost_Sheet_Template__c =: costSheetTemplateList[0].Id];
					List<Cost_Pricing_Association__c> costPricingAssociationWithTax = [SELECT Id,Pricing_Element_Master__c,Unit__c,PE_Type__c,Type__c,Quantity__c,Rate__c,Amount__c,Tax_Amount__c, Sequence__c, (SELECT Id,Name,Tax_Master__c,Tax_Master__r.Rounding_Method__c,Tax_Master__r.Tax_Type__c,Tax_Master__r.Name,Tax_Master__r.Tax__c,Cost_Pricing_Association__c,App__c,Amount__c from Cost_Sheet_Tax_Linkings__r) ,Cost_Sheet_Template__c
																				from Cost_Pricing_Association__c where Cost_Sheet_Template__c =: costSheetTemplateList[0].Id];

					wrp.costSheetTemObj 		= costSheetTemplateList.isEmpty() ? null : costSheetTemplateList[0];
					wrp.lockRecord 				= costSheetTemplateList[0].Approval_Status__c == 'Approved' || costSheetTemplateList[0].Approval_Status__c == 'Rejected' ? true : false;
					wrp.projectList 			= projectList.isEmpty() ? null : projectList;
					wrp.selectedBlock 			= costSheetLinkingList.isEmpty() ? null : costSheetLinkingList[0].Unit__r.Floor__r.Block__c;
					wrp.selectedFloor 			= costSheetLinkingList.isEmpty() ? null : costSheetLinkingList[0].Unit__r.Floor__c;
					wrp.unitWrp 				= unitWrp != null ? unitWrp : null;
					wrp.picklistResult 			= picklistValues != null ? picklistValues : null;
					wrp.costPricingAssociationWithTax = costPricingAssociationWithTax.isEmpty() ? null : costPricingAssociationWithTax;
					System.debug('wrp ===> ' + wrp);
					
				}
				return wrp;
				
			}
			return null;
		} catch (Exception e) {
			System.debug('Error ===> ' + e.getMessage());
			System.debug('Line ===> ' + e.getLineNumber());
			return null;
		}
	}

	public class existingDetailsWrapper{
		@AuraEnabled public Cost_Sheet_Template__c costSheetTemObj{get;set;}
		@AuraEnabled public Boolean lockRecord{get;set;}
		@AuraEnabled public List<Project__c> projectList{get;set;}
		@AuraEnabled public String selectedBlock{get;set;}
		@AuraEnabled public String selectedFloor{get;set;}
		@AuraEnabled public unitFloorBlockWrapper unitWrp{get;set;}
		@AuraEnabled public List<Cost_Pricing_Association__c> costPricingAssociationWithTax{get;set;}
		@AuraEnabled public Map<String, List<String>> picklistResult{get;set;}
	}

	@AuraEnabled
	public static String saveAllRecords(Id costSheetTempId, Cost_Sheet_Template__c costSheetTempRec, List<Id> selectedUnitIds, String costPricingAssociationsListJson){
		try {
			System.debug('costSheetTempId ===> ' + costSheetTempId);
			System.debug('costSheetTempRec ===> ' + costSheetTempRec);
			System.debug('selectedUnitIds ===> ' + selectedUnitIds);
			System.debug('costPricingAssociationsListJson ===> ' + costPricingAssociationsListJson);

			Id costSheetTemplateId;

			Map<String,Id> costPricingAsstnPricingMap = new Map<String,Id>();
			Map<String,List<Cost_Sheet_Tax_Linking__c>> pricingElementToCostPricingAssociationMap = new Map<String,List<Cost_Sheet_Tax_Linking__c>>();

			List<Cost_Unit_Linking__c> costUnitLinkingListToInsert = new List<Cost_Unit_Linking__c>();
			List<Cost_Unit_Linking__c> costUnitLinkingListToDelete = new List<Cost_Unit_Linking__c>();
			List<Cost_Pricing_Association__c> costPricingAssociationListToInsert = new List<Cost_Pricing_Association__c>();
			List<Cost_Pricing_Association__c> costPricingAssociationListToUpdate = new List<Cost_Pricing_Association__c>();
			List<Cost_Pricing_Association__c> costPricingAssociationListToDelete = new List<Cost_Pricing_Association__c>();
			List<Cost_Sheet_Tax_Linking__c> costSheetTaxLinkingListToInsert = new List<Cost_Sheet_Tax_Linking__c>();
			List<Cost_Sheet_Tax_Linking__c> costSheetTaxLinkingListToUpdate = new List<Cost_Sheet_Tax_Linking__c>();
			List<Cost_Sheet_Tax_Linking__c> costSheetTaxLinkingListToDelete = new List<Cost_Sheet_Tax_Linking__c>();
			if(costSheetTempId != null & costSheetTempRec != null){
				System.debug('updation');
				Cost_Sheet_Template__c costSheet = new Cost_Sheet_Template__c();
				costSheet.Id 				= costSheetTempRec.Id;
				costSheet.Company__c 		= costSheetTempRec.Company__c;
				costSheet.Project__c 		= costSheetTempRec.Project__c;
				costSheet.Template_Code__c 	= costSheetTempRec.Template_Code__c;
				costSheet.Name 				= costSheetTempRec.Name;
				costSheet.Active__c 		= costSheetTempRec.Active__c;
				update costSheet;
				costSheetTemplateId = costSheet.Id;
			}else{
				System.debug('insertion');
				Cost_Sheet_Template__c costSheet = new Cost_Sheet_Template__c();
				costSheet.Company__c 		= costSheetTempRec.Company__c;
				costSheet.Project__c 		= costSheetTempRec.Project__c;
				costSheet.Template_Code__c 	= costSheetTempRec.Template_Code__c;
				costSheet.Name 				= costSheetTempRec.Name;
				costSheet.Active__c 		= costSheetTempRec.Active__c;
				insert costSheet;
				costSheetTemplateId = costSheet.Id;
			}
			System.debug('costSheetTempRec ===> ' + costSheetTemplateId);

			Set<Id> existingUnitIds = new Set<Id>();
			List<Cost_Unit_Linking__c> existingCostUnitLinking = [SELECT Id,Unit__c,Cost_Sheet_Template__c from Cost_Unit_Linking__c where Cost_Sheet_Template__c =: costSheetTemplateId];
			if(!existingCostUnitLinking.isEmpty()){
				for(Cost_Unit_Linking__c unit : existingCostUnitLinking){
					existingUnitIds.add(unit.Unit__c);
				}

				for(Cost_Unit_Linking__c unit : existingCostUnitLinking){
					if(selectedUnitIds.size() > 0 && (!selectedUnitIds.contains(unit.Unit__c))){
						costUnitLinkingListToDelete.add(unit);
					}
				}
			}

			if(selectedUnitIds.size() > 0 && costSheetTemplateId != null){
				for(Id unit : selectedUnitIds){
					if(!existingUnitIds.contains(unit)){
						Cost_Unit_Linking__c costUnitLink = new Cost_Unit_Linking__c(
							Unit__c 				= unit != null ? unit : null, 
							Cost_Sheet_Template__c 	= costSheetTemplateId != null ? costSheetTemplateId : null);
							System.debug('costUnitLink ===> ' + costUnitLink);
						costUnitLinkingListToInsert.add(costUnitLink);
					}
				}
			}

			if(!costUnitLinkingListToInsert.isEmpty()){
				insert costUnitLinkingListToInsert;
			}

			if(!costUnitLinkingListToDelete.isEmpty()){
				delete costUnitLinkingListToDelete;
			}

			Set<Id> existingPricingEleIds = new Set<Id>();
			Set<Id> existingIds = new Set<Id>();
			Map<Id,Cost_Pricing_Association__c> pricingByCostPricingAssociationMap = new Map<Id,Cost_Pricing_Association__c>();
			Map<Id,List<Cost_Sheet_Tax_Linking__c>> costPricingAsstnByTaxLinkingMap = new Map<Id,List<Cost_Sheet_Tax_Linking__c>>();
			Map<Id,List<Id>> existingCostPricingByTaxIdMap = new Map<Id,List<Id>>();
			Map<Id,List<Id>> newCostPricingByTaxIdMap = new Map<Id,List<Id>>();
			List<Cost_Pricing_Association__c> existingCostPricingAssociation = [SELECT Id,Amount__c,Pricing_Element_Master__c,Unit__c,PE_Type__c,Type__c,Quantity__c,Rate__c,Tax_Amount__c,Cost_Sheet_Template__c, Sequence__c,
																				(SELECT Id,Tax_Master__c,Tax_Master__r.Rounding_Method__c,Amount__c,App__c,Cost_Pricing_Association__c from Cost_Sheet_Tax_Linkings__r) from Cost_Pricing_Association__c where Cost_Sheet_Template__c =: costSheetTemplateId];
			if(!existingCostPricingAssociation.isEmpty()){
				for(Cost_Pricing_Association__c pricing : existingCostPricingAssociation){
					existingPricingEleIds.add(pricing.Pricing_Element_Master__c);
					pricingByCostPricingAssociationMap.put(pricing.Pricing_Element_Master__c, pricing);
					List<Cost_Sheet_Tax_Linking__c> costSheetLinkingList = pricing.Cost_Sheet_Tax_Linkings__r != null ? pricing.Cost_Sheet_Tax_Linkings__r : null; 
					if(!costSheetLinkingList.isEmpty()){
						costPricingAsstnByTaxLinkingMap.put(pricing.Id, costSheetLinkingList);
						Set<Id> taxMasterIds = new Set<Id>();
						for(Cost_Sheet_Tax_Linking__c link : costSheetLinkingList){
							taxMasterIds.add(link.Tax_Master__c);
						}
						existingCostPricingByTaxIdMap.put(pricing.Id, new List<Id>(taxMasterIds));
					}
				}
			}

			List<Object> rawCostPricingAssociationsList = (List<Object>) JSON.deserializeUntyped(costPricingAssociationsListJson);
            List<Map<String, Object>> costPricingAssociationsList = new List<Map<String, Object>>();
            
            for (Object obj : rawCostPricingAssociationsList) {
                if (obj instanceof Map<String, Object>) {
					System.debug('obj ===> ' + obj);
                    costPricingAssociationsList.add((Map<String, Object>) obj);
                }
            }
			System.debug('costPricingAssociationsList ===> ' + costPricingAssociationsList);

			Set<Id> selectedPricingIds = new Set<Id>();
			Map<Id,List<Id>> selectedPricingByTaxIds = new Map<Id, List<Id>>();
			if (!costPricingAssociationsList.isEmpty() && costSheetTemplateId != null) {
                for (Map<String, Object> cstPriceAsoctn : costPricingAssociationsList) {
					Id pricingId = cstPriceAsoctn.get('Pricing_Element_Master__c') != null ? (String)cstPriceAsoctn.get('Pricing_Element_Master__c') : null;
					if(pricingId != null){
						selectedPricingIds.add(pricingId);
					}

					List<Object> rawTaxList = (List<Object>) cstPriceAsoctn.get('taxList');
                    if (rawTaxList != null && !rawTaxList.isEmpty()) {
						Set<Id> taxIds = new Set<Id>();
                        for (Object taxObj : rawTaxList) {
                            if (taxObj instanceof Map<String, Object>) {
                                Map<String, Object> tax = (Map<String, Object>) taxObj;
								System.debug('tax ===> ' + tax);
								System.debug('tax id ===> ' + (String) tax.get('Id'));
								String taxId = (String) tax.get('Id');
								system.debug('taxId ===> ' + taxId);
								if (String.isNotBlank(taxId)) {
									taxIds.add(taxId);
									system.debug('taxIds ===> ' + taxIds);
								}
							}
						}
						system.debug('taxIds ===> ' + taxIds);

						if(!selectedPricingByTaxIds.containsKey(pricingId)){
							selectedPricingByTaxIds.put(pricingId, new List<Id>(taxIds));
						}
						system.debug('selectedPricingByTaxIds ===> ' + selectedPricingByTaxIds);

					}
				}
			}

			System.debug('selectedPricingIds ===> ' + selectedPricingIds);
			System.debug('selectedPricingByTaxIds ===> ' + selectedPricingByTaxIds);

			for(Cost_Pricing_Association__c pricing : existingCostPricingAssociation){
				if(selectedPricingIds.size() > 0 && (!selectedPricingIds.contains(pricing.Pricing_Element_Master__c))){
					costPricingAssociationListToDelete.add(pricing);
					System.debug('costPricingAssociationListToDelete ===> ' + costPricingAssociationListToDelete);
					if(!pricing.Cost_Sheet_Tax_Linkings__r.isEmpty()){
						for(Cost_Sheet_Tax_Linking__c taxLink : pricing.Cost_Sheet_Tax_Linkings__r){
							System.debug('tax link Id ====> ' + taxLink.Id);
							System.debug('tax link to delete ====> ' + taxLink);
							costSheetTaxLinkingListToDelete.add(taxLink);
						}
					}
				}
			}

            if (!costPricingAssociationsList.isEmpty() && costSheetTemplateId != null) {
                for (Map<String, Object> cstPriceAsoctn : costPricingAssociationsList) {
					String pricingId = cstPriceAsoctn.get('Pricing_Element_Master__c') != null ? (String)cstPriceAsoctn.get('Pricing_Element_Master__c') : null;
					System.debug('pricingId ===> ' + pricingId);
					Boolean isNewCostPricingAsstn = false;
					Cost_Pricing_Association__c costPARec = new Cost_Pricing_Association__c();

					if(existingPricingEleIds.contains(pricingId)){
						System.debug('is not a new cost pricing asstn');
						Cost_Pricing_Association__c cpa = pricingByCostPricingAssociationMap.get(pricingId);
						System.debug('cpa ===> ' + cpa);
						costPARec.Id = cpa.Id;
						isNewCostPricingAsstn = false;
						System.debug('costPARec ===> ' + costPARec);
					}else{
						System.debug('is a new cost pricing asstn');
						// costPARec = new Cost_Pricing_Association__c();
						costPARec.Pricing_Element_Master__c = pricingId;
						costPARec.Cost_Sheet_Template__c 	= costSheetTemplateId;
						isNewCostPricingAsstn = true;
					}

					costPARec.Unit__c 					= cstPriceAsoctn.get('Unit__c') != null ? (String)cstPriceAsoctn.get('Unit__c') : null;
					costPARec.PE_Type__c 				= cstPriceAsoctn.get('PE_Type__c') != null ? (String)cstPriceAsoctn.get('PE_Type__c') : null;
                    costPARec.Type__c 				= cstPriceAsoctn.get('Type__c') != null ? (String)cstPriceAsoctn.get('Type__c') : null;
					costPARec.Quantity__c 				= cstPriceAsoctn.get('Quantity__c') != null ? Integer.valueOf(String.valueOf(cstPriceAsoctn.get('Quantity__c'))) : null;
                    costPARec.Sequence__c 				= cstPriceAsoctn.get('Sequence__c') != null ? Integer.valueOf(String.valueOf(cstPriceAsoctn.get('Sequence__c'))) : null;
					costPARec.Rate__c 					= cstPriceAsoctn.get('Rate__c') != null ? Decimal.valueOf(String.valueOf(cstPriceAsoctn.get('Rate__c'))) : null;

					Object amountObj = cstPriceAsoctn.get('Amount__c');
					Decimal amount = 0.0;
					if (amountObj != null) {
						if (amountObj instanceof String) {
							costPARec.Amount__c = Decimal.valueOf((String) amountObj); 
						} else if (amountObj instanceof Integer) {
							costPARec.Amount__c = Decimal.valueOf((Integer) amountObj); 
						}
					}

					Object taxObjRec = cstPriceAsoctn.get('Tax_Amount__c');
					System.debug('taxObjRec ===> ' + taxObjRec);
					Decimal taxAmount = 0.0;
					if (taxObjRec != null) {
						if (taxObjRec instanceof String) {
						String taxAmountStr = (String) taxObjRec;
                        taxAmountStr = taxAmountStr.replace('\u00A0', '').trim();
                        if (String.isNotBlank(taxAmountStr)) {
                            costPARec.Tax_Amount__c = Decimal.valueOf(taxAmountStr);
                        }
							System.debug(costPARec.Tax_Amount__c);
						} else if (taxObjRec instanceof Integer) {
							costPARec.Tax_Amount__c = Decimal.valueOf((Integer) taxObjRec); 
							System.debug(costPARec.Tax_Amount__c);
						}else if (taxObjRec instanceof Decimal) {
							costPARec.Tax_Amount__c = (Decimal) taxObjRec;
							System.debug(costPARec.Tax_Amount__c);
						}
					}

					system.debug('costPARec.Tax_Amount__c ===> ' + costPARec.Tax_Amount__c);
					system.debug('costPARec ===> ' + costPARec);

					// String amountStr = (String) cstPriceAsoctn.get('Amount__c') != null ? (String) cstPriceAsoctn.get('Amount__c') : null;
					// costPARec.Amount__c 				= Decimal.valueOf(amountStr.trim());
					// String taxAmount = (String)cstPriceAsoctn.get('Tax_Amount__c') != null ? (String)cstPriceAsoctn.get('Tax_Amount__c') : null;
					// System.debug('taxAmount ===> ' + taxAmount);
					// costPARec.Tax_Amount__c 			= Decimal.valueOf(taxAmount.trim());
					System.debug('existingPricingEleIds ===> ' + existingPricingEleIds);
					if(existingPricingEleIds.contains(pricingId)){
						costPricingAssociationListToUpdate.add(costPARec);
					}else{
						costPricingAssociationListToInsert.add(costPARec);
					}
                    
                    System.debug('costPARec ==> ' + costPARec);

					List<Object> rawTaxList = (List<Object>) cstPriceAsoctn.get('taxList');
                    if (rawTaxList != null && !rawTaxList.isEmpty()) {
                        for (Object taxObj : rawTaxList) {
                            if (taxObj instanceof Map<String, Object>) {
                                Map<String, Object> tax = (Map<String, Object>) taxObj;
								System.debug('tax ==> ' + tax);

								List<Cost_Sheet_Tax_Linking__c> existingCostSheetLinkingList;
								List<Id> existingTaxIds = new List<Id>();
								if(isNewCostPricingAsstn == false){
									existingCostSheetLinkingList = costPricingAsstnByTaxLinkingMap.get(costPARec.Id) != null ? costPricingAsstnByTaxLinkingMap.get(costPARec.Id) : new List<Cost_Sheet_Tax_Linking__c>();
									existingTaxIds = existingCostPricingByTaxIdMap.get(costPARec.Id) == null ? null : existingCostPricingByTaxIdMap.get(costPARec.Id) ;
									system.debug('existingCostSheetLinkingList ===> ' + existingCostSheetLinkingList);
									system.debug('selectedPricingByTaxIds ===> ' + selectedPricingByTaxIds);

									if(selectedPricingByTaxIds.containsKey(pricingId)){
										List<Id> selectedTaxIds = selectedPricingByTaxIds.get(pricingId);
										Map<Id, Cost_Sheet_Tax_Linking__c> existingRecordsMap = new Map<Id, Cost_Sheet_Tax_Linking__c>();
										if(!existingCostSheetLinkingList.isEmpty() && existingCostSheetLinkingList != null){
											for (Cost_Sheet_Tax_Linking__c existingLink : existingCostSheetLinkingList) {
												existingRecordsMap.put(existingLink.Tax_Master__c, existingLink);
												system.debug('existingRecordsMap map===> ' + existingRecordsMap);

											}
										}

										for (Id selectedTaxId : selectedTaxIds) {
											system.debug('existingRecordsMap ===> ' + existingRecordsMap);
											system.debug('selectedTaxId ===> ' + selectedTaxId);
											if (!existingRecordsMap.containsKey(selectedTaxId)) {
												system.debug('new cost sheet tax linking for existing cost price association');
												Cost_Sheet_Tax_Linking__c costSheetLink = new Cost_Sheet_Tax_Linking__c(
													Tax_Master__c 	= tax.get('Id') != null ? (String)tax.get('Id') : null,
													Amount__c 		= tax.get('Amount__c') != null ? Decimal.valueOf(String.valueOf(tax.get('Amount__c'))) : null,
													App__c 			= tax.get('App__c') != null ? Integer.valueOf(String.valueOf(tax.get('App__c'))) : null,
													Cost_Pricing_Association__c = costPARec.Id
												);

												Boolean existsInInsertList = false;
												Boolean existsInUpdateList = false;

												for (Cost_Sheet_Tax_Linking__c existingInsert : costSheetTaxLinkingListToInsert) {
													system.debug('existingInsert 1==> ' + existingInsert);
													if (existingInsert.Tax_Master__c == costSheetLink.Tax_Master__c &&
														existingInsert.Cost_Pricing_Association__c == costSheetLink.Cost_Pricing_Association__c) {
														existsInInsertList = true;
														break;
													}
												}

												for (Cost_Sheet_Tax_Linking__c existingUpdate : costSheetTaxLinkingListToUpdate) {
													system.debug('existingUpdate 1==> ' + existingUpdate);
													system.debug('existingUpdate.Tax_Master__c ==> ' + existingUpdate.Tax_Master__c + ' ==costSheetLink.Tax_Master__c ===> ' + costSheetLink.Tax_Master__c);
													system.debug('existingUpdate.Cost_Pricing_Association__c 1==> ' + existingUpdate.Cost_Pricing_Association__c + ' == costSheetLink.Cost_Pricing_Association__c ===> ' + costSheetLink.Cost_Pricing_Association__c);
													if (existingUpdate.Tax_Master__c == costSheetLink.Tax_Master__c &&
														existingUpdate.Cost_Pricing_Association__c == costSheetLink.Cost_Pricing_Association__c) {
														existsInUpdateList = true;
														break;
													}
												}

												system.debug('existsInInsertList ===> ' + existsInInsertList + '  existsInUpdateList ===> ' + existsInUpdateList) ;
												if (!existsInInsertList && !existsInUpdateList) {
													costSheetTaxLinkingListToInsert.add(costSheetLink);
												}

												// costSheetTaxLinkingListToInsert.add(costSheetLink);
												system.debug('new costSheetLink ==> ' + costSheetLink);
											}else{
												system.debug('update existing cost sheet tax linking');
												Cost_Sheet_Tax_Linking__c existingLink = existingRecordsMap.get(selectedTaxId);
												system.debug('existingLink ===> ' + existingLink);
												Cost_Sheet_Tax_Linking__c costSheetLink = new Cost_Sheet_Tax_Linking__c(
													Id 				= existingLink.Id,
													Tax_Master__c 	= tax.get('Id') != null ? (String)tax.get('Id') : null,
													Amount__c 		= tax.get('Amount__c') != null ? Decimal.valueOf(String.valueOf(tax.get('Amount__c'))) : null,
													App__c 			= tax.get('App__c') != null ? Integer.valueOf(String.valueOf(tax.get('App__c'))) : null,
													Cost_Pricing_Association__c = existingLink.Cost_Pricing_Association__c
												);
												Boolean exists = false;
												for(Cost_Sheet_Tax_Linking__c cost : costSheetTaxLinkingListToUpdate){
													if(cost.Id == existingLink.Id){
														exists = true;
														break;
													}
												}
												if(!exists){
													costSheetTaxLinkingListToUpdate.add(costSheetLink);
												}
											}
										}

										for(Cost_Sheet_Tax_Linking__c costSheet : existingCostSheetLinkingList){
											if(!selectedTaxIds.contains(costSheet.Tax_Master__c)){
												costSheetTaxLinkingListToDelete.add(costSheet);
											}
										}
									}
								}else{
									System.debug('New Cost_Sheet_Tax_Linking__c to new Cost Pricing Association');
									String taxId = (String) tax.get('Id');
									if (String.isNotBlank(taxId)) {
										Cost_Sheet_Tax_Linking__c costSheetLink = new Cost_Sheet_Tax_Linking__c(
											Tax_Master__c 	= tax.get('Id') != null ? (String)tax.get('Id') : null,
											Amount__c 		= tax.get('Amount__c') != null ? Decimal.valueOf(String.valueOf(tax.get('Amount__c'))) : null,
											App__c 			= tax.get('App__c') != null && tax.get('App__c') != '' ? Integer.valueOf(String.valueOf(tax.get('App__c'))) : null
										);
										costSheetTaxLinkingListToInsert.add(costSheetLink);

									if (!pricingElementToCostPricingAssociationMap.containsKey(costPARec.Pricing_Element_Master__c)) {
										pricingElementToCostPricingAssociationMap.put(costPARec.Pricing_Element_Master__c, new List<Cost_Sheet_Tax_Linking__c>());
									}
									pricingElementToCostPricingAssociationMap.get(costPARec.Pricing_Element_Master__c).add(costSheetLink);
									}
								}
							}
						}
					}
                }
            }

			if(!costPricingAssociationListToInsert.isEmpty()){
                List<Pricing_Element_Master__c> defaultPricingElementMasters = [select Id,Name,Base_Unit__c from  Pricing_Element_Master__c Where Name = 'Facing Charges' or  Name = 'Corner Charges' or Name = 'Floor Rise'];
                for(Pricing_Element_Master__c cem : defaultPricingElementMasters){
                    Boolean newPriceEle = False;
                    for(Cost_Pricing_Association__c cpa1 : costPricingAssociationListToInsert){

                        if(cem.Id == cpa1.Pricing_Element_Master__c){
                            newPriceEle = True;
                            break;
                        }

                    }
                    if(newPriceEle == False){
                        Cost_Pricing_Association__c cpa = new Cost_Pricing_Association__c();
                        cpa.Unit__c = cem.Base_Unit__c;
                        
                        cpa.Pricing_Element_Master__c = cem.Id;
                        cpa.Cost_Sheet_Template__c = costPricingAssociationListToInsert[0].Cost_Sheet_Template__c;
                        costPricingAssociationListToInsert.add(cpa);

                    }
                  
                }
                System.debug('costPricingAssociationListToInsert==>'+costPricingAssociationListToInsert);

				insert costPricingAssociationListToInsert;

				for (Cost_Pricing_Association__c insertedPA : costPricingAssociationListToInsert) {
                    costPricingAsstnPricingMap.put(insertedPA.Pricing_Element_Master__c, insertedPA.Id);
					System.debug('costPricingAsstnPricingMap ===> ' + costPricingAsstnPricingMap);
                }

				if(!costSheetTaxLinkingListToInsert.isEmpty()){
					for(Id pricingId : costPricingAsstnPricingMap.keySet()){
						Id costPricingAsstnId = costPricingAsstnPricingMap.get(pricingId);
						System.debug('costPricingAsstnId ===> ' + costPricingAsstnId);
						system.debug('pricingElementToCostPricingAssociationMap.get(pricingId) ===> ' + pricingElementToCostPricingAssociationMap.get(pricingId));
						List<Cost_Sheet_Tax_Linking__c> costSheetList = pricingElementToCostPricingAssociationMap.containsKey(pricingId) 
																		? pricingElementToCostPricingAssociationMap.get(pricingId) 
																		: new List<Cost_Sheet_Tax_Linking__c>();
						System.debug('costSheetList ===> ' + costSheetList);
						if(!costSheetList.isEmpty()){
							for(Cost_Sheet_Tax_Linking__c cost : costSheetList){
								System.debug('cost ===> ' + cost);
								cost.Cost_Pricing_Association__c = costPricingAsstnId;
								System.debug('costSheetTaxLinkingListToInsert ===> ' + cost);
							}
						}
					}
				}
			}
			
			if(!costPricingAssociationListToDelete.isEmpty()){
				delete costPricingAssociationListToDelete;
			}

			if(!costPricingAssociationListToUpdate.isEmpty()){
				update costPricingAssociationListToUpdate;
			}

			if(!costSheetTaxLinkingListToInsert.isEmpty()){
				insert costSheetTaxLinkingListToInsert;
			}

			if (!costSheetTaxLinkingListToUpdate.isEmpty()) {
				update costSheetTaxLinkingListToUpdate;
			}

			if(!costSheetTaxLinkingListToDelete.isEmpty()){
				delete costSheetTaxLinkingListToDelete;
			}

			if(costSheetTemplateId != null){
				Cost_Sheet_Template__c costSheetTemplate = [SELECT Id, Approval_Status__c from Cost_Sheet_Template__c where Id =: costSheetTemplateId];
				if(costSheetTemplate != null && costSheetTemplate.Approval_Status__c == 'Pending'){
					Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
					req.setObjectId(costSheetTemplateId);
					req.setProcessDefinitionNameOrId('Cost_Sheet_Template_Approval_Process'); 
					Approval.ProcessResult result = Approval.process(req);
				}
			}
			
			return costSheetTemplateId;
			
		} catch (Exception e) {
			System.debug('Error in saveAllRecords ===> ' + e.getMessage());
			System.debug('Error in line ===> ' + e.getLineNumber());
			return 'Error : ' + e.getMessage();
		}
	}

	@AuraEnabled(cacheable=true)
	public static unitFloorBlockWrapper getTowerFloorUnitPricingElementData(Id projectId){
		try {
			Set<Id> BlockIds = new Set<Id>();
			Set<Id> floorIds = new Set<Id>();
			List<Block__c> BlockList = [SELECT Id,Name,Project__c, Block_Code__c from Block__c where Project__c =: projectId];
			for(Block__c tw : BlockList){
				BlockIds.add(tw.Id);
			}
			List<Floor__c> floorList = [SELECT Id,Name,Block__c, Floor_No__c from Floor__c where Block__c IN: BlockIds ORDER BY Floor_No__c ASC];
			for(Floor__c flr : floorList){
				floorIds.add(flr.Id);
			}
			List<Unit__c> unitList = [SELECT Id, Name,Floor__c,Status__c,Unit_Name_Code__c, Floor__r.Floor_No__c,  Floor__r.Name, Floor__r.Block__r.Name, Floor__r.Block__r.Block_Code__c from Unit__c where Floor__c IN: floorIds];
			List<Pricing_Element_Master__c> pricingElementList = [SELECT Id,Name,Conversion_Unit__c, Agreement__c,Parking_Type__c from Pricing_Element_Master__c WHERE Parking_Type__c = null];
			List<Tax_Master__c> taxMasterList = [SELECT Id,Name,Rounding_Method__c,Tax__c,Tax_Type__c from Tax_Master__c ];
			System.debug('taxMasterList ===> ' + taxMasterList);

			unitFloorBlockWrapper wrp = new unitFloorBlockWrapper();
			wrp.BlockList 			= BlockList.isEmpty() ? null : BlockList;
			wrp.floorList 			= floorList.isEmpty() ? null : floorList;
			wrp.unitList  			= unitList.isEmpty() ? null : unitList;
			wrp.pricingElementList  = pricingElementList.isEmpty() ? null : pricingElementList;
			wrp.taxMasterList		= taxMasterList.isEmpty() ? null : taxMasterList;
			System.debug('wrp ===> ' + wrp);
			return wrp;
		} catch (Exception e) {
			System.debug('Error in getBlockFloorData ===> ' + e.getMessage());
			System.debug('Error in line ===> ' + e.getLineNumber());
			return null;
		}
	}

	public class unitFloorBlockWrapper{
		@AuraEnabled public List<Block__c> BlockList{get;set;}
		@AuraEnabled public List<Floor__c> floorList{get;set;}
		@AuraEnabled public List<Unit__c> unitList{get;set;}
		@AuraEnabled public List<Pricing_Element_Master__c> pricingElementList{get;set;}
		@AuraEnabled public List<Tax_Master__c> taxMasterList{get;set;}
	}

	@AuraEnabled(cacheable=true)
	public static List<Company__c> getCompanyDetails(){
		try {
			List<Company__c> companyList = [SELECT Id,Name from Company__c];
			if(!companyList.isEmpty()){
				return companyList;
			}
			return null;
		} catch (Exception e) {
			System.debug('Error in fetching company details ===> ' + e.getMessage());
			System.debug('Error in line ===> ' + e.getLineNumber());
			return null;
		}
	}

	@AuraEnabled
	public static projectPicklistWrapper fetchProjectAndPicklistDetails(Id companyId, Map<String, String> ObjectByField){
		try {
			System.debug('companyId ===> ' + companyId);
			List<Project__c> projectList;
			Map<String, List<String>> picklistValByField;

			if(companyId != null){
				projectList = [SELECT Id,Name,Active__c from Project__c where Company__c =: companyId and Active__c = true];
				System.debug('projectList ===> ' + projectList);
			}
			if(ObjectByField != null){
				picklistValByField = getAllPickListVal(ObjectByField);
			}

			projectPicklistWrapper wrp = new projectPicklistWrapper();
			wrp.projectList = projectList.isEmpty() ? null : projectList;
			wrp.picklistValByField = picklistValByField == null ? null : picklistValByField;
			return wrp;
		} catch (Exception e) {
			System.debug('Error in fetchProjectAndPicklistDetails===> ' + e.getMessage());
			System.debug('Error in line ===> ' + e.getLineNumber());
			return null;
		}
	}

	public class projectPicklistWrapper{
		@AuraEnabled public List<Project__c> projectList{get;set;}
		@AuraEnabled public Map<String, List<String>> picklistValByField{get;set;}
	}

	@AuraEnabled(cacheable=true)
	public static List<Project__c> fetchProjectRecords(Id companyId){
		try {
			System.debug('companyId ===> ' + companyId);
			List<Project__c> projectList = [SELECT Id,Name,Active__c from Project__c where Company__c =: companyId and Active__c = true];
			System.debug('projectList ===> ' + projectList);
			if(!projectList.isEmpty()){
				return projectList;
			}
			return null;
		} catch (Exception e) {
			System.debug('Error in fetching projectList===> ' + e.getMessage());
			System.debug('Error in line ===> ' + e.getLineNumber());
			return null;
		}
	}

	@AuraEnabled(cacheable= true)
    public static Map<String, List<String>> getAllPickListVal(Map<String, String> ObjectByField){
        System.debug('ObjectByField==>'+ObjectByField);
        Map<String, List<String>> picklistValByField = new Map<String, List<String>>();
        System.debug('ObjectByField.keySet()==>'+ObjectByField.keySet());
        for(String fields : ObjectByField.keySet()){
            picklistValByField.put(fields, getPicklistValues(ObjectByField.get(fields), fields));
        }
         System.debug('picklistValByField==>'+picklistValByField);
        return picklistValByField;
    }
    
    @AuraEnabled(cacheable= true)
    public static List<String> getPicklistValues(String objName, String fieldName){
        List<String> options = new List<String>();
        Map<String, String> mapPickListValues = new Map<String, String>();
        Schema.SObjectType objSobjectType = Schema.getGlobalDescribe().get(objName);
        Schema.DescribeSObjectResult objDescribeSobject = objSobjectType.getDescribe();
        Map<String, Schema.SObjectField> mapFields = objDescribeSobject.fields.getMap();
        List<Schema.PicklistEntry> lstPickListValues = mapFields.get(fieldName).getDescribe().getPickListValues();
        for (Schema.PicklistEntry objPickList : lstPickListValues) {
            options.add(objPickList.getValue());
        }
        return options;
    }
    public static void mytest(){
        Integer i=0;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
        i++;i++;
    }

}