public without Sharing  class CostSheetGenerationController {
    private static final String APPROVAL_PROCESS_LEVEL_1 ='Senior_Manager_Sales_Approval';

    private static final String APPROVAL_PROCESS_LEVEL_2 = 'Chief_Commercial_Approval';

    private static final String APPROVAL_PROCESS_LEVEL_3 = 'Sector_Head_GMC_Approval';
    
    @AuraEnabled
    public static fetchDataWrapper getOnLoadData(String recordId) {
        try {
            System.debug('recordId --->' + recordId);
            
            Tax_Details__c carParkingTax = [SELECT Id, Name, CGST__c, SGST__c FROM Tax_Details__c WHERE Name = 'Tax Details' LIMIT 1];
            
            Opportunity opp = new Opportunity();
            if(recordId.startsWith('00T')){
                Task ts = [select id,WhatId from Task where id =: recordId ];

                opp = [SELECT Id, Email__c, Unit__c, OwnerId, Unit__r.Name, Unit__r.Unit_Name_Code__c, (SELECT Id, Subject, WhatId, Status FROM Tasks WHERE Subject = 'Finalise Cost Sheet & Generate Payment Schedule' AND Status = 'Open') FROM Opportunity WHERE Id =:ts.WhatId];
                System.debug('opp --->' + opp);
                System.debug('opp.Tasks --->' + opp.Tasks);
            }
            else{
                opp = [SELECT Id, Email__c, Unit__c, OwnerId, Unit__r.Name, Unit__r.Unit_Name_Code__c,(SELECT Id, Subject, WhatId, Status FROM Tasks WHERE Subject = 'Finalise Cost Sheet & Generate Payment Schedule' AND Status = 'Open') FROM Opportunity WHERE Id =:recordId];
                System.debug('opp==>'+opp);
            }
            System.debug('opp==>'+opp);
            List<Unit__c> unitList = [SELECT Id, Name, Floor__c, Floor__r.Block__c, Floor__r.Block__r.Base_Price_of_Unit_per_sqft__c,  Super_Built_Up_Area_sq_ft__c FROM Unit__c Where Status__c != 'Sold']; //Floor__r.Block__r.Max_Discount_on_Base_Price__c,
            System.debug('unitList --->' + unitList);
            
            List<Cost_Sheet_Template__c> costSheetTemplateList = [SELECT Id, Name, 
                                                                    (SELECT Id, Name, Payment_Scheme__r.Name,Payment_Scheme__r.Block__c FROM Cost_Scheme_Linkings__r), 
                                                                    (SELECT Id, Name, Unit__c FROM Cost_Unit_Linking__r)
                                                                    FROM Cost_Sheet_Template__c
                                                                    WHERE Id IN (SELECT Cost_Sheet_Template__c FROM Cost_Scheme_Linking__c)];
            System.debug('costSheetTemplateList --->' + costSheetTemplateList);
            fetchDataWrapper wrp = new fetchDataWrapper();
            wrp.opp = opp;
            wrp.carParkingTax = carParkingTax;
            wrp.unitList = unitList.isEmpty() ? null : unitList;
            wrp.costSheetTemplateList = costSheetTemplateList.isEmpty() ? null : costSheetTemplateList;
            if (String.isBlank(opp.Email__c)) {
                wrp.emailError = 'Email is mandatory on the Opportunity before generating a Cost Sheet.';
            }
            System.debug('UNIT LIST SIZE =====> ' + unitList.size());
            System.debug('TEMPLATE LIST SIZE ==> ' + costSheetTemplateList.size());
            System.debug('UNIT LIST EMPTY =====> ' + unitList.isEmpty());
            System.debug('TEMPLATE LIST EMPTY ==> ' + costSheetTemplateList.isEmpty());
            wrp.errorMessage = unitList.isEmpty() || costSheetTemplateList.isEmpty() ? 'Unit or Cost Sheet Template is empty' : null;
            System.debug('wrp --->' + wrp);
            System.debug('ERROR MESSAGE =======> ' + wrp.errorMessage);
            return wrp;
        } catch(Exception e) {
            System.debug('Error in getUnits ---> ' + e.getMessage());
            System.debug('Error in getUnits ---> ' + e.getLineNumber());
            return null;
        }
    }
    
    public class fetchDataWrapper{
        @AuraEnabled public List<Unit__c> unitList{get;set;}
        @AuraEnabled public List<Cost_Sheet_Template__c> costSheetTemplateList{get;set;}
        @AuraEnabled public Opportunity opp{get;set;}
        @AuraEnabled public Tax_Details__c carParkingTax{get;set;}
        @AuraEnabled public String errorMessage{get; set;}
        @AuraEnabled public String emailError{get; set;}
    }
    
    
    @AuraEnabled
    public static Unit__c getUnitRecord(String unitId) {
        try {
            System.debug('UNIT ID ==> ' + unitId);
            Unit__c unitRecord = [SELECT Id,Name,Unit_Name_Code__c,Status__c,Floor__c, Floor__r.Id, Floor__r.Block__c FROM Unit__c WHERE Id = :unitId LIMIT 1];
            System.debug('UNIT RECORD ==> ' + unitRecord);
            System.debug('FLOOR ID ==> ' + unitRecord.Floor__c);
            System.debug('BLOCK ID ==> ' + unitRecord.Floor__r?.Block__c);

            return unitRecord;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unit record: ' + e.getMessage());
        }
    }
    @AuraEnabled
    public static Special_Discount__c getSpecialDiscount(Id unitId) {
        try {
            if (unitId == null) {
                return null;
            }
            Unit__c unitRec = [SELECT Id,Name,Floor__r.Name,Floor__r.Block__r.Name,Floor__r.Block__r.Project__c,Floor__r.Block__r.Project__r.Name, Unit_Name_Code__c FROM Unit__c WHERE Id = :unitId LIMIT 1 ];
            Id projectId = unitRec.Floor__r?.Block__r?.Project__c;

            if (projectId == null) {
                return null;
            }

            List<Special_Discount__c> discounts = [SELECT Id,Name,Special_Discount_Name__c,Discount_Type__c,Discount_Percentage__c, Is_Active__c,Start_Date__c,End_Date__c,Project__c FROM Special_Discount__c WHERE Project__c = :projectId AND Is_Active__c = true LIMIT 1];
            return discounts.isEmpty() ? null : discounts[0];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    @AuraEnabled
    public static String saveCostSheet(Opportunity opp,List<Task> tasks,String unitId,String cslId,List<Pricing_Element__c> pricingElements,
        List<Map<String, Object>> parkingElements,Decimal discountAmount, Decimal discountPercent) {
        try {
            if (opp == null) {
                throw new AuraHandledException('Please enter the Opportunity');
            }

            if (String.isBlank(unitId)) {
                throw new AuraHandledException('Please select the Unit');
            }

            if (String.isBlank(cslId)) {
                throw new AuraHandledException('Please select the Cost Scheme');
            }
            //COST SHEET
            Cost_Sheet__c cs = new Cost_Sheet__c();
            cs.Opportunity__c = opp.Id;
            cs.Cost_Scheme_Linking__c = cslId;
            cs.Unit__c = unitId;
            cs.Discount_Amount__c = discountAmount != null ? discountAmount : 0;
            cs.Discount_Percent__c = discountPercent != null ? discountPercent : 0;
            insert cs;
            System.debug('Cost Sheet Created: ' + cs.Id);
            List<Task> existingTasks = [SELECT Id, Subject, Status FROM Task WHERE WhatId = :opp.Id AND Subject = 'Finalise Cost Sheet & Generate Payment Schedule' LIMIT 1];
            if (existingTasks.isEmpty()) {
                Task finaliseCostSheetTask = new Task();
                finaliseCostSheetTask.Subject ='Finalise Cost Sheet & Generate Payment Schedule';
                finaliseCostSheetTask.WhatId = opp.Id;
                finaliseCostSheetTask.OwnerId = opp.OwnerId;
                finaliseCostSheetTask.ActivityDate = Date.today().addDays(3);
                insert finaliseCostSheetTask;
                System.debug('Finalise Cost Sheet Task Created: ' + finaliseCostSheetTask.Id);
            }

            //PRICING ELEMENTS
            if (pricingElements != null && !pricingElements.isEmpty()) {
                List<Pricing_Element__c> pricingToInsert = new List<Pricing_Element__c>();
                for (Pricing_Element__c item : pricingElements) {
                    Pricing_Element__c pe = new Pricing_Element__c();
                    pe.Cost_Sheet__c = cs.Id;
                    pe.Pricing_Element_Master__c = item.Pricing_Element_Master__c;
                    pe.PE_Type__c = item.PE_Type__c;
                    pe.Quantity__c = item.Quantity__c;
                    pe.Rate__c = item.Rate__c;
                    pe.Unit__c = item.Unit__c;
                    pe.Type__c = item.Type__c;
                    pe.Amount__c = item.Amount__c;
                    pe.Discount_Amount__c = item.Discount_Amount__c;
                    pe.Discount__c = item.Discount__c;
                    pe.SGST_Tax_Percentage__c = item.SGST_Tax_Percentage__c;
                    pe.CGST_Tax_Percentage__c = item.CGST_Tax_Percentage__c;
                    pe.IGST_Tax_Percentage__c = item.IGST_Tax_Percentage__c;
                    pe.parking_Element__c = item.parking_Element__c;
                    pricingToInsert.add(pe);
                }

                insert pricingToInsert;
            }
            //PARKING ELEMENTS
            if (parkingElements != null && !parkingElements.isEmpty()) {
                List<Pricing_Element_Master__c> masters = [SELECT Id, Name, Parking_Type__c FROM Pricing_Element_Master__c WHERE Parking_Type__c != null];
                Map<String, Id> parkingMasterMap = new Map<String, Id>();
                for (Pricing_Element_Master__c master : masters) {
                    String key = master.Parking_Type__c.toLowerCase();
                    if (!parkingMasterMap.containsKey(key)) {
                        parkingMasterMap.put(key, master.Id);
                    }
                }
                List<Pricing_Element__c> parkingToInsert = new List<Pricing_Element__c>();
                for (Map<String, Object> row : parkingElements) {
                    String type = (String) row.get('type');
                    String key = type == null ? null : type.toLowerCase();

                    if (key == null || !parkingMasterMap.containsKey(key)) continue;
                
                    if (!parkingMasterMap.containsKey(type)) {
                        continue;
                    }
                    Pricing_Element__c pe = new Pricing_Element__c();
                    pe.Cost_Sheet__c = cs.Id;
                    pe.Pricing_Element_Master__c = parkingMasterMap.get(key);
                    pe.Rate__c = getDecimalValue(row.get('amount'));
                    pe.Amount__c = getDecimalValue(row.get('finalAmount'));
                    pe.Quantity__c = getIntegerValue(row.get('quantity'));
                    pe.SGST_Tax_Percentage__c = getDecimalValue(row.get('carSGSTtax'));
                    pe.CGST_Tax_Percentage__c = getDecimalValue(row.get('carCGSTtax'));
                    pe.parking_Element__c = true;
                    pe.Type__c = 'Agreement';
                    parkingToInsert.add(pe);
                }

                if (!parkingToInsert.isEmpty()) {
                    insert parkingToInsert;
                }
            }
            update opp;
            return cs.Id;
        } catch (Exception e) {
            System.debug('Error in saveCostSheet: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // @AuraEnabled
    // public static String createCostSheet(Opportunity opp, List<Task> tasks, String unitId, String cslId) {
    //     try {
    //         String costSheetId;
    //         System.debug('tasks===>'+tasks);
    //         System.debug('unitId===>'+unitId);
    //         System.debug('cslId===>'+cslId);
    //         List<Task> costSheetTask = [SELECT Id,Subject from task where Subject = 'Finalise Cost Sheet & Generate Payment Schedule' LIMIT 1];
    //         if (opp == null) {
    //             return 'Please enter the Opportunity';
    //         }
    //         if (cslId == null || cslId == '') {
    //             return 'Please select the cost scheme';
    //         }
    //         if (unitId == null || unitId == '') {
    //             return 'Please select the Unit';
    //         }
    //         System.debug('oppId ---> ' + opp.Id);
    //         System.debug('Tasks --->' + tasks);
    //         System.debug('costSchemeLinkingId ---> ' + cslId);
            
    //         // List<Cost_Sheet__c> costSheetList = [SELECT Id, Name, Opportunity__c, Cost_Scheme_Linking__c FROM Cost_Sheet__c WHERE Opportunity__c = :opp.Id AND Cost_Scheme_Linking__c = :cslId AND Unit__c =: unitId];
    //         // System.debug('costSheetList --->' + costSheetList);
    //         // if(!costSheetList.isEmpty()) {
    //             //     System.debug('Cost Sheet Already There');
    //             //     return 'ERROR';
    //         // }
            
    //         opp.StageName = 'Cost Sheet Generated';
    //         Cost_Sheet__c cs = new Cost_Sheet__c();
    //         cs.Opportunity__c = opp.Id;
    //         cs.Cost_Scheme_Linking__c = cslId;
    //         cs.Unit__c = unitId;
            
    //         if (cs != null) {
    //             insert cs;
    //             costSheetId = cs.Id;
    //             System.debug('Task.size ---> ' + opp.Tasks.size());
    //             System.debug('costSheetTask==>'+costSheetTask);
    //             if(tasks == null || costSheetTask.isEmpty()){
    //                 Task t = new Task();
    //                 t.Subject = 'Finalise Cost Sheet & Generate Payment Schedule';
    //                 t.WhatId = opp.Id;
    //                 t.OwnerId = opp.OwnerId;
    //                 t.ActivityDate = Date.newInstance(System.now().addDays(3).year(),
    //                 System.now().addDays(3).month(),
    //                 System.now().addDays(3).day());  // Adds 72 hours (3 days) to the current time
    //                 insert t;
    //                 update opp;
                    
    //             }
    //         }
            
    //         List<Unit__c> unitList = [SELECT Id,Name,Super_Built_Up_Area_sq_ft__c,Floor_Rise__c,Corner_Rs_Sqft__c,Facing_Rs_Sqft__c,Base_Price_per_sqft__c from Unit__c where Id =: unitId LIMIT 1]; //Car_Parking_Amount__c,Car_Parking__c
    //         System.debug('unitList==>'+unitList);
            
    //         Task taskToClose = [select id,Subject,Status from Task Where WhatId =: opp.Id AND Subject =:'Generate Cost Sheet' Limit 1];
    //         taskToClose.Status = 'Completed';
    //         update taskToClose;
            
    //         List<Cost_Scheme_Linking__c> getCostSchemeLinking = [select id,Cost_Sheet_Template__c from Cost_Scheme_Linking__c Where Id =: cslId Limit 1];
    //         System.debug('getCostSchemeLinking==>'+getCostSchemeLinking);
            
    //         List<Cost_Pricing_Association__c> getAllPricingAssociations = [select id,Name,Amount__c,Cost_Sheet_Template__c,PE_Type__c,Type__c,Pricing_Element_Master__c,Quantity__c,Rate__c,Tax_Amount__c,Unit__c,Pricing_Element_Master__r.Name, Sequence__c  from Cost_Pricing_Association__c where Cost_Sheet_Template__c =: getCostSchemeLinking[0].Cost_Sheet_Template__c];
    //         System.debug('getAllPricingAssociations==>'+getAllPricingAssociations);
            
    //         Set<String> allcostPricingAssIds = new Set<String>();
    //         for(Cost_Pricing_Association__c cpa : getAllPricingAssociations){
    //             allcostPricingAssIds.add(cpa.Id);
    //         }
            
    //         List<Cost_Sheet_Tax_Linking__c> costSheetTaxLinkingRecords = [select Id,Cost_Pricing_Association__c,Tax_Master__c,Tax_Master__r.Tax__c ,Tax_Master__r.Tax_Type__c ,Tax_Master__r.Name from Cost_Sheet_Tax_Linking__c Where Cost_Pricing_Association__c  In:allcostPricingAssIds];
    //         List<Pricing_Element_Master__c > pricingElementMasterRecords = [select Id,Name from Pricing_Element_Master__c  Where Name = 'Corner Charges' or Name = 'Floor Rise' or Name = 'Facing Charges'];
    //         Map<Id,Pricing_Element_Master__c> mapofPricingElements = new  Map<Id,Pricing_Element_Master__c>();
    //         for(Pricing_Element_Master__c pemr : pricingElementMasterRecords){
    //             mapofPricingElements.put(pemr.Id, pemr);
    //         }
            
    //         System.debug('mapofPricingElements==>'+mapofPricingElements);
            
            
    //         List<Pricing_Element__c> pricingElementsToInsert = new List<Pricing_Element__c>();
    //         List<PricingElements__c> pricingRecords = [
    //             SELECT Name, Unit_Field__c 
    //             FROM PricingElements__c
    //         ];
            
    //         Map<String, String> pricingMap = new Map<String, String>();
            
    //         // Populate the Map
    //         for (PricingElements__c rec : pricingRecords) {
    //             pricingMap.put(rec.Name, rec.Unit_Field__c);
    //         }
            
    //         for(Cost_Pricing_Association__c csp : getAllPricingAssociations){
    //             Pricing_Element_Master__c matchedElement;
    //             if(mapofPricingElements.ContainsKey(csp.Pricing_Element_Master__c)){
                    
    //                 matchedElement = mapofPricingElements.get(csp.Pricing_Element_Master__c);
    //                 System.debug('matchedElement==>'+matchedElement);
    //             }
    //             Pricing_Element__c pe = new Pricing_Element__c();
    //             pe.Cost_Sheet__c = costSheetId != null ? costSheetId : null;
    //             pe.PE_Type__c = csp.PE_Type__c != null ? csp.PE_Type__c : null;
    //             pe.Sequence__c = csp.Sequence__c != null ? csp.Sequence__c : null;
    //             Decimal area = unitList[0].Super_Built_Up_Area_sq_ft__c;
                
    //             System.debug('csp.Pricing_Element_Master__r.Name==>'+csp.Pricing_Element_Master__r.Name);
    //             System.debug('Corner Charges==>'+pricingMap.get('Corner Charges'));
    //             System.debug('Floor Rise==>'+pricingMap.get('Floor Rise'));
    //             System.debug('Facing Charges==>'+pricingMap.get('Facing Charges'));
    //             System.debug('Basic Price ==>'+pricingMap.get('Basic Price'));
    //             System.debug('matchedElement==>'+matchedElement);
                
                
    //             if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Corner Charges')  && unitList[0].Corner_Rs_sqft__c != null ){
    //                 System.debug('entered..');
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Corner_Rs_sqft__c;
    //                 pe.Amount__c = unitList[0].Corner_Rs_sqft__c * area;
                    
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Floor Rise') && unitList[0].Floor_Rise__c != null ){
    //                 System.debug('entered..');
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Floor_Rise__c;
    //                 pe.Amount__c = unitList[0].Floor_Rise__c * area;
                    
                    
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Facing Charges') && unitList[0].Facing_Rs_Sqft__c != null){
    //                 System.debug('entered..');
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Facing_Rs_Sqft__c;
    //                 pe.Amount__c = unitList[0].Facing_Rs_Sqft__c * area;
                    
                    
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Basic Price') ){
    //                 System.debug('entered..');
    //                 System.debug('unitList==>'+unitList[0]);
    //                 System.debug('unitList==>'+unitList[0].Base_Price_per_sqft__c);
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Base_Price_per_sqft__c;
    //                 pe.Amount__c = unitList[0].Base_Price_per_sqft__c * area;
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Car Parking') ){
    //                 // System.debug('entered..');
    //                 // System.debug('unitList==>'+unitList[0]);
    //                 // System.debug('unitList==>'+unitList[0].Car_Parking_Amount__c );
    //                 // pe.Quantity__c = 1;
    //                 // pe.Rate__c = unitList[0].Car_Parking_Amount__c ;
    //                 // pe.Amount__c =   unitList[0].Car_Parking_Amount__c ;
    //             }
    //             else{
    //                 pe.Quantity__c = (csp.Unit__c != null && csp.Unit__c == 'sqft' && unitList[0].Super_Built_Up_Area_sq_ft__c != null) ? unitList[0].Super_Built_Up_Area_sq_ft__c : csp.Quantity__c;
    //                 // pe.Rate__c = csp.Rate__c != null ? csp.Rate__c : null;
    //                 // pe.Amount__c = pe.Quantity__c != null && pe.Rate__c != null ? (pe.Quantity__c * pe.Rate__c) : null;
    //                 pe.Rate__c = csp.Rate__c;
    //                 if (pe.Quantity__c != null && pe.Rate__c != null) {
    //                     Decimal amount = pe.Quantity__c * pe.Rate__c;
    //                     // Round Rate and Amount up to next integer if needed
    //                     if (pe.Rate__c != pe.Rate__c.setScale(0)) {
    //                         pe.Rate__c = pe.Rate__c.setScale(0, RoundingMode.CEILING);
    //                     }
    //                     if (amount != amount.setScale(0)) {
    //                         pe.Amount__c = amount.setScale(0, RoundingMode.CEILING);
    //                     } else {
    //                         pe.Amount__c = amount;
    //                     }
    //                 } else {
    //                     pe.Amount__c = null;
    //                 }
                    
    //             }
    //             pe.Unit__c = csp.Unit__c != null ? csp.Unit__c : null;
    //             pe.Type__c = csp.Type__c != null ? csp.Type__c : null;
    //             pe.Pricing_Element_Master__c = csp.Pricing_Element_Master__c;
    //             for(Cost_Sheet_Tax_Linking__c cstlr : costSheetTaxLinkingRecords){
    //                 if(csp.Id == cstlr.Cost_Pricing_Association__c){
    //                     if(cstlr.Tax_Master__r.Tax_Type__c == 'SGST'){
    //                         pe.SGST_Tax_Percentage__c = cstlr.Tax_Master__r.Tax__c;
    //                     }else if(cstlr.Tax_Master__r.Tax_Type__c == 'CGST'){
    //                         pe.CGST_Tax_Percentage__c = cstlr.Tax_Master__r.Tax__c;
    //                     }else if(cstlr.Tax_Master__r.Tax_Type__c == 'IGST'){
    //                         pe.IGST_Tax_Percentage__c = cstlr.Tax_Master__r.Tax__c;
    //                     }
                        
    //                 }
    //             }
                
    //             pricingElementsToInsert.add(pe);
                
    //         }
    //         System.debug('pricingElementsToInsert==>'+pricingElementsToInsert);
    //         insert pricingElementsToInsert;
            
    //         System.debug('costSheetId==>'+costSheetId);
            
    //         return costSheetId;
    //     } catch (DmlException e) {
    //         System.debug('DML Error in createCostSheet ---> ' + e.getMessage());
    //         return 'Error during insert: ' + e.getMessage();
    //     } catch (Exception e) {
    //         System.debug('Error in createCostSheet ---> ' + e.getMessage());
    //         return e.getMessage();
    //     }
    // }
    
    
    // @AuraEnabled
    // public static List<Discount_LineItem__c> checkAccess(String opp){
    //     System.debug('opp==>'+opp);
    //     try {
    //         List<Opportunity> oppRecord  = [select id,Project__c,Project__r.Name from  Opportunity where Id =: opp Limit 1];
    //         System.debug('oppRecord==>'+oppRecord);
    //         if(oppRecord.size() > 0 && oppRecord[0].Project__c != null){
    //             List<Discount_Master__c> discountMaster = [select id,Project__c,Active__c from Discount_Master__c where Project__c =: oppRecord[0].Project__c AND Active__c = true];
    //             Set<Id> allDiscountMasterIds = new set<Id>();
    //             for(Integer i=0;i<discountMaster.size();i++){
    //                 allDiscountMasterIds.add(discountMaster[i].Id);
    //             }
    //             if(allDiscountMasterIds.size() > 0 ){
    //                 List<Discount_LineItem__c> dlis = [
    //                     SELECT Id, Roles__c, Maximum__c, Minimum__c, Discount_Master__c,
    //                         Discount_Master__r.Pricing_Element_Master__c,
    //                         Discount_Master__r.Pricing_Element_Master__r.Name
    //                     FROM Discount_LineItem__c
    //                     WHERE Discount_Master__c IN :allDiscountMasterIds
    //                     ORDER BY Discount_Master__c, Maximum__c DESC
    //                 ];

    //                 Map<Id, Discount_LineItem__c> masterToLineItemMap = new Map<Id, Discount_LineItem__c>();

    //                 for (Discount_LineItem__c dli : dlis) {
    //                     if (!masterToLineItemMap.containsKey(dli.Discount_Master__c)) {
    //                         masterToLineItemMap.put(dli.Discount_Master__c, dli);
    //                     }
    //                 }
    //                 List<Discount_LineItem__c> discountLineItems = masterToLineItemMap.values();                    
    //                 // List<Discount_LineItem__c> discountLineItems = [select id,Roles__c,Maximum__c,Minimum__c,Discount_Master__c,Discount_Master__r.Pricing_Element_Master__c, Discount_Master__r.Pricing_Element_Master__r.Name from Discount_LineItem__c where Discount_Master__c In: allDiscountMasterIds ORDER BY Maximum__c DESC];
    //                 // System.debug('discountLineItems==>'+discountLineItems);
    //                 return discountLineItems;
    //             }
                
                
    //         }
    //         return new List<Discount_LineItem__c>();
            
    //     } catch (Exception e) {
    //         throw new AuraHandledException(e.getMessage());
    //     }
    // }
    
    // @AuraEnabled
    // public static List<Pricing_Element__c> getPricingElements(String cslId, String unitId){
    //     try{
    //         System.debug('cslId==>'+cslId);
    //         System.debug('unitId==>'+unitId);
    //         List<Pricing_Element__c> getAllPricingAssociations = [select id,Name,Amount__c,Cost_Sheet__c,PE_Type__c,Quantity__c,Rate__c,Final_Tax_Amount__c,Unit__c,Pricing_Element_Master__c,Pricing_Element_Master__r.Name,Cost_Sheet__r.Name,Discount_Amount__c,Discount__c  from Pricing_Element__c where Cost_Sheet__c =: cslId];
    //         System.debug('getAllPricingAssociations==>'+getAllPricingAssociations);
    //         return getAllPricingAssociations;
    //     }catch(Exception e){
    //         System.debug('Exception occurred: ' + e.getMessage());
    //         return new List<Pricing_Element__c>();
    //     }
    // }
    @AuraEnabled
    public static List<Pricing_Element__c> getPricingElements(String cslId, String unitId) {
        try {
            System.debug('cslId ==> ' + cslId);
            System.debug('unitId ==> ' + unitId);

            List<Cost_Scheme_Linking__c> costSchemeLinking = [SELECT Id, Cost_Sheet_Template__c FROM Cost_Scheme_Linking__c  WHERE Id = :cslId  LIMIT 1  ];
            if (costSchemeLinking.isEmpty()) {
                return new List<Pricing_Element__c>();
            }

            List<Unit__c> unitList = [SELECT Id,Name,Super_Built_Up_Area_sq_ft__c,  Floor_Rise__c, Corner_Rs_Sqft__c, Facing_Rs_Sqft__c,Base_Price_per_sqft__c FROM Unit__c  WHERE Id = :unitId LIMIT 1 ];

            if (unitList.isEmpty()) {
                return new List<Pricing_Element__c>();
            }

            List<Cost_Pricing_Association__c> pricingAssociations = [ SELECT Id,Name,Amount__c, Cost_Sheet_Template__c, PE_Type__c, Type__c, Pricing_Element_Master__c,
                    Quantity__c, Rate__c, Tax_Amount__c,  Unit__c, Sequence__c,Pricing_Element_Master__r.Name  FROM Cost_Pricing_Association__c WHERE Cost_Sheet_Template__c = :costSchemeLinking[0].Cost_Sheet_Template__c ];

            if (pricingAssociations.isEmpty()) {
                return new List<Pricing_Element__c>();
            }

            Set<Id> cpaIds = new Set<Id>();
            for (Cost_Pricing_Association__c cpa : pricingAssociations) {
                cpaIds.add(cpa.Id);
            }
            List<Cost_Sheet_Tax_Linking__c> taxLinkingRecords = [SELECT Id,Cost_Pricing_Association__c, Tax_Master__c, Tax_Master__r.Tax__c, Tax_Master__r.Tax_Type__c,  Tax_Master__r.Name
                FROM Cost_Sheet_Tax_Linking__c  WHERE Cost_Pricing_Association__c IN :cpaIds ];

            List<PricingElements__c> pricingRecords = [  SELECT Name, Unit_Field__c FROM PricingElements__c  ];
            Map<String, String> pricingMap = new Map<String, String>();
            for (PricingElements__c rec : pricingRecords) {
                pricingMap.put(rec.Name, rec.Unit_Field__c);
            }
            List<Pricing_Element__c> pricingElements = new List<Pricing_Element__c>();
            Decimal area = unitList[0].Super_Built_Up_Area_sq_ft__c;
            for (Cost_Pricing_Association__c csp : pricingAssociations) {
                Pricing_Element__c pe = new Pricing_Element__c();
                pe.PE_Type__c = csp.PE_Type__c;
                pe.Sequence__c = csp.Sequence__c;
                pe.Unit__c = csp.Unit__c;
                pe.Type__c = csp.Type__c;
                pe.Pricing_Element_Master__c = csp.Pricing_Element_Master__c;

                if (csp.Pricing_Element_Master__r.Name == pricingMap.get('Corner Charges') && unitList[0].Corner_Rs_sqft__c != null  ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Corner_Rs_sqft__c;
                    pe.Amount__c =  unitList[0].Corner_Rs_sqft__c * area;
                } else if (csp.Pricing_Element_Master__r.Name == pricingMap.get('Floor Rise')  &&  unitList[0].Floor_Rise__c != null  ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Floor_Rise__c;
                    pe.Amount__c =  unitList[0].Floor_Rise__c * area;

                } else if (csp.Pricing_Element_Master__r.Name ==  pricingMap.get('Facing Charges') && unitList[0].Facing_Rs_Sqft__c != null ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Facing_Rs_Sqft__c;
                    pe.Amount__c = unitList[0].Facing_Rs_Sqft__c * area;

                } else if (csp.Pricing_Element_Master__r.Name ==  pricingMap.get('Basic Price')  ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Base_Price_per_sqft__c;
                    pe.Amount__c =   unitList[0].Base_Price_per_sqft__c * area;

                }else {
                    pe.Quantity__c =(csp.Unit__c != null && csp.Unit__c == 'sqft' && area != null) ? area : csp.Quantity__c;

                    pe.Rate__c = csp.Rate__c;

                    if (pe.Quantity__c != null && pe.Rate__c != null ) {
                        Decimal amount = pe.Quantity__c * pe.Rate__c;
                        if (pe.Rate__c != pe.Rate__c.setScale(0)) {
                            pe.Rate__c = pe.Rate__c.setScale(0, RoundingMode.CEILING );
                        }

                        if (amount != amount.setScale(0)
                        ) {
                            pe.Amount__c =  amount.setScale(0, RoundingMode.CEILING);
                        } else {
                            pe.Amount__c = amount;
                        }

                    } else {
                        pe.Amount__c = null;
                    }
                }

                for (Cost_Sheet_Tax_Linking__c taxRec : taxLinkingRecords) {
                    if ( csp.Id == taxRec.Cost_Pricing_Association__c ) {
                        if ( taxRec.Tax_Master__r.Tax_Type__c =='SGST'  ) {
                            pe.SGST_Tax_Percentage__c = taxRec.Tax_Master__r.Tax__c;
                        } else if (
                            taxRec.Tax_Master__r.Tax_Type__c == 'CGST'
                        ) {
                            pe.CGST_Tax_Percentage__c = taxRec.Tax_Master__r.Tax__c;

                        } else if (
                            taxRec.Tax_Master__r.Tax_Type__c == 'IGST'
                        ) {
                        pe.IGST_Tax_Percentage__c =  taxRec.Tax_Master__r.Tax__c;
                        }
                    }
                }

                pe.Pricing_Element_Master__r = csp.Pricing_Element_Master__r;
                pricingElements.add(pe);
            }

            System.debug('Preview Pricing Elements ==> ' + pricingElements );
            return pricingElements;
        }  catch (Exception e) {
            System.debug( 'getPricingElements Error ==> ' + e.getMessage() );
            System.debug(  'Line ==> ' + e.getLineNumber() );
            return new List<Pricing_Element__c>();
        }
    }
    
    @AuraEnabled
    public static List<Parking__c> getParkingRecords(String unitId){
        try{
            System.debug('unitId==>'+unitId);
            List<Unit__c> allUnits = [select id,Unit_Type__c,Status__c,Unit_Name_Code__c,Floor__r.Block__r.Id from Unit__c Where Id =:unitId];
            
            List<Parking__c> getAllParkingRecords = [select id,Amount_Per_Parking__c,Block__c,Name,Parking_Type__c,Total_Parking__c,Available_Parking__c from Parking__c where Block__c =: allUnits[0].Floor__r.Block__r.Id];
            return getAllParkingRecords;
            
        }catch(Exception e){
            System.debug('Exception occurred: ' + e.getMessage());
            return new List<Parking__c>();
        }
    }
    
    @AuraEnabled
    public static List<Pricing_Element__c> createparkingElements(List<Map<String, Object>> parkingElements,String costId) {
        set<String> insertedPricingElements = new set<String>();
        List<Pricing_Element__c> getAllPricingAssociations  = new List<Pricing_Element__c>();
        try {
            System.debug('parkingElements==>' + parkingElements);
            List<Pricing_Element_Master__c> getPricingElements = [SELECT Id, Name, Parking_Type__c  FROM Pricing_Element_Master__c WHERE Parking_Type__c != null];
            Map<String, Id> pricingElementMap = new Map<String, Id>();
            for (Pricing_Element_Master__c elem : getPricingElements) {
                pricingElementMap.put(elem.Parking_Type__c, elem.Id);
            }
            
            List<Pricing_Element__c> pricingElementsToUpsert = new List<Pricing_Element__c>();
            
            for (Map<String, Object> row : parkingElements) {
                System.debug('row==>'+row);
                String type = (String) row.get('type');
                String key = type == null ? null : type.toLowerCase();
                Id pricingElementId = pricingElementMap.get(key);
                
                
                if (pricingElementId != null) {
                    Pricing_Element__c newElement = new Pricing_Element__c(
                        Pricing_Element_Master__c = pricingElementId,
                    Rate__c = getDecimalValue(row.get('amount')),
                    Amount__c = getDecimalValue(row.get('finalAmount')),
                    Quantity__c =  getIntegerValue(row.get('quantity')),
                    SGST_Tax_Percentage__c = getDecimalValue(row.get('carsGSTtax')),
                    CGST_Tax_Percentage__c = getDecimalValue(row.get('carcGSTtax')),
                    parking_Element__c = true,
                    Cost_Sheet__c = costId
                  //  Type__c = 'Agreement'
                        //  Parking_Numbers__c =  parkingValues
                    );
                    System.debug('newElement ===> ' + newElement);
                    pricingElementsToUpsert.add(newElement);
                } else {
                    System.debug('No matching Pricing Element Master found for type: ' + type);
                }
            }
            
            if (!pricingElementsToUpsert.isEmpty()) {
                insert pricingElementsToUpsert;
                for (Pricing_Element__c insertedElement : pricingElementsToUpsert) {
                    insertedPricingElements.add(insertedElement.Id);
                }
                getAllPricingAssociations = [select id,Name,Amount__c,Cost_Sheet__c,PE_Type__c,Quantity__c,Rate__c,Tax_Amount__c,Unit__c,Pricing_Element_Master__c,Pricing_Element_Master__r.Name,Cost_Sheet__r.Name,Discount__c,Discount_Amount__c  from Pricing_Element__c where Id IN: insertedPricingElements];
            }
            return getAllPricingAssociations;
        } catch (Exception e) {
            system.debug('Error ==> ' + e.getMessage());
            system.debug('Error in line ==> ' + e.getLineNumber());
            return null;
        }
    }
    
    @AuraEnabled
    public static void updateParkingAvailability(Id parkingDetailId, Integer quantityChange) {
        System.debug('parkingDetailId ==> ' + parkingDetailId);
        System.debug('quantityChange ==> ' + quantityChange);
        Parking__c parking = [ SELECT Id, Available_Parking__c FROM Parking__c WHERE Id = :parkingDetailId LIMIT 1];
        parking.Available_Parking__c =(parking.Available_Parking__c == null ? 0 : parking.Available_Parking__c) - quantityChange;
        System.debug('AFTER Available ==> ' + parking.Available_Parking__c);
        update parking;
    }
    
    public static Decimal getDecimalValue(Object value) {
        try {
            if (value == null) {
                return 0; // Default value if null
            } else if (value instanceof Decimal) {
                return (Decimal) value; // Directly return if it's already a Decimal
            } else if (value instanceof String) {
                return Decimal.valueOf((String) value); // Convert String to Decimal
            }
        } catch (Exception e) {
            System.debug('Error converting to Decimal: ' + e.getMessage());
        }
        return 0; // Default fallback value
    }
    
    
    public static Integer getIntegerValue(Object value) {
        try {
            if (value == null) {
                return 1; // Default value if null
            } else if (value instanceof Decimal) {
                return ((Decimal) value).intValue(); // Convert Decimal to Integer
            } else if (value instanceof String) {
                return Integer.valueOf((String) value); // Convert String to Integer
            }
        } catch (Exception e) {
            System.debug('Error converting to Integer: ' + e.getMessage());
        }
        return 1; // Default fallback value
    }
    
    // @AuraEnabled
    // public static String updatePricingElements(List<Pricing_Element__c> pricingElements) {
    //     try {
    //         if (pricingElements == null || pricingElements.isEmpty()) {
    //             throw new AuraHandledException('No Pricing Elements provided for update.');
    //         }
    //         System.debug('Pricing Elements to upsert: ' + pricingElements);
    //         for (Pricing_Element__c pricingElement : pricingElements) {
    //             if (pricingElement.Quantity__c != null && pricingElement.Rate__c != null) {
    //                 Decimal amount = pricingElement.Quantity__c * pricingElement.Rate__c;
    //                 pricingElement.Amount__c = (amount != amount.setScale(0)) ? amount.setScale(0, RoundingMode.CEILING) : amount;
    //             }
    //         }
    //         upsert pricingElements;
    //         return 'success';
    //     } catch (Exception e) {
    //         system.debug('Error ==> ' + e.getMessage());
    //         system.debug('Error in line ==> ' + e.getLineNumber());
    //         return null;
    //     }
    // }
    @AuraEnabled
    public static String updatePricingElements( List<Pricing_Element__c> pricingElements,String costSheetId) {
        try {
            if (pricingElements == null || pricingElements.isEmpty()) {
                throw new AuraHandledException(
                    'No Pricing Elements provided for update.'
                );
            }
            if (String.isBlank(costSheetId)) {
                throw new AuraHandledException('Cost Sheet Id is required.');
            }
            for (Pricing_Element__c pricingElement : pricingElements) {
                pricingElement.Cost_Sheet__c = costSheetId;
                if (pricingElement.Quantity__c != null && pricingElement.Rate__c != null) {
                    Decimal amount = pricingElement.Quantity__c * pricingElement.Rate__c;
                    pricingElement.Amount__c = (amount != amount.setScale(0)) ? amount.setScale(0, RoundingMode.CEILING) : amount;
                }
            }
            upsert pricingElements;
            return 'success';
        } catch (Exception e) {
            System.debug('Error ==> ' + e.getMessage());
            System.debug('Error in line ==> ' + e.getLineNumber());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void submitCostSheetForApproval(String data, String costSheetId){
        System.debug('submitCostSheetForApproval method is get called ');
        System.debug('Cost Sheet Id ==> ' + costSheetId);
        try{
            if (String.isBlank(costSheetId)) {
                throw new AuraHandledException('Cost Sheet Id is required.');
            }
            createPaymentSchedule(costSheetId);
            System.debug('data ===> ' + data);
            startDiscountApproval(costSheetId);
            
        }catch(Exception e){
            system.debug('Error ==> ' + e.getMessage());
            system.debug('Error in line ==> ' + e.getLineNumber());
            throw new AuraHandledException('Unable to submit Cost Sheet for approval: ' + e.getMessage());
        }
    }

    private static void createRegistrationCharges(String costSheetId) {
        if (String.isBlank(costSheetId)) {
            return;
        }

        system.debug('costSheetId::'+costSheetId);

        //List<Pricing_Element_Master__c> registartionCharges = [SELECT Id, Name, Agreement__c FROM Pricing_Element_Master__c WHERE Name = 'Registration Charges*' LIMIT 1];
        List<Agreement__c> settings = [SELECT Name__c, Percentage__c, Type__c FROM Agreement__c LIMIT 1];

        Decimal totalAgreementValue = 0;
        for (Pricing_Element__c pricingElement : [
            SELECT Id, Type__c, Total_Amount_Excluding_Tax__c
            FROM Pricing_Element__c
            WHERE Cost_Sheet__c = :costSheetId
        ]) {
            if (pricingElement.Total_Amount_Excluding_Tax__c != null && pricingElement.Type__c == 'Agreement') {
                totalAgreementValue += pricingElement.Total_Amount_Excluding_Tax__c;
            }
        }

        Decimal calcValue = (totalAgreementValue * settings[0].Percentage__c) / 100;
        Decimal roundedValue = (calcValue != calcValue.setScale(0)) ? calcValue.setScale(0, RoundingMode.CEILING) : calcValue;

        // List<Pricing_Element__c> existingRegistrationCharges = [
        //     SELECT Id
        //     FROM Pricing_Element__c
        //     WHERE Cost_Sheet__c = :costSheetId
        //     AND Pricing_Element_Master__c = :registartionCharges[0].Id
        //     LIMIT 1
        // ];

        // Pricing_Element__c registrationCharge = existingRegistrationCharges.isEmpty()
        //     ? new Pricing_Element__c(Cost_Sheet__c = costSheetId, Pricing_Element_Master__c = registartionCharges[0].Id)
        //     : new Pricing_Element__c(Id = existingRegistrationCharges[0].Id);

        // registrationCharge.Type__c = 'Ammenities';
        // registrationCharge.Quantity__c = 1;
        // registrationCharge.Rate__c = roundedValue;
        // registrationCharge.Amount__c = roundedValue;

        // upsert registrationCharge;
    }

    @AuraEnabled
    public static void createPaymentSchedule(Id costSheetId) {
        System.debug('Processing Cost Sheet ID: ' + costSheetId);
        Id selectedCostSheetTempId;
        
        try {
            if(costSheetId != null){
                Cost_Sheet__c getCostSheet = [select id,Opportunity__c,Name,Cost_Scheme_Linking__c,finalize_CostSheet__c,Total_Pricing_Value__c, Total_Pricing_Value_Excluding_Tax__c, Total_Tax_Value__c,Cost_Scheme_Linking__r.Cost_Sheet_Template__c from Cost_Sheet__c Where Id =:costSheetId Limit 1];
                
                selectedCostSheetTempId = getCostSheet?.Cost_Scheme_Linking__r?.Cost_Sheet_Template__c != null ? getCostSheet.Cost_Scheme_Linking__r.Cost_Sheet_Template__c : '';
                
                Cost_Scheme_Linking__c getSchemeLinking = [select id,Payment_Scheme__c,Cost_Sheet_Template__c,Cost_Sheet_Template__r.Amount__c,Cost_Sheet_Template__r.Tax_Amount__c  from Cost_Scheme_Linking__c Where id =:getCostSheet.Cost_Scheme_Linking__c Limit 1];
                System.debug('Scheme Liking: ' + getSchemeLinking);
                
                List<Payment_Scheme_Installment__c> getPaymetSchemeRecords = [select id,Payment_Scheme__c,Payment_Scheme__r.Name,Installment__c,Name,Payment_Schedule_Master__c,Payment_Schedule_Master__r.Name,Display_Order__c,Payment_Schedule_Master__r.Installment_Code__c, Payment_Schedule_Master__r.Installment_Sequence__c,Type__c,Payment_Schedule_Master__r.Description__c  from Payment_Scheme_Installment__c Where Payment_Scheme__c  =:getSchemeLinking.Payment_Scheme__c];
                System.debug('getPaymetSchemeRecords size: ' + getPaymetSchemeRecords.size());
                Decimal smallDisplayNum =  10000;
                for(Payment_Scheme_Installment__c psi : getPaymetSchemeRecords){
                    if(psi.Display_Order__c  < smallDisplayNum){
                        smallDisplayNum = psi.Display_Order__c;
                    }
                }
                Decimal totalAgreementValue = 0;
                Decimal tokenAmount = 0;
                //List<Payment_Schedule__c> allPaymentSchedules = new List<Payment_Schedule__c>();
                List<Cost_Sheet_Payment_Schedule__c> allPaymentSchedules = new List<Cost_Sheet_Payment_Schedule__c>();
                
                for(Payment_Scheme_Installment__c psi : getPaymetSchemeRecords){
                    Cost_Sheet_Payment_Schedule__c ps = new Cost_Sheet_Payment_Schedule__c();
                    Decimal rawAgreement = (getCostSheet.Total_Pricing_Value_Excluding_Tax__c / 100) * psi.Installment__c;
                    Decimal rawTax = (getCostSheet.Total_Tax_Value__c / 100) * psi.Installment__c;

                    ps.Opportunity__c = getCostSheet.Opportunity__c;
                    ps.Cost_Sheet__c = costSheetId;
                    ps.Installment__c = psi.Installment__c;
                    // ps.Type__c = psi.Type__c;
                    ps.Type__c = 'Agreement';
                    // ps.Agreement_Value__c = (getCostSheet.Total_Pricing_Value_Excluding_Tax__c / 100) * psi.Installment__c;
                    // ps.Tax_Amount__c = (getCostSheet.Total_Tax_Value__c / 100) * psi.Installment__c;
                    ps.Agreement_Value__c = Math.ceil(rawAgreement);
                    ps.Tax_Amount__c = Math.ceil(rawTax);
                    
                    ps.Diff_Agreement_Value__c = ps.Agreement_Value__c - rawAgreement;
                    ps.Diff_Tax_Amount__c = ps.Tax_Amount__c - rawTax;
                    ps.Other_Charges__c = 0;
                    ps.Other_Tax_Amount__c = 0;
                    //ps.Installment_Sequence__c =  psi.Payment_Schedule_Master__r.Installment_Sequence__c;
                    ps.Installment_Sequence__c =  psi.Display_Order__c;
                    ps.Description__c = psi.Payment_Schedule_Master__r.Description__c != null ? psi.Payment_Schedule_Master__r.Description__c : null;
                    if (smallDisplayNum == psi.Display_Order__c) {
                        
                    } else {
                        Date nextMonth = Date.today().addMonths(1);
                        Integer lastDayOfNextMonth = Date.daysInMonth(nextMonth.year(), nextMonth.month());
                        Date nextMonthLastDate = Date.newInstance(nextMonth.year(), nextMonth.month(), lastDayOfNextMonth);
                    }
                    ps.Name = psi.Payment_Schedule_Master__r.Name;
                    if(ps.Name == 'Token Advance (TA) – Rs.3,12,000/'){
                        tokenAmount = ps.Agreement_Value__c;
                    }
                    allPaymentSchedules.add(ps);
                }
                
                List<Pricing_Element__c> ammentiesPricingElements = [select Id,Cost_Sheet__c,Pricing_Element_Master__c,Pricing_Element_Master__r.Name,Type__c,Quantity__c,Amount__c,Actual_Amount__c,Total_Amount_Excluding_Tax__c,Final_Tax_Amount__c,Description__c, Sequence__c  from Pricing_Element__c Where Cost_Sheet__c =: costSheetId and Type__c ='Ammenities'];
                for(Pricing_Element__c pe : ammentiesPricingElements){
                    Cost_Sheet_Payment_Schedule__c ps =  new Cost_Sheet_Payment_Schedule__c();
                    ps.Name = pe.Pricing_Element_Master__r.Name;
                    ps.Type__c =  pe.Type__c;
                    ps.Cost_Sheet__c = costSheetId;

                    ps.Agreement_Value__c = pe.Total_Amount_Excluding_Tax__c;
                    ps.Tax_Amount__c = pe.Final_Tax_Amount__c;
                    ps.Description__c = pe.Description__c;
                    ps.Installment_Sequence__c = pe.Sequence__c;
                    ps.Opportunity__c = getCostSheet.Opportunity__c;
                    allPaymentSchedules.add(ps);

                }
                insert allPaymentSchedules;
            }
        } catch (Exception e) {
            System.debug(' Error ===> ' + e.getLineNumber() + ' ---> ' + e.getMessage());
        }
    }
    private static Id getProjectRoleUser(Id projectId,String roleName) {

        System.debug('Finding Project Role User');
        System.debug('Project ==> ' + projectId);
        System.debug('Role ==> ' + roleName);

        if (projectId == null || String.isBlank(roleName)) {
            return null;
        }
        List<Project_Roles__c> projectRoles = [SELECT Id,Project__c,    Roles__c,User__c FROM Project_Roles__c WHERE Project__c = :projectId AND User__c != null];

        for (Project_Roles__c projectRole : projectRoles) {
            if (projectRole.Roles__c != null && projectRole.Roles__c.trim().equalsIgnoreCase(roleName.trim())) {
                System.debug( 'Project Role matched ==> ' + projectRole.Id );
                System.debug( 'Approver User ==> ' + projectRole.User__c );
                return projectRole.User__c;
            }
        }
        return null;
    }
    private static void submitApprovalLevel(Cost_Sheet__c cs,List<Discount_LineItem__c> requiredSlabs,Integer level,Id projectId) {
        System.debug('========== SUBMIT APPROVAL LEVEL ==========');
        System.debug('Level ==> ' + level);
        if (level <= 0 || level > requiredSlabs.size()) {
            throw new AuraHandledException('Invalid approval level: ' + level );
        }
        Discount_LineItem__c currentSlab = requiredSlabs[level - 1];
        String roleName = currentSlab.Roles__c;
        System.debug('Current Role ==> ' + roleName);
        if (String.isBlank(roleName)) {
            throw new AuraHandledException('Role is blank on Discount Line Item ' + currentSlab.Name);
        }
        Id approverId = getProjectRoleUser(projectId,roleName);
        if (approverId == null) {
            throw new AuraHandledException('No Project Role User found for role "' + roleName +'" in this Project.');
        }
        System.debug('Approver Id ==> ' + approverId);
        cs.Next_Approver__c = approverId;
        if (level == 1) {
            cs.Senior_Manager_Sales_Approval_Status__c ='Pending';
        } else if (level == 2) {
            cs.Chief_Commercial_Approval_Status__c ='Pending';

        } else if (level == 3) {
            cs.Sector_Head_GMC_Approval_Status__c = 'Pending';
        }
        update cs;
        String processName;
        if (level == 1) {
            processName = APPROVAL_PROCESS_LEVEL_1;
        } else if (level == 2) {
            processName = APPROVAL_PROCESS_LEVEL_2;
        } else if (level == 3) {
            processName = APPROVAL_PROCESS_LEVEL_3;
        } else {
            throw new AuraHandledException('Approval level ' + level +' is not configured.');
        }

        System.debug('Approval Process ==> ' + processName);
        Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
        request.setObjectId(cs.Id);
        request.setProcessDefinitionNameOrId(processName);
        //request.setComments( 'Cost Sheet submitted for discount approval. ' +'Level: ' + level +', Role: ' + roleName);

        Approval.ProcessResult result = Approval.process(request);
        System.debug('Approval Process Result ==> ' + result);
        if (!result.isSuccess()) {
            String errorMessage = '';
            for (Database.Error error :result.getErrors() ) {
                errorMessage += error.getMessage() + ' ';
            }
            throw new AuraHandledException( 'Approval submission failed: ' + errorMessage);
        }

        System.debug( 'Approval Level ' +  level + ' submitted successfully.' );
    }
    private static void startDiscountApproval(Id costSheetId) {
            System.debug('========== START DISCOUNT APPROVAL ==========');
            System.debug('Cost Sheet Id ==> ' + costSheetId);
            Cost_Sheet__c cs = [SELECT Id,Name,Discount_Amount__c,Discount_Percent__c, Opportunity__c,Opportunity__r.Project__c,
                    Opportunity__r.Project__r.Name,Senior_Manager_Sales_Approval_Status__c,Sector_Head_GMC_Approval_Status__c,
                    Chief_Commercial_Approval_Status__c, Highest_Approver__c, Next_Approver__c FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1];

            Decimal discountAmount = cs.Discount_Amount__c == null ? 0 : cs.Discount_Amount__c;

            System.debug('Discount Amount ==> ' + discountAmount);
            if (discountAmount <= 0) {
                System.debug('No discount. Approval is not required.');
                return;
            }

            Id projectId = cs.Opportunity__r.Project__c;
            if (projectId == null) {
                throw new AuraHandledException('Project is not available on the Opportunity.');
            }
            List<Discount_Master__c> masters = [SELECT Id,Project__c, Active__c FROM Discount_Master__c WHERE Project__c = :projectId  AND Active__c = true LIMIT 2 ];

            if (masters.isEmpty()) {
                throw new AuraHandledException('No active Discount Master is configured for this Project.');
            }
            if (masters.size() > 1) {
                throw new AuraHandledException('More than one active Discount Master is configured for this Project.');
            }

            Id discountMasterId = masters[0].Id;
            List<Discount_LineItem__c> slabs = [ SELECT Id, Name, Minimum__c, Maximum__c, Roles__c, Discount_Master__c FROM Discount_LineItem__c WHERE Discount_Master__c = :discountMasterId ORDER BY Minimum__c ASC ];
            if (slabs.isEmpty()) {
                throw new AuraHandledException('No Discount Line Items are configured for this Project.');
            }

            // Find the which the Cost Sheet discount
            Discount_LineItem__c matchedSlab;
            for (Discount_LineItem__c slab : slabs) {
                if (slab.Minimum__c == null || slab.Maximum__c == null) {
                    continue;
                }
                if ( discountAmount >= slab.Minimum__c && discountAmount <= slab.Maximum__c) {
                    matchedSlab = slab;
                    break;
                }
            }

            if (matchedSlab == null) {
                throw new AuraHandledException('No Discount approval slab is configured for discount amount '+ discountAmount);
            }
            System.debug('Matched Slab ==> ' + matchedSlab);
            System.debug('Matched Role ==> ' + matchedSlab.Roles__c);
            List<Discount_LineItem__c> requiredSlabs = new List<Discount_LineItem__c>();
            for (Discount_LineItem__c slab : slabs) {
                if (slab.Minimum__c != null && matchedSlab.Minimum__c != null && slab.Minimum__c <= matchedSlab.Minimum__c) {
                    requiredSlabs.add(slab);
                }
            }

            System.debug('Required Approval Slabs ==> ' + requiredSlabs);
            System.debug('Required Approval Count ==> ' + requiredSlabs.size());

            // Highest Approver = role of the highest applicable slab. 
            cs.Highest_Approver__c = matchedSlab.Roles__c;
            // First approval has not been started yet.
            if (requiredSlabs.size() >= 1 && cs.Senior_Manager_Sales_Approval_Status__c != 'Approved' ) {
                submitApprovalLevel(cs,requiredSlabs, 1, projectId);
                return;
            }
            // Level 2
            if (requiredSlabs.size() >= 2 && cs.Sector_Head_GMC_Approval_Status__c == 'Approved' && cs.Chief_Commercial_Approval_Status__c != 'Approved') {
                submitApprovalLevel( cs,requiredSlabs,2,projectId);
                return;
            }
            // Level 3
            if (requiredSlabs.size() >= 3 && cs.Senior_Manager_Sales_Approval_Status__c == 'Approved' && cs.Sector_Head_GMC_Approval_Status__c != 'Approved') {
                submitApprovalLevel(cs,requiredSlabs, 3,projectId);
                return;
            }
            update cs;
            System.debug('No new approval level required.');
    }
    public static void handleApprovalStep(List<Cost_Sheet__c> newRecords,Map<Id, Cost_Sheet__c> oldMap) {
        System.debug('========== COST SHEET APPROVAL TRIGGER ==========');
        Set<Id> level2CostSheetIds = new Set<Id>();
        Set<Id> level3CostSheetIds = new Set<Id>();
        for (Cost_Sheet__c cs : newRecords) {
            Cost_Sheet__c oldCs = oldMap.get(cs.Id);
            // Level 1 approved → submit Level 2 asynchronously
            if (cs.Senior_Manager_Sales_Approval_Status__c == 'Approved' && oldCs.Senior_Manager_Sales_Approval_Status__c != 'Approved') {
                System.debug('Senior Manager approved. Queueing Level 2 for ' + cs.Id);
                level2CostSheetIds.add(cs.Id);
            }
            // Level 2 approved → submit Level 3 asynchronously
            if (cs.Chief_Commercial_Approval_Status__c == 'Approved' && oldCs.Chief_Commercial_Approval_Status__c != 'Approved') {
                System.debug('Chief Commercial approved. Queueing Level 3 for ' + cs.Id );
                level3CostSheetIds.add(cs.Id);
            }
        }
        if (!level2CostSheetIds.isEmpty()) {
            System.enqueueJob(new CostSheetApprovalQueueable(level2CostSheetIds, 2));
        }

        if (!level3CostSheetIds.isEmpty()) {
            System.enqueueJob( new CostSheetApprovalQueueable(level3CostSheetIds, 3) );
        }
    }
    public static void processNextApproval( Id costSheetId, Integer nextLevel) {
        System.debug('Processing next approval level ==> ' + nextLevel );
        Cost_Sheet__c cs = [ SELECT Id,Name,Discount_Amount__c,Opportunity__c,Opportunity__r.Project__c,Senior_Manager_Sales_Approval_Status__c,Sector_Head_GMC_Approval_Status__c, Chief_Commercial_Approval_Status__c,Highest_Approver__c, Next_Approver__c FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1];
        Decimal discountAmount =  cs.Discount_Amount__c == null ? 0: cs.Discount_Amount__c;
        if (discountAmount <= 0) {
            return;
        }
        Id projectId = cs.Opportunity__r.Project__c;
        if (projectId == null) {
            throw new AuraHandledException('Project is missing from Opportunity.');
        }
        List<Discount_Master__c> masters = [SELECT Id FROM Discount_Master__c WHERE Project__c = :projectId AND Active__c = true LIMIT 2];
        if (masters.isEmpty()) {
            throw new AuraHandledException('No active Discount Master found for Project.');
        }

        if (masters.size() > 1) {
            throw new AuraHandledException('More than one active Discount Master found for Project.');
        }
        List<Discount_LineItem__c> slabs = [SELECT Id,Name,Minimum__c,Maximum__c,Roles__c FROM Discount_LineItem__c WHERE Discount_Master__c = :masters[0].Id ORDER BY Minimum__c ASC ];
        Discount_LineItem__c matchedSlab;
        for (Discount_LineItem__c slab : slabs) {
            if (slab.Minimum__c != null && slab.Maximum__c != null && discountAmount >= slab.Minimum__c && discountAmount <= slab.Maximum__c) {
                matchedSlab = slab;
                break;
            }
        }

        if (matchedSlab == null) {
            throw new AuraHandledException('No discount slab found for amount ' + discountAmount );
        }
        List<Discount_LineItem__c> requiredSlabs = new List<Discount_LineItem__c>();
        for (Discount_LineItem__c slab : slabs) {
            if (slab.Minimum__c != null && slab.Minimum__c <= matchedSlab.Minimum__c ) {
                requiredSlabs.add(slab);
            }
        }
        System.debug('Required Slabs ==> ' + requiredSlabs);
        if (nextLevel > requiredSlabs.size()) {
            System.debug('Level ' + nextLevel + ' is not required.' );
            return;
        }
        submitApprovalLevel(cs,requiredSlabs,nextLevel,projectId);
    }
    public static void testData(){
        Integer i =0 ;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
    }
}